#!/usr/bin/env bash
# tests/lint/en-learn-glossary.test.sh
#
# docs/CONTEXT.md is the artifact that answers the question code cannot: which of
# three synonyms is canonical, what was rejected, which ambiguity got settled. A
# reader can recover what the code does; they cannot recover the team's agreed
# vocabulary, because the losing words are not in the tree.
#
# Two rules do the work and both erode quietly. "Be opinionated" is what stops
# the file becoming a record of every word anyone used. "Stands on its own" is
# what stops it filling with file paths and config numbers that rot.
#
# Scope: writing an entry is model behaviour. These assertions lock the
# specification and the template. TD7 tracks behavioural coverage.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-learn glossary"

# Prose gets reflowed. An assertion that greps a single line goes red when a
# sentence wraps, which is a false failure about formatting, not content. Flatten
# to one line and strip markdown emphasis before matching.
flat() { tr '\n' ' ' < "$1" | sed 's/[*_`]//g; s/  */ /g'; }

RULES="$REPO_ROOT/skills/en-learn/references/glossary-rules.md"
TMPL="$REPO_ROOT/skills/en-learn/references/templates/context-template.md"
SKILL="$REPO_ROOT/skills/en-learn/SKILL.md"

assert_file_exists "$RULES" "the glossary rules exist"
assert_file_exists "$TMPL"  "the CONTEXT.md template exists"

# --- be opinionated ----------------------------------------------------------
# A glossary that lists every word the team ever used has not made a decision,
# and the reader still does not know which one to write.
flat "$RULES" | grep -qi 'opinionated' \
  && pass "the rules tell the writer to be opinionated" \
  || fail "the rules tell the writer to be opinionated"

grep -q '_Avoid:_\|\*Avoid:\*' "$RULES" \
  && pass "retired synonyms use the Avoid convention" \
  || fail "retired synonyms use the Avoid convention"

# --- stands on its own -------------------------------------------------------
# Each exclusion is a category of rot. Losing any one of them is how the file
# turns into documentation that contradicts the code six months later.
for excl in 'file path' 'date' 'owner' 'version' 'PR'; do
  grep -qi "$excl" "$RULES" \
    && pass "exclusion stated: $excl" \
    || fail "exclusion stated: $excl"
done

flat "$RULES" | grep -qi 'state the behavior, not the number\|state the behaviour, not the number' \
  && pass "config values are excluded by stating behaviour, not the number" \
  || fail "config values are excluded by stating behaviour, not the number"

# --- what earns a slot -------------------------------------------------------
# Without a bar, general programming vocabulary floods the file.
flat "$RULES" | grep -qi 'new engineer would need' \
  && pass "the qualifying bar is the new-engineer test" \
  || fail "the qualifying bar is the new-engineer test"

flat "$RULES" | grep -qi 'general programming vocabulary' \
  && pass "general programming vocabulary is excluded" \
  || fail "general programming vocabulary is excluded"

# --- the ambiguities tail ----------------------------------------------------
# This section is the audit trail: it records opinions the team has formed, which
# is the one thing a reader can never reconstruct from the code.
grep -q 'Flagged ambiguities' "$RULES" \
  && pass "the rules specify a flagged-ambiguities tail" \
  || fail "the rules specify a flagged-ambiguities tail"

grep -q 'Flagged ambiguities' "$TMPL" \
  && pass "the template carries the ambiguities tail" \
  || fail "the template carries the ambiguities tail"

# --- the template renders ----------------------------------------------------
# An unrendered placeholder shipped into a real repo is a template leak.
if grep -q '{{' "$TMPL"; then
  fail "the template has no unrendered placeholders"
else
  pass "the template has no unrendered placeholders"
fi

# --- declared ----------------------------------------------------------------
for f in references/glossary-rules.md references/templates/context-template.md; do
  grep -q "$f" "$SKILL" \
    && pass "$f is declared in en-learn's requires:" \
    || fail "$f is declared in en-learn's requires:"
done

report
