#!/usr/bin/env bash
# tests/lint/agent-dispatch-resolves.test.sh
#
# A skill that spawns `subagent_type: "X"` needs X to exist wherever the skill
# installs. EN13 deleted seven reviewer agent definitions and absorbed their
# scopes into the peer briefs, but five skills kept naming them as subagent_type.
# The dispatch resolved only on machines whose install predated the deletion; a
# fresh install from main would have failed every one.
#
# It survived a full release because nothing checked, and it was found by
# reconciling foundation's agent catalog against the filesystem — a documentation
# audit, not a test. See TD9.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="agent dispatch resolves"

# Every subagent_type named anywhere in skills/ must have a definition in skills/.
unresolved=""
named=$(grep -rhoE 'subagent_type: "[a-z][a-z-]*"' "$REPO_ROOT/skills" 2>/dev/null \
        | sed 's/.*"\(.*\)"/\1/' | sort -u)
count=0
for a in $named; do
  count=$((count + 1))
  ls "$REPO_ROOT"/skills/*/agents/"$a".md >/dev/null 2>&1 || unresolved="$unresolved $a"
done

[ "$count" -ge 3 ] \
  && pass "found subagent_type references to check ($count distinct)" \
  || fail "found subagent_type references to check" "only $count — the scan is probably broken"

if [ -z "$unresolved" ]; then
  pass "every dispatched subagent_type has a definition in this repo"
else
  fail "every dispatched subagent_type has a definition in this repo" \
       "undefined:$unresolved"
fi

# The reverse: a skill that dispatches an agent must also CARRY it, since a skill
# installs alone and cannot reach another skill's directory.
missing=""
for skill in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$skill")
  for a in $(grep -rhoE 'subagent_type: "[a-z][a-z-]*"' "$skill" 2>/dev/null | sed 's/.*"\(.*\)"/\1/' | sort -u); do
    [ -f "$skill/agents/$a.md" ] || missing="$missing $name->$a"
  done
done
[ -z "$missing" ] && pass "every skill carries the agents it dispatches" \
                  || fail "every skill carries the agents it dispatches" "$missing"

# And declares them, so skill-payload stays consistent in both directions.
undeclared=""
for skill in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$skill")
  for f in "$skill"agents/*.md; do
    [ -f "$f" ] || continue
    a=$(basename "$f" .md)
    grep -q "^  - agents/$a.md\$" "$skill/SKILL.md" || undeclared="$undeclared $name->$a"
  done
done
[ -z "$undeclared" ] && pass "every carried agent is declared in requires:" \
                     || fail "every carried agent is declared in requires:" "$undeclared"

# The retired seven must not come back by name.
if grep -rqE 'subagent_type: "(correctness|testing|maintainability|standards|security|performance|migrations)-reviewer"' "$REPO_ROOT/skills" 2>/dev/null; then
  fail "no skill dispatches the retired per-dimension reviewers"
else
  pass "no skill dispatches the retired per-dimension reviewers"
fi

report
