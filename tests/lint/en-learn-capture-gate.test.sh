#!/usr/bin/env bash
# tests/lint/en-learn-capture-gate.test.sh
#
# The capture gate is the whole point of en-learn's capture mode: coding agents
# reconstruct what and how from the tree, so a wiki restating that makes them
# read more to learn less. The gate's value is entirely in its defaults — write
# nothing unless three conditions hold, each answered by NAMING something — and
# defaults erode quietly under later edits.
#
# What this locks down is the shape that keeps the gate honest, not its wording.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-learn capture gate"

SKILL="$REPO_ROOT/skills/en-learn/SKILL.md"
GATE="$REPO_ROOT/skills/en-learn/references/capture-gate.md"
TMPL="$REPO_ROOT/skills/en-learn/references/templates/learning-template.md"

assert_file_exists "$GATE" "the gate reference exists"

# --- the gate is reachable and runs before the work ---
grep -q 'references/capture-gate.md' "$SKILL" \
  && pass "capture reads the gate" || fail "capture reads the gate"
gate_line=$(grep -n 'references/capture-gate.md' "$SKILL" | head -1 | cut -d: -f1)
compose_line=$(grep -n 'Compose entry' "$SKILL" | head -1 | cut -d: -f1)
[ "$gate_line" -lt "$compose_line" ] \
  && pass "the gate is applied before the entry is composed" \
  || fail "the gate is applied before the entry is composed" "gate:$gate_line compose:$compose_line"

# --- the default must be to write nothing ---
# Scoped to the capture FLOW, not the whole file. The description also states
# the default, so a file-wide grep passed even with the step text deleted — the
# assertion has to pin where the instruction lives, or it checks marketing copy.
capture_flow=$(sed -n '/^## Process — Mode A/,/^## Process — Mode B/p' "$SKILL")
echo "$capture_flow" | grep -qi 'default is to write nothing' \
  && pass "the capture flow itself states the write-nothing default" \
  || fail "the capture flow itself states the write-nothing default"
grep -qi 'default is to write nothing' "$GATE" \
  && pass "the gate states the write-nothing default" || fail "the gate states the write-nothing default"

# --- three conditions, all required, each naming something ---
for c in 'Not recoverable from the code' 'Changes a future action' 'Outlives the occasion'; do
  grep -qF "$c" "$GATE" && pass "gate condition present: $c" || fail "gate condition present: $c"
done
grep -qi 'all three must hold' "$GATE" \
  && pass "the conditions are conjunctive, not a menu" || fail "the conditions are conjunctive, not a menu"
grep -qiE 'cannot name|unnamed answer' "$GATE" \
  && pass "an unnamed answer fails the condition" || fail "an unnamed answer fails the condition"

# --- a rejected capture is reported, never silent ---
grep -qiE 'report which condition failed' "$GATE" \
  && pass "the gate requires reporting which condition failed" || fail "the gate requires reporting which condition failed"
grep -qiE 'silent skip is indistinguishable' "$GATE" \
  && pass "the gate says why a silent skip is unacceptable" || fail "the gate says why a silent skip is unacceptable"

# --- bookkeeping is not conditional on filing content ---
# Regression guard: a plan left at in_progress because nothing was captured is
# the exact orphaning bug step 11 was unbundled to prevent.
grep -qiE 'bookkeeping is not conditional|11a.*always runs|always runs.*11a' "$SKILL" \
  && pass "lifecycle bookkeeping still runs when the gate rejects" \
  || fail "lifecycle bookkeeping still runs when the gate rejects"

# --- one learning per run ---
grep -qi 'one learning per run' "$GATE" \
  && pass "one learning per run, so batching cannot carry a weak entry" \
  || fail "one learning per run"

# --- the template must not reimpose mandatory sections ---
assert_file_exists "$TMPL" "the template exists"
grep -qiE 'one paragraph until it earns more' "$TMPL" \
  && pass "the template defaults to a paragraph" || fail "the template defaults to a paragraph"
for dead in '## TL;DR' '## Context' "## What didn't work" '## Prevention' '## Root cause'; do
  # Allowed only as an anti-example; a bare heading at line start is the tell.
  if grep -qE "^${dead}$" "$TMPL"; then
    fail "the template no longer mandates '$dead'"
  else
    pass "the template no longer mandates '$dead'"
  fi
done
grep -qi 'Optional sections' "$TMPL" \
  && pass "extra sections are optional and must earn their place" || fail "extra sections are optional"

# --- the categories the gate exists to admit ---
for q in 'Constraints that live outside the code' 'Paths not taken' 'Deliberate deviations' 'do not announce themselves'; do
  grep -qF "$q" "$GATE" && pass "qualifying category kept: $q" || fail "qualifying category kept: $q"
done
# --- and the ones it exists to reject ---
for n in 'How the code works' 'What a fix changed' 'Point-in-time state'; do
  grep -qF "$n" "$GATE" && pass "rejected category kept: $n" || fail "rejected category kept: $n"
done

# --- no exemption survives ---------------------------------------------------
# --bootstrap-patterns held the only documented route around the gate, and is
# gone (U15). A documented exemption is worse than a bug: it is the seam a later
# edit widens. tests/lint/no-gate-bypass.test.sh owns that assertion now.

# --- The generalization step -------------------------------------------------
# Several candidates sharing a cause are one learning. Without this step the gate
# admits four near-duplicate entries and calls each of them individually correct.

