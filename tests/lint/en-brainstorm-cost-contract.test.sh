#!/usr/bin/env bash
# Guards the cost-pass wins that would otherwise silently regress:
#   1. the foundation.md scan stays bounded (it was ~51K tokens unbounded)
#   2. the design doc is validated before /en-plan consumes it

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm cost contract"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
DISPATCH="$REPO_ROOT/skills/en-brainstorm/references/research-dispatch.md"

# --- 1. the context scan is bounded: section-index first, never the whole file ---
if grep -qiE "Existing-context scan \(bounded\)" "$SKILL" \
   && grep -qF "grep -n '^#' docs/foundation.md" "$SKILL" \
   && grep -qiE "Never .cat. it whole" "$SKILL" \
   && grep -qiE "index only" "$SKILL"; then
  pass "foundation/learnings scan is bounded (section index; never read whole)"
else
  fail "the existing-context scan must stay bounded — section-index read, never a whole-file read"
fi

# --- 2. the design doc is linted before handoff, and brainstorm dispatches no scouts ---
if grep -qF 'bin/ensemble-lint --scope docs/designs' "$SKILL" \
   && grep -qiE "dispatches no scouts" "$DISPATCH"; then
  pass "design doc is lint-validated before handoff; no-scout contract is documented"
else
  fail "must lint the design doc before handoff and document the no-scout contract"
fi

# --- 3. every sub-agent dispatch names a read budget and a return contract ---
# An unspecified dispatch returns whatever it decides to, at whatever cost it
# picks, and approach quality is the whole output of this skill. The frontier
# rounds' fact lookup and the synthesis-time absence verifier share one agent,
# repo-fact-lookup, which owns the budget and the return shape; SKILL.md must
# dispatch it by name at both sites. The divergent approach generators state
# theirs in brainstorm-approaches.md.
APPROACHES="$REPO_ROOT/skills/en-brainstorm/references/brainstorm-approaches.md"
FACT="$REPO_ROOT/skills/en-brainstorm/agents/repo-fact-lookup.md"
unspecified=""
sites=$(grep -ciE 'dispatch(ing)? the `repo-fact-lookup` agent' "$SKILL")
[ "$sites" -ge 2 ] || unspecified="$unspecified fact-lookup:dispatch-sites=$sites"
grep -qiE '~[0-9]+ targeted reads' "$FACT"                   || unspecified="$unspecified fact-lookup:budget"
grep -qF 'file:line' "$FACT" && grep -qF '`absent`' "$FACT"   || unspecified="$unspecified fact-lookup:return"
grep -qF '`confirmed`' "$FACT" && grep -qF '`refuted`' "$FACT" && grep -qF '`unverifiable`' "$FACT" \
                                                              || unspecified="$unspecified verifier:return"
grep -qE '^model: ' "$FACT"                                   || unspecified="$unspecified fact-lookup:tier"
grep -qiE '^\*\*Budget\.\*\* Roughly [0-9]+ reads' "$APPROACHES" || unspecified="$unspecified approaches:budget"
grep -qiE 'Each agent returns' "$APPROACHES"                 || unspecified="$unspecified approaches:return"
[ -z "$unspecified" ] \
  && pass "both sub-agent dispatches name a read budget and a return contract" \
  || fail "both sub-agent dispatches name a read budget and a return contract" \
         "unspecified:$unspecified"

report
