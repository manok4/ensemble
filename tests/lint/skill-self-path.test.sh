#!/usr/bin/env bash
# tests/lint/skill-self-path.test.sh
#
# A skill must not refer to itself by its repo path. `skills/en-sweep/scripts/x`
# resolves only from the root of this source checkout. Skills install one
# directory at a time into ~/.claude/skills/ and ~/.codex/skills/, where no
# `skills/` parent exists, so the path is a runtime failure for an invocation
# and a dead pointer for a citation.
#
# Written 2026-09-03. /en-sweep had three of these: its continuous-monitor
# invocation and two Reference-files entries, sitting alongside eleven correct
# $SKILL_DIR uses in the same file. Nothing caught the mix, which is what made
# it survive: each new one looked like the ones already there.
#
# ALLOWED, and why:
#   - An env-anchored absolute install path. /en-guardrail writes
#     ${ENSEMBLE_HOME:-...}/skills/en-guardrail/bin/check-guardrail.sh into the
#     host's settings.json. That is a path into the source checkout, chosen at
#     install time by a human, not a path the running skill resolves.
#   - A `path/to/` prefix, which marks the line as illustrative.
#   - tests/ and docs/, which legitimately address skills from the repo root.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="skill self-path"

for skill in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$skill")

  # Every line naming this skill by its repo path, minus the two allowed forms.
  # The ENSEMBLE_HOME test looks left of the match on the same line, so an
  # env-anchored path passes while a bare one on the next line still fails.
  offenders=$(grep -rn "skills/$name/" "$skill" 2>/dev/null \
    | grep -v 'ENSEMBLE_HOME' \
    | grep -v "path/to/skills/$name/" \
    || true)

  if [ -z "$offenders" ]; then
    pass "$name refers to itself by \$SKILL_DIR, not by repo path"
  else
    fail "$name refers to itself by \$SKILL_DIR, not by repo path" \
         "$(printf '%s' "$offenders" | sed "s|$REPO_ROOT/||" | cut -c1-120)"
  fi
done

report
