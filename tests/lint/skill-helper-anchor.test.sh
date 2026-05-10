#!/usr/bin/env bash
# Drift guard for skill helper-path anchoring.
#
# Field-observed bug: en-build's fail-fast preflight listed bare-relative
# paths like `references/host-detect.md` and `bin/ensemble-detect-host`. The
# agent anchored these at the skill dir, but the install layout has shared
# helpers at the SOURCE ROOT (skill at $ROOT/skills/<name>/, helpers at
# $ROOT/{references,bin}/). Result: the preflight failed for installs that
# were actually correct.
#
# Other skills had the same anchor ambiguity but didn't fail-fast — they
# silently paid a discovery tax (probing multiple candidate paths) on every
# invocation.
#
# Fix: every backtick-wrapped `references/X` and `bin/Y` reference in skill
# bodies is now anchored at $ENSEMBLE_ROOT. This test enforces that
# convention so future contributors don't drop bare-relative paths back in.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="skill helper-path anchoring"

# Every skill MUST anchor its helper paths at $ENSEMBLE_ROOT. The initial
# scope of this fix was the 8 skills with active bin/ dispatches; the
# remaining 6 (en-brainstorm, en-debug, en-learn, en-qa, en-resolve-pr,
# en-ship) ALSO have process steps like "Source references/host-detect.md"
# that were anchoring incorrectly at the skill dir on the install layout
# this PR documents. Per PR #15 review, the drift guard now covers all 14.
TARGET_SKILLS="en-brainstorm en-build en-cross-review en-debug en-foundation en-guardrail en-learn en-plan en-qa en-resolve-pr en-review en-setup en-ship en-sweep"

# Sentinel that says "this skill has the helper-resolution preamble."
PREAMBLE_SENTINEL='**Helper resolution.**'

# --- Each target skill has the helper-resolution preamble ---
for skill in $TARGET_SKILLS; do
  f="$REPO_ROOT/skills/$skill/SKILL.md"
  if [ ! -f "$f" ]; then
    fail "[$skill] SKILL.md missing"
    continue
  fi
  if grep -qF "$PREAMBLE_SENTINEL" "$f"; then
    pass "[$skill] has Helper-resolution preamble"
  else
    fail "[$skill] missing Helper-resolution preamble (must explain \$ENSEMBLE_ROOT)"
  fi
done

# --- The preamble mentions $ENSEMBLE_ROOT, the install convention, and
#     fail-loudly behavior ---
for skill in $TARGET_SKILLS; do
  f="$REPO_ROOT/skills/$skill/SKILL.md"
  preamble_line=$(grep -F "$PREAMBLE_SENTINEL" "$f" | head -1)
  for keyword in '$ENSEMBLE_ROOT' 'install root' 'env var' 'Fail loudly'; do
    if echo "$preamble_line" | grep -qF "$keyword"; then
      pass "[$skill] preamble references: $keyword"
    else
      fail "[$skill] preamble missing keyword: $keyword"
    fi
  done
done

# --- No bare-relative `references/X.md` paths in the body of target skills ---
# Bare = backtick-wrapped, NOT preceded by $ENSEMBLE_ROOT/ or any directory
# component. Allow:
#   - The preamble line itself (mentions `references/X` literally).
#   - The installed-skill-relative `docs/plans/.../tech-debt-tracker.md`
#     (those are project-relative, not plugin-relative — different scope).
for skill in $TARGET_SKILLS; do
  f="$REPO_ROOT/skills/$skill/SKILL.md"
  # Strip the preamble line and check the rest.
  bare=$(grep -nE '`references/[a-zA-Z0-9_./-]+\.(md|yml|yaml)`' "$f" \
       | grep -v 'Helper resolution' \
       | grep -v '`references/X`' \
       || true)
  if [ -n "$bare" ]; then
    fail "[$skill] has unanchored \`references/...\` references" "$(echo "$bare" | head -3)"
  else
    pass "[$skill] no unanchored backtick-wrapped references/ paths"
  fi