grep -q 'Generalize before you write' "$GATE" \
  && pass "the gate has a generalization step" || fail "the gate has a generalization step"

grep -qi 'is this an instance of something' "$GATE" \
  && pass "generalization is posed as a question asked before writing" \
  || fail "generalization is posed as a question asked before writing"

grep -qi 'share a cause, not a topic' "$GATE" \
  && pass "the class test is cause-based, not topic-based" \
  || fail "the class test is cause-based, not topic-based"

grep -qi 'extend it' "$GATE" \
  && pass "an existing class entry is extended rather than duplicated" \
  || fail "an existing class entry is extended rather than duplicated"

# --- Frontmatter schema: reduced field set -----------------------------------
SCHEMA="$REPO_ROOT/skills/en-learn/references/learning-frontmatter-schema.md"
assert_file_exists "$SCHEMA" "the frontmatter schema exists"

for dropped in problem_type confidence; do
  grep -q "^| \`$dropped\`" "$SCHEMA" \
    && fail "$dropped is no longer a schema field" \
    || pass "$dropped is no longer a schema field"
done

grep -q 'The retrieval field' "$SCHEMA" \
  && pass "applies_when is marked as the retrieval field" \
  || fail "applies_when is marked as the retrieval field"

grep -qi 'Write the \*\*situation\*\*, not the subject' "$SCHEMA" \
  && pass "the schema says to write the situation, not the subject" \
  || fail "the schema says to write the situation, not the subject"

# --- Schema parity across carriers -------------------------------------------
# The schema is duplicated per self-contained skill. Derive carriers from the
# filesystem so that deleting a copy cannot make this check quietly vacuous.
CARRIERS=$(ls "$REPO_ROOT"/skills/*/references/learning-frontmatter-schema.md 2>/dev/null | wc -l | tr -d ' ')
[ "$CARRIERS" -ge 2 ] \
  && pass "at least two skills carry the schema ($CARRIERS)" \
  || fail "at least two skills carry the schema (found $CARRIERS)"

REF_SUM=$(shasum "$SCHEMA" | cut -d' ' -f1)
SKEW=0
for c in "$REPO_ROOT"/skills/*/references/learning-frontmatter-schema.md; do
  [ "$(shasum "$c" | cut -d' ' -f1)" = "$REF_SUM" ] || SKEW=$((SKEW+1))
done
[ "$SKEW" -eq 0 ] \
  && pass "every carried copy of the schema is byte-identical" \
  || fail "every carried copy of the schema is byte-identical ($SKEW diverged)"

# --- U5: capture routes to an artifact type ----------------------------------
# The gate decides WHETHER to write; the router decides WHICH artifact. A router
# that ran first would classify candidates that should never be written at all.
#
# SCOPE (TD7): routing is a model judgment. These assertions check that the
# specification is wired into the skill and that the fixture corpus exists. They
# do NOT show that a candidate routes correctly — no shell assertion reaches it.

flatf() { tr '\n' ' ' < "$1" | sed 's/[*_`]//g; s/  */ /g'; }

grep -q 'references/artifact-types.md' "$SKILL" \
  && pass "capture reads the artifact-types reference" \
  || fail "capture reads the artifact-types reference"

# The retired taxonomy must be gone from the capture flow, not merely unused.
if flatf "$SKILL" | grep -qE 'Identify category|bugs/ \(|patterns/ \(|decisions/ \('; then
  fail "the four-category step is gone from capture"
else
  pass "the four-category step is gone from capture"
fi

# Ordering: the gate is step 4, the router follows it.
gate_ln=$(grep -n 'Apply the capture gate' "$SKILL" | head -1 | cut -d: -f1)
route_ln=$(grep -n 'Route to an artifact type' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$gate_ln" ] && [ -n "$route_ln" ] && [ "$gate_ln" -lt "$route_ln" ]; then
  pass "the gate runs before the router (lines $gate_ln < $route_ln)"
else
  fail "the gate runs before the router" "gate=$gate_ln router=$route_ln"
fi

# --- the fixture corpus ------------------------------------------------------
# Not executed here. It is what TD7's eval suite will run, and the source of the
# worked examples that guide the model doing the routing.
FIX="$REPO_ROOT/tests/fixtures/routing"
assert_file_exists "$FIX/README.md" "the routing fixture corpus is documented"

for t in term decision solution; do
  n=$(grep -l "^expect_type: $t\$" "$FIX"/*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 1 ] \
    && pass "the corpus has a candidate expected to route to $t" \
    || fail "the corpus has a candidate expected to route to $t"
done

# Both tie-break directions, and a candidate the gate rejects outright.
[ "$(grep -l '^tie_break:' "$FIX"/*.md 2>/dev/null | wc -l | tr -d ' ')" -ge 2 ] \
  && pass "the corpus covers both tie-break directions" \
  || fail "the corpus covers both tie-break directions"

grep -q '^expect_type: none$' "$FIX"/*.md \
  && pass "the corpus includes a gate-rejected candidate" \
  || fail "the corpus includes a gate-rejected candidate"

# The README must not claim the fixtures are executed — that would be the exact
# overclaim TD7 exists to prevent.
flatf "$FIX/README.md" | grep -qi 'not run by any shell test\|not executed' \
  && pass "the corpus states plainly that it is not executed" \
  || fail "the corpus states plainly that it is not executed"

report
