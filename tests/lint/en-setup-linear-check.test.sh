#!/usr/bin/env bash
# tests/lint/en-setup-linear-check.test.sh
#
# EN19 U7. Before the first publish, /en-setup confirms the Linear workspace
# can carry a plan: the team, the four workflow states by name, python3 for
# ensemble-linear-plan, and the GitHub integration mapping, which no MCP tool
# can read and so is confirmed by the operator and recorded.
#
# The check is model-followed (MCP calls), so this guards the prose. The
# clauses that matter: states matched by name (In Progress and In Review share
# a type), local mode making no MCP call, and the mapping spelled out so an
# operator can see why PR open must not map to an earlier state.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-setup linear check"

SKILL="$REPO_ROOT/skills/en-setup/SKILL.md"
CHECK="$REPO_ROOT/skills/en-setup/references/setup-linear-check.md"
PUB="$REPO_ROOT/skills/en-plan/references/linear-publish.md"
TPL="$REPO_ROOT/skills/en-setup/references/templates/config-local-example.yaml"
EXAMPLE="$REPO_ROOT/.ensemble/config.local.example.yaml"

has()   { grep -qiE -- "$2" "$1" && pass "$3" || fail "$3" "missing from $(basename "$1"): $2"; }
has_near() { tr '\n' ' ' < "$1" | grep -qiE -- "$2" && pass "$3" || fail "$3" "not found together in $(basename "$1"): $2"; }

assert_file_exists "$CHECK" "the Linear check reference exists"

# --- 1. routed from both entry points, and only in linear mode ---------------
state3=$(awk '/^## State 3/{f=1; next} f&&/^## /{exit} f' "$SKILL")
assert_contains "$state3" 'references/setup-linear-check.md' "State 3's diagnostic routes to the Linear check"
step15=$(awk '/^15\. \*\*Final verification/{f=1} f&&/^16\. /{exit} f' "$SKILL")
assert_contains "$step15" 'references/setup-linear-check.md' "State 2's final verification routes to it too"
has "$CHECK" 'Absent or\s*$|Absent or `local`, skip the whole check' "absent or local skips the whole check"
has_near "$CHECK" 'skip the whole check: no MCP call' "and makes no MCP call in local mode"

# --- 2. what it checks ---------------------------------------------------------
has "$CHECK" 'list_teams' "the team key is confirmed over MCP"
has "$CHECK" 'list_issue_statuses' "the workflow states are read over MCP"
for st in 'Agent Ready' 'In Progress' 'In Review' 'Done'; do
  has "$CHECK" "\`$st\`" "the check names the state: $st"
done
has "$CHECK" '\*\*by name\*\*, never by type' "states are matched by name, never by type"
has "$CHECK" 'share the type `started`' "and the prose says why"
has "$CHECK" 'missing or duplicated' "a missing or duplicated state is red, naming it"
has "$CHECK" 'command -v python3' "python3 is checked, since ensemble-linear-plan needs it"
has "$CHECK" 'No Linear MCP server in this session' "a session without the Linear MCP server is reported, not crashed"

# --- 3. the GitHub mapping -------------------------------------------------------
has "$CHECK" 'linear_github_confirmed: true' "the confirmation is recorded as linear_github_confirmed"
has "$CHECK" '🟡 unset' "unset is yellow, not red"
has_near "$CHECK" 'PR open:\*\* `In Review`, or no automation' "the required PR-open mapping is printed"
has_near "$CHECK" 'moves the parent \*\*backwards\*\*' "and the prose says why an earlier state is wrong"
has_near "$CHECK" 'Merge:\*\* `Done`' "the required merge mapping is printed"
has "$TPL" 'linear_github_confirmed' "the en-setup template documents the key"
has "$EXAMPLE" 'linear_github_confirmed' "the repo's example config documents the key"
has "$PUB" 'linear_github_confirmed --allowed true,false' "publish reads the key"
has_near "$PUB" 'warn[^#]{0,200}and continue' "and warns without blocking when it is unset"

report