done

# --- No bare-relative `bin/X` paths in the body (backtick-wrapped, no anchor) ---
# Pattern: backtick + bin/ + identifier (with or without a trailing space + args).
for skill in $TARGET_SKILLS; do
  f="$REPO_ROOT/skills/$skill/SKILL.md"
  bare=$(grep -nE '`bin/[a-zA-Z0-9_-]+(\b| )' "$f" \
       | grep -v 'Helper resolution' \
       | grep -v '`bin/Y`' \
       || true)
  if [ -n "$bare" ]; then
    fail "[$skill] has unanchored \`bin/...\` references" "$(echo "$bare" | head -3)"
  else
    pass "[$skill] no unanchored backtick-wrapped bin/ paths"
  fi
done

# --- en-build's preflight specifically lists all required helpers with the anchor ---
EN_BUILD="$REPO_ROOT/skills/en-build/SKILL.md"
for required_path in \
  '$ENSEMBLE_ROOT/references/host-detect.md' \
  '$ENSEMBLE_ROOT/references/build-orchestration.md' \
  '$ENSEMBLE_ROOT/references/build-handoff.md' \
  '$ENSEMBLE_ROOT/references/outside-voice.md' \
  '$ENSEMBLE_ROOT/references/severity.md' \
  '$ENSEMBLE_ROOT/references/finding-schema.md' \
  '$ENSEMBLE_ROOT/bin/ensemble-build-peer-prompt' \
  '$ENSEMBLE_ROOT/bin/ensemble-verify-peer-evidence'; do
  if grep -qF "$required_path" "$EN_BUILD"; then
    pass "[en-build] preflight lists anchored path: $required_path"
  else
    fail "[en-build] preflight missing anchored path: $required_path"
  fi
done

# --- Sanity: the anchored paths actually resolve in the source repo
#     (catches typos in the preflight list — if the path doesn't exist
#     in the plugin, /en-setup won't be able to install it either) ---
for path in \
  references/host-detect.md \
  references/build-orchestration.md \
  references/build-handoff.md \
  references/outside-voice.md \
  references/severity.md \
  references/finding-schema.md \
  bin/ensemble-build-peer-prompt \
  bin/ensemble-verify-peer-evidence; do
  if [ -e "$REPO_ROOT/$path" ]; then
    pass "plugin source has: $path"
  else
    fail "plugin source MISSING: $path (preflight references a non-existent helper)"
  fi
done

# --- en-guardrail's hook script is skill-local, not at root bin/. The
#     anchored path must reflect that and resolve to a real file. ---
GUARDRAIL_HOOK="$REPO_ROOT/skills/en-guardrail/bin/check-guardrail.sh"
GUARDRAIL_SKILL="$REPO_ROOT/skills/en-guardrail/SKILL.md"

if [ -f "$GUARDRAIL_HOOK" ]; then
  pass "en-guardrail hook script exists at skill-local path"
else
  fail "en-guardrail hook script missing at $GUARDRAIL_HOOK"
fi

if grep -qF '$ENSEMBLE_ROOT/skills/en-guardrail/bin/check-guardrail.sh' "$GUARDRAIL_SKILL"; then
  pass "en-guardrail SKILL.md anchors check-guardrail.sh at the skill-local path"
else
  fail "en-guardrail SKILL.md should anchor check-guardrail.sh at \$ENSEMBLE_ROOT/skills/en-guardrail/bin/"
fi

if grep -qE '`\$ENSEMBLE_ROOT/bin/check-guardrail\.sh`' "$GUARDRAIL_SKILL"; then
  fail "en-guardrail SKILL.md uses \$ENSEMBLE_ROOT/bin/check-guardrail.sh — that path doesn't exist; the script is skill-local"
else
  pass "en-guardrail SKILL.md does NOT use the wrong root-bin path"
fi

report
