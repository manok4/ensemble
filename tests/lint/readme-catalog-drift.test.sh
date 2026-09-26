#!/usr/bin/env bash
# tests/lint/readme-catalog-drift.test.sh
#
# README.md's catalogs went stale with nothing noticing: on 2026-09-26 they said
# 14 skills and 11 agents while skills/ held 17 skills and 6 agent definitions,
# three skills had no row, row 11 was missing, and seven retired reviewer agents
# were still listed. foundation-catalog-drift guards foundation.md; this guards
# the README the same way, derived from skills/ rather than from a pinned count,
# so adding a skill or an agent fails here until the README says so.
#
#   EVERY SKILL, NO PHANTOMS   one row per skills/ directory, and no row for a
#                              skill that does not exist.
#   SAME NUMBERS AS §5.1       each row's number is the foundation's, so the two
#                              catalogs cannot disagree about ordering.
#   COUNTS ADD UP              the total sentence and the two headings match the
#                              rows and the directory count.
#   AGENTS AND DISPATCHERS     one row per agent definition, and each row's
#                              "Dispatched by" names exactly the skills that
#                              carry that agent.
#
# Negative controls at authoring: deleting the en-loop row, renumbering en-flow,
# changing "17 skills total" to 16, dropping repo-fact-lookup's row, and adding
# /en-qa to web-research's dispatchers each turned its assertion red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="README catalog drift"

README="$REPO_ROOT/README.md"
F="$REPO_ROOT/docs/foundation.md"
assert_file_exists "$README" "README.md exists"

SKILLS_SEC=$(sed -n '/^## Skill catalog/,/^## Agent catalog/p' "$README")
AGENTS_SEC=$(sed -n '/^## Agent catalog/,/^## Repository layout/p' "$README")
on_disk=$(ls -d "$REPO_ROOT"/skills/*/ | xargs -n1 basename | sort)
n_disk=$(printf '%s\n' "$on_disk" | grep -c .)

# README rows: "| <n> | `/en-x` | ..." -> "<n> en-x"
rows=$(printf '%s\n' "$SKILLS_SEC" | sed -n 's/^| \([0-9][0-9]*\) | `\/\(en-[a-z-]*\)` |.*/\1 \2/p')
readme_skills=$(printf '%s\n' "$rows" | awk '{print $2}' | sort)

missing=$(comm -23 <(printf '%s\n' "$on_disk") <(printf '%s\n' "$readme_skills") | tr '\n' ' ')
phantom=$(comm -13 <(printf '%s\n' "$on_disk") <(printf '%s\n' "$readme_skills") | tr '\n' ' ')
[ -z "${missing// }" ] && pass "every skill in skills/ has a README row" \
                       || fail "every skill in skills/ has a README row" "missing: $missing"
[ -z "${phantom// }" ] && pass "the README lists no skill that does not exist" \
                       || fail "the README lists no skill that does not exist" "phantom: $phantom"

# Foundation §5.1 rows: "| <n> | `en-x` | ..." -> "<n> en-x"
f_rows=$(sed -n '/^### 5\.1 Skill summary/,/^### 5\.2/p' "$F" | sed -n 's/^| \([0-9][0-9]*\) | `\(en-[a-z-]*\)` |.*/\1 \2/p' | sort -k2)
diffs=$(comm -3 <(printf '%s\n' "$rows" | sort -k2) <(printf '%s\n' "$f_rows") | tr -s '\t ' ' ')
[ -z "${diffs// }" ] && pass "each README row carries the same number as foundation §5.1" \
                     || fail "README and foundation §5.1 number the skills differently" "$diffs"

total=$(printf '%s\n' "$SKILLS_SEC" | sed -n 's/^\([0-9][0-9]*\) skills total: \([0-9][0-9]*\) lifecycle, \([0-9][0-9]*\) orthogonal\..*/\1 \2 \3/p' | head -1)
set -- $total
life_rows=$(printf '%s\n' "$SKILLS_SEC" | sed -n '/^### Lifecycle skills/,/^### Orthogonal skills/p' | grep -c '^| [0-9]')
orth_rows=$(printf '%s\n' "$SKILLS_SEC" | sed -n '/^### Orthogonal skills/,$p' | grep -c '^| [0-9]')
life_h=$(printf '%s\n' "$SKILLS_SEC" | sed -n 's/^### Lifecycle skills (\([0-9]*\))$/\1/p')
orth_h=$(printf '%s\n' "$SKILLS_SEC" | sed -n 's/^### Orthogonal skills (\([0-9]*\))$/\1/p')
if [ $# -eq 3 ] && [ "$1" -eq "$n_disk" ] && [ "$2" -eq "$life_rows" ] && [ "$3" -eq "$orth_rows" ] \
   && [ "$life_h" = "$life_rows" ] && [ "$orth_h" = "$orth_rows" ]; then
  pass "the total ($n_disk), the lifecycle and orthogonal counts and their headings all agree"
else
  fail "the README's skill counts disagree" \
       "sentence='${total:-none}' dirs=$n_disk rows=$life_rows/$orth_rows headings=${life_h:-?}/${orth_h:-?}"
fi

# --- agents -------------------------------------------------------------------
agents_disk=$(ls "$REPO_ROOT"/skills/*/agents/*.md 2>/dev/null | xargs -n1 basename | sed 's/\.md$//' | sort -u)
n_agents=$(printf '%s\n' "$agents_disk" | grep -c .)
agent_rows=$(printf '%s\n' "$AGENTS_SEC" | sed -n 's/^| `\([a-z-]*\)` |.*/\1/p' | sort)
[ "$agents_disk" = "$agent_rows" ] \
  && pass "the agent catalog lists exactly the agent definitions in skills/*/agents/" \
  || fail "the agent catalog differs from skills/*/agents/" \
          "disk: $(echo $agents_disk) | readme: $(echo $agent_rows)"
printf '%s\n' "$AGENTS_SEC" | grep -qE "^$n_agents agent definitions\." \
  && pass "the agent count sentence says $n_agents" \
  || fail "the agent catalog must open with '$n_agents agent definitions.'"

wrong=""
for a in $agents_disk; do
  carriers=$(ls "$REPO_ROOT"/skills/*/agents/"$a".md | awk -F/ '{print $(NF-2)}' | sort | tr '\n' ' ')
  said=$(printf '%s\n' "$AGENTS_SEC" | grep -E "^\| \`$a\` \|" | awk -F'|' '{print $(NF-1)}' \
         | grep -oE '/en-[a-z-]+' | tr -d / | sort -u | tr '\n' ' ')
  [ "$carriers" = "$said" ] || wrong="$wrong $a(carried by: ${carriers}| README: ${said})"
done
[ -z "$wrong" ] && pass "each agent's 'Dispatched by' names exactly the skills that carry it" \
                || fail "an agent's dispatchers differ from its carriers" "$wrong"

report
