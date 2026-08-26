#!/usr/bin/env bash
# tests/portability/anchored-invocation.test.sh
#
# EN12 U6. The Bash tool's working directory is the USER'S PROJECT, not the
# skill directory, on every host. A bare `bash scripts/x` therefore resolves
# against the project and exits 127. Every executed-shell call site is anchored
# to $SKILL_DIR instead, and this test runs from an unrelated directory — the
# condition that turns the bug on.
#
# The Compound Engineering plugin logged three separate path bugs learning this
# (#764, #811, #898), which is why the conversion got its own unit.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="anchored script invocation"

ELSEWHERE="$(mktemp -d)"
trap 'rm -rf "$ELSEWHERE"' EXIT INT TERM HUP

# --- no skill may name a script through the old install root ---
stale=$(grep -rl 'ENSEMBLE_ROOT/bin' "$REPO_ROOT/skills" 2>/dev/null || true)
assert_eq "" "$stale" "no skill resolves a script through \$ENSEMBLE_ROOT/bin"

# --- no bare executed-shell relative path survives ---
# `bash scripts/x` / `. scripts/x` with no anchor is the exit-127 shape.
bare=$(grep -rnE '(^|[^/"])(bash|sh|\. |source ) +scripts/[a-z-]+' "$REPO_ROOT/skills"/*/SKILL.md 2>/dev/null || true)
assert_eq "" "$bare" "no unanchored executed-shell path in any SKILL.md"

# --- the load-bearing trailing semicolon ---
# Without it a flattened block becomes an env-var prefix, $SKILL_DIR expands
# before the assignment lands, and the path collapses to /scripts/...
missing_semi=$(grep -rn 'SKILL_DIR="[^"]*"$' "$REPO_ROOT/skills"/*/SKILL.md 2>/dev/null \
                 | grep -v ';' || true)
assert_eq "" "$missing_semi" "every SKILL_DIR assignment keeps its trailing semicolon"

# --- every anchored path resolves to a script the skill actually carries ---
missing=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  skill=$(echo "$line" | sed -E 's|.*/skills/([^/]+)/.*|\1|')
  script=$(echo "$line" | grep -oE '\$SKILL_DIR/scripts/[A-Za-z0-9._-]+' | head -1 | sed 's|.*/||')
  [ -n "$script" ] || continue
  [ -f "$REPO_ROOT/skills/$skill/scripts/$script" ] || missing="$missing $skill/$script"
done < <(grep -rho '\$SKILL_DIR/scripts/[A-Za-z0-9._-]*' "$REPO_ROOT/skills"/*/SKILL.md \
           | sort -u | while read -r p; do grep -rl "$p" "$REPO_ROOT/skills"/*/SKILL.md | sed "s|\$|:$p|"; done)
assert_eq "" "$(echo $missing)" "every anchored path names a script the skill carries"

# --- the real condition: run them from somewhere else entirely ---
ran=0; failed=""
for skill_dir in "$REPO_ROOT"/skills/*/; do
  skill=$(basename "$skill_dir")
  [ -d "$skill_dir/scripts" ] || continue
  for s in "$skill_dir"scripts/*; do
    [ -x "$s" ] || continue
    case "$(basename "$s")" in
      ensemble-cli-smoke|ensemble-extract-json|ensemble-peer-invoke) continue ;;  # sourced libs, not CLIs
    esac
    # Written the way a SKILL.md writes it: assignment as its own statement,
    # terminated, THEN the call. The env-var-prefix form
    # (SKILL_DIR="..." bash "$SKILL_DIR/...") expands $SKILL_DIR before the
    # assignment takes effect — which is precisely the failure the trailing
    # semicolon exists to prevent, and which an earlier version of this test
    # walked straight into.
    out=$(cd "$ELSEWHERE" && SKILL_DIR="$skill_dir"; timeout 20 bash "$SKILL_DIR/scripts/$(basename "$s")" --help </dev/null 2>&1 | head -3)
    rc=$?
    ran=$((ran+1))
    case "$out" in
      *"No such file"*|*"command not found"*|*"unbound variable"*|*"127"*)
        failed="$failed $skill/$(basename "$s")" ;;
      *) [ "$rc" -le 2 ] || failed="$failed $skill/$(basename "$s")(rc=$rc)" ;;
    esac
  done
done
assert_eq "" "$failed" "every bundled script runs anchored from an unrelated cwd ($ran invocations)"

# --- negative control: the same calls WITHOUT the anchor must fail ---
probe=$(cd "$ELSEWHERE" && bash scripts/ensemble-lint --help 2>&1 | head -1)
case "$probe" in
  *"No such file"*|*"cannot open"*) pass "an unanchored call from an unrelated cwd does fail (the bug is real)" ;;
  *) fail "an unanchored call from an unrelated cwd does fail" "got: $probe" ;;
esac

report
