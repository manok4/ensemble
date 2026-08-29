#!/usr/bin/env bash
# tests/lint/pointer-map-coverage.test.sh
#
# AGENTS.md is the map an agent reads first to find out where things live. An
# artifact location missing from it is invisible: the agent does not know to look,
# and nothing fails.
#
# EN14 introduced two new artifact locations (docs/CONTEXT.md, docs/decisions/)
# and the template was never updated. Its learnings row still named the retired
# taxonomy in prose — "Compounding learnings (bugs, patterns, decisions)" — which
# the EN14 sweep missed because the sweep matched PATHS and this was prose.
#
# Caught by a human reading the generated file, not by any test. Hence this one.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="pointer map coverage"

# Every artifact location a skill writes to must appear in the template's map.
LOCATIONS='docs/foundation.md docs/architecture.md docs/CONTEXT.md docs/decisions/ docs/learnings/ docs/plans/active/ docs/plans/completed/ docs/plans/tech-debt-tracker.md docs/designs/'

for tpl in "$REPO_ROOT"/skills/*/references/templates/agents-md-template.md; do
  [ -f "$tpl" ] || continue
  skill=$(basename "$(dirname "$(dirname "$(dirname "$tpl")")")")
  map=$(sed -n '/^## Where things live/,/^## /p' "$tpl")
  missing=""
  for loc in $LOCATIONS; do
    printf '%s' "$map" | grep -qF "$loc" || missing="$missing $loc"
  done
  [ -z "$missing" ] && pass "$skill's pointer map covers every artifact location" \
                    || fail "$skill's pointer map covers every artifact location" "missing:$missing"

  # The retired taxonomy must not survive as prose. Character classes so this
  # pattern cannot match itself.
  if printf '%s' "$map" | grep -qiE '[b]ugs, [p]atterns'; then
    fail "$skill's pointer map does not name the retired taxonomy"
  else
    pass "$skill's pointer map does not name the retired taxonomy"
  fi
done

# Both carriers byte-identical.
n=$(ls "$REPO_ROOT"/skills/*/references/templates/agents-md-template.md 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$n" "2" "two skills carry the AGENTS.md template"
d=$(for f in "$REPO_ROOT"/skills/*/references/templates/agents-md-template.md; do hash_file "$f"; done | sort -u | wc -l | tr -d ' ')
assert_eq "$d" "1" "both carried copies of the template are identical"

# A generated AGENTS.md must not carry the template's own documentation.
if [ -f "$REPO_ROOT/AGENTS.md" ]; then
  for leak in 'Notes on generation' 'Append-merge mode'; do
    if grep -q "$leak" "$REPO_ROOT/AGENTS.md"; then
      fail "the generated AGENTS.md excludes template documentation: $leak"
    else
      pass "the generated AGENTS.md excludes template documentation: $leak"
    fi
  done
  grep -qF 'docs/CONTEXT.md' "$REPO_ROOT/AGENTS.md" \
    && pass "the generated AGENTS.md points at the glossary" \
    || fail "the generated AGENTS.md points at the glossary"
fi

report
