#!/usr/bin/env bash
# tests/lint/foundation-catalog-drift.test.sh
#
# foundation.md's skill and agent catalogs are prose describing a filesystem, so
# they rot silently: nothing fails when a skill is added or an agent deleted.
#
# Found by auditing docs/: the catalog listed 11 agents when the repo defined 4
# (EN13 deleted seven and the rows stayed) and 15 skills when there were 17. A
# second, fuller catalog in docs/workflow-and-catalog.md had rotted the same way
# and worse — 14 skills, 11 agents, still documenting two removed modes. It was
# deleted rather than repaired, since two copies of the same list is what let both
# drift unnoticed.
#
# This asserts the surviving copy against the filesystem it describes.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="foundation catalog drift"

F="$REPO_ROOT/docs/foundation.md"
assert_file_exists "$F" "foundation.md exists"

SKILLS=$(sed -n '/^## 5\. Skill Catalog/,/^## 6\./p' "$F")
AGENTS=$(sed -n '/^## 6\. Agent Catalog/,/^## 7\./p' "$F")

# --- every skill on disk appears, and nothing is listed that does not exist ---
missing=""
for s in $(ls -d "$REPO_ROOT"/skills/*/ 2>/dev/null | xargs -n1 basename); do
  printf '%s' "$SKILLS" | grep -q "\`$s\`" || missing="$missing $s"
done
[ -z "$missing" ] && pass "every skill on disk is in the catalog" \
                  || fail "every skill on disk is in the catalog" "missing:$missing"

phantom=""
for s in $(printf '%s' "$SKILLS" | grep -oE '`en-[a-z-]+`' | tr -d '`' | sort -u); do
  [ -d "$REPO_ROOT/skills/$s" ] || phantom="$phantom $s"
done
[ -z "$phantom" ] && pass "the catalog lists no skill that does not exist" \
                  || fail "the catalog lists no skill that does not exist" "phantom:$phantom"

# --- same both ways for agents ------------------------------------------------
# The agent gap was not stale prose: seven rows described agents five skills were
# still dispatching by subagent_type. See TD9.
on_disk=$(ls "$REPO_ROOT"/skills/*/agents/*.md 2>/dev/null | xargs -n1 basename | sed 's/\.md$//' | sort -u)
a_missing=""
for a in $on_disk; do
  printf '%s' "$AGENTS" | grep -q "\`$a\`" || a_missing="$a_missing $a"
done
[ -z "$a_missing" ] && pass "every agent on disk is in the catalog" \
                    || fail "every agent on disk is in the catalog" "missing:$a_missing"

a_phantom=""
for a in $(printf '%s' "$AGENTS" | grep -oE '^\| `[a-z-]+`' | tr -d '|` ' | sort -u); do
  printf '%s\n' $on_disk | grep -qx "$a" || a_phantom="$a_phantom $a"
done
[ -z "$a_phantom" ] && pass "the catalog lists no agent the repo does not define" \
                    || fail "the catalog lists no agent the repo does not define" "phantom:$a_phantom"

# --- one catalog, not two -----------------------------------------------------
# Two copies of the same list is the mechanism that let both rot.
if [ -e "$REPO_ROOT/docs/workflow-and-catalog.md" ]; then
  fail "there is exactly one skill/agent catalog" "docs/workflow-and-catalog.md is back"
else
  pass "there is exactly one skill/agent catalog"
fi

report
