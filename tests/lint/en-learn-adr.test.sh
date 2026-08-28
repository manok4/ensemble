#!/usr/bin/env bash
# tests/lint/en-learn-adr.test.sh
#
# A decision recorded as prose tells a future agent what was chosen. It does not
# tell them what they must now uphold, which is the part that changes their
# behaviour. "Invariants this creates" is the section that turns a decision into
# rules something can be checked against.
#
# Zero frontmatter is deliberate, not an omission. An ADR is read by a human or
# an agent following a link, never matched by a query, so every field would be
# bookkeeping nobody reads. The template carrying frontmatter is a regression.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-learn ADR format"

flat() { tr '\n' ' ' < "$1" | sed 's/[*_`]//g; s/  */ /g'; }

FMT="$REPO_ROOT/skills/en-learn/references/adr-format.md"
TMPL="$REPO_ROOT/skills/en-learn/references/templates/adr-template.md"
SKILL="$REPO_ROOT/skills/en-learn/SKILL.md"

assert_file_exists "$FMT"  "the ADR format reference exists"
assert_file_exists "$TMPL" "the ADR template exists"

# --- zero frontmatter --------------------------------------------------------
# The template is what gets copied. If it carries a YAML block, every ADR will.
if head -1 "$TMPL" | grep -q '^---$'; then
  fail "the template carries no frontmatter"
else
  pass "the template carries no frontmatter"
fi

flat "$FMT" | grep -qi 'no frontmatter\|zero frontmatter' \
  && pass "the format states that ADRs carry no frontmatter" \
  || fail "the format states that ADRs carry no frontmatter"

# --- title states the claim --------------------------------------------------
# "Plugin distribution" tells a reader nothing. "Ship as a Claude plugin; defer
# Codex" tells them the decision without opening the file.
flat "$FMT" | grep -qi 'states the claim\|title.*claim\|claim, not a topic' \
  && pass "the title must state the claim, not the topic" \
  || fail "the title must state the claim, not the topic"

# --- invariants --------------------------------------------------------------
# The section that makes an ADR actionable rather than archival.
grep -q '## Invariants this creates' "$FMT" \
  && pass "the format specifies an invariants section" \
  || fail "the format specifies an invariants section"

grep -q '## Invariants this creates' "$TMPL" \
  && pass "the template carries the invariants section" \
  || fail "the template carries the invariants section"

# --- amendment by dated update ----------------------------------------------
# Superseding a file scatters one decision across several; amending in place
# keeps the whole history where the reader already is.
flat "$FMT" | grep -qE '## Update, YYYY-MM-DD' \
  && pass "amendments use a dated in-place Update section" \
  || fail "amendments use a dated in-place Update section"

flat "$FMT" | grep -qi 'in place\|amended in place' \
  && pass "the format says amend in place rather than supersede" \
  || fail "the format says amend in place rather than supersede"

# --- numbering ---------------------------------------------------------------
flat "$FMT" | grep -qE 'NNNN|zero-pad' \
  && pass "the numbering scheme is specified" \
  || fail "the numbering scheme is specified"

# 'no.*renumber' also matched "no frontmatter ... renumber" elsewhere in the
# file, so removing the rule left the assertion green. Match the rule itself.
flat "$FMT" | grep -qi 'never renumber and never reuse' \
  && pass "numbers are never reused or renumbered" \
  || fail "numbers are never reused or renumbered"

# --- rejected alternatives ---------------------------------------------------
# The single most valuable thing an ADR holds: a tree records what exists, never
# what was rejected or why.
# Two weaker forms of this assertion passed while the section was deleted: the
# bare word 'rejected' matched the shape block, and so did the heading, because
# the shape block reproduces it inside a fence. Match the reason instead — prose
# that appears only in the section itself.
flat "$FMT" | grep -qi 'records what exists.*never what was rejected\|never record what was rejected' \
  && pass "rejected alternatives are recorded with their reason" \
  || fail "rejected alternatives are recorded with their reason"

# --- declared ----------------------------------------------------------------
for f in references/adr-format.md references/templates/adr-template.md; do
  grep -q "$f" "$SKILL" \
    && pass "$f is declared in en-learn's requires:" \
    || fail "$f is declared in en-learn's requires:"
done

report
