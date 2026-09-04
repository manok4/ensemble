#!/usr/bin/env bash
# tests/lint/peer-prompt-invocation.test.sh
#
# Each peer skill documents, in its own SKILL.md, the command that builds the
# peer prompt. On 2026-09-04 en-review's documented command exited 2 ("unknown
# flag: --artifact-type") and omitted the --brief the script requires: D50
# moved review dimensions into per-skill briefs, en-plan's call was updated,
# en-review's was not. Since --peer is en-review's default and makes the peer
# the sole reviewer, a plain /en-review following its own text had no reviewer.
# All three skills also passed the brief as `references/peer-brief.md`, which
# the script opens relative to the CALLER's cwd, the user's project at runtime,
# not the skill directory.
#
# So: pull the documented command out of each SKILL.md, fill its placeholders,
# and run it from a directory that is not the skill's. A documented invocation
# that does not execute is the class of defect no prose guard can see.
#
# Negative control at authoring: reverting en-review's line to the
# --artifact-type form turned its clause red; passing a bare
# `references/peer-brief.md` from the foreign cwd turned all three red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="documented peer-prompt invocations run"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# The foreign cwd is a stand-in for the user's project, so project-relative
# artifact paths a skill legitimately uses (en-foundation reviews
# docs/foundation.md) must resolve there.
mkdir -p "$T/elsewhere/docs"
printf 'diff --git a/x.ts b/x.ts\n+export const one = 1;\n' > "$T/artifact.diff"
printf -- '---\ntype: plan\n---\n# P\n### U1. Thing\n- **Goal:** x\n' > "$T/artifact.plan.md"
printf -- '---\ntype: foundation\n---\n# F\n' > "$T/elsewhere/docs/foundation.md"

checked=0
for skill in en-plan en-review en-foundation; do
  dir="$REPO_ROOT/skills/$skill"
  cmd=$(grep -oE '`\$SKILL_DIR/scripts/ensemble-build-peer-prompt [^`]*`' "$dir/SKILL.md" | head -1 | tr -d '`')
  if [ -z "$cmd" ]; then
    fail "$skill documents a prompt-builder command" "no backticked invocation found in SKILL.md"
    continue
  fi
  checked=$((checked + 1))
  # Fill the placeholders the prose uses; leave every real flag as written.
  filled=$(printf '%s' "$cmd" \
    | sed -e "s|\$SKILL_DIR|$dir|g" \
          -e "s|<diff>|$T/artifact.diff|g" \
          -e "s|<plan-path>|$T/artifact.plan.md|g" \
          -e "s|<path>|$T/artifact.diff|g" \
          -e 's|"<one-line[^"]*>"|"context"|g' \
          -e 's|"<one line[^"]*>"|"context"|g' \
          -e 's|"\$PEER_MODE"|cross-agent|g')
  out=$(cd "$T/elsewhere" && eval "$filled" 2>"$T/err.$skill"); rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "REPORTER"; then
    pass "$skill: the documented prompt-builder command runs from a foreign cwd"
  else
    fail "$skill: the documented prompt-builder command runs from a foreign cwd" \
         "rc=$rc stderr=$(head -c 160 "$T/err.$skill" | tr '\n' ' ') cmd=$filled"
  fi
done
[ "$checked" -eq 3 ] && pass "all three peer skills were checked" || fail "all three peer skills were checked" "checked=$checked"

# --- en-review --lite: the same documented command with the lite brief (D79) ---
dir="$REPO_ROOT/skills/en-review"
cmd=$(grep -oE '`\$SKILL_DIR/scripts/ensemble-build-peer-prompt [^`]*`' "$dir/SKILL.md" | head -1 | tr -d '`')
filled=$(printf '%s' "$cmd" \
  | sed -e "s|\$SKILL_DIR|$dir|g" \
        -e "s|references/peer-brief.md|references/peer-brief-lite.md|g" \
        -e "s|<diff>|$T/artifact.diff|g" \
        -e 's|"<one-line[^"]*>"|"context"|g' \
        -e 's|"\$PEER_MODE"|cross-agent|g')
out=$(cd "$T/elsewhere" && eval "$filled" 2>"$T/err.lite"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "REPORTER" \
   && printf '%s' "$out" | grep -q "lite review" && ! printf '%s' "$out" | grep -q '^### testing'; then
  pass "en-review --lite: the documented command runs with the lite brief and carries its dimensions"
else
  fail "en-review --lite: the documented command runs with the lite brief and carries its dimensions" \
       "rc=$rc stderr=$(head -c 160 "$T/err.lite" | tr '\n' ' ')"
fi

report
