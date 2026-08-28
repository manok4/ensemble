#!/usr/bin/env bash
# tests/lint/no-gate-bypass.test.sh
#
# The capture gate's value is entirely in its defaults: write nothing unless three
# conditions hold. A documented exemption is worth more than a bug, because it is
# the route a future edit widens — "bootstrap is exempt" becomes "retrofit is
# exempt" becomes an exemption nobody remembers the shape of.
#
# --bootstrap-patterns held exactly such an exemption, in its own words: entries
# that "fail condition 1 by construction". It dispatched an agent to read the
# codebase and file conventions as learnings, which is the thing the gate exists
# to reject — an agent recovers conventions from the tree without help.
#
# This also asserts no mode emits a frontmatter field the schema retired. The
# path-based sweep in U8/U9 could not see those: it matched paths, and a flag
# whose VALUES are category names, or frontmatter a mode emits, is neither.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="no gate bypass"

# --- the mode and its machinery are gone -------------------------------------
for token in 'bootstrap-patterns' 'source: bootstrap' 'bootstrap_run' 'requires_validation'; do
  hits=$(grep -rl -- "$token" "$REPO_ROOT/skills" 2>/dev/null || true)
  if [ -z "$hits" ]; then
    pass "no skill file references: $token"
  else
    fail "no skill file references: $token" "$(echo "$hits" | sed "s|$REPO_ROOT/||" | tr '\n' ' ')"
  fi
done

# File and declaration removed together — one without the other leaves either a
# dangling requirement or an undeclared file, and skill-payload catches only one
# of those directions.
n_files=$(ls "$REPO_ROOT"/skills/*/references/learn-bootstrap-patterns.md 2>/dev/null | wc -l | tr -d ' ')
n_decls=$(grep -rl 'references/learn-bootstrap-patterns.md' "$REPO_ROOT"/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$n_files" "0" "no carrier still holds the bootstrap reference"
assert_eq "$n_decls" "0" "no SKILL.md still declares the bootstrap reference"

# --- nothing claims a route around the gate ----------------------------------
LEARN="$REPO_ROOT/skills/en-learn/SKILL.md"
if grep -qi 'exempt from the capture gate' "$LEARN"; then
  fail "no mode claims an exemption from the capture gate"
else
  pass "no mode claims an exemption from the capture gate"
fi

# --- ingest no longer advertises a retired flag ------------------------------
# The flag's VALUES were category names. A path sweep cannot see that.
if grep -q -- '--category' "$LEARN"; then
  fail "ingest no longer advertises a --category flag"
else
  pass "ingest no longer advertises a --category flag"
fi

# --- no mode emits a retired frontmatter field -------------------------------
# Asserted across the whole skill so a later edit cannot reintroduce one quietly.
# Matched only at line start, which missed the realistic form
#   - Frontmatter: `confidence: 6`
# so reintroducing a retired field left this green. These fields have no
# legitimate mention left in the skill, so a plain search is both simpler and
# strictly stronger.
for field in 'category:' 'problem_type:' 'component:' 'confidence:'; do
  if grep -qF -- "$field" "$LEARN"; then
    fail "no mode emits the retired field: $field"
  else
    pass "no mode emits the retired field: $field"
  fi
done

# --- the lint rule that chased the flag goes with it -------------------------
LINT="$REPO_ROOT/skills/en-setup/references/templates/ensemble-lint"
if grep -q 'bootstrap-unvalidated' "$LINT"; then
  fail "ensemble-lint no longer defines learnings.bootstrap-unvalidated"
else
  pass "ensemble-lint no longer defines learnings.bootstrap-unvalidated"
fi

# --- the retrofit follow-up points somewhere real ----------------------------
# Removing the mode without repointing its callers leaves a dangling suggestion.
SETUP="$REPO_ROOT/skills/en-setup/SKILL.md"
if grep -q 'bootstrap-patterns' "$SETUP"; then
  fail "en-setup no longer suggests the removed mode"
else
  pass "en-setup no longer suggests the removed mode"
fi

grep -qi 'CONTEXT.md' "$SETUP" \
  && pass "en-setup's retrofit path points at glossary seeding instead" \
  || fail "en-setup's retrofit path points at glossary seeding instead"

report
