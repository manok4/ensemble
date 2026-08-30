#!/usr/bin/env bash
# tests/lint/en-brainstorm-glossary-boundary.test.sh
#
# Brainstorm is where terminology gets argued about, so it must READ the
# glossary — a design doc that settles a term against a glossary it never
# opened hands /en-plan two vocabularies. But it must never WRITE the glossary.
#
# docs/CONTEXT.md already has owners: en-setup seeds it, en-learn accretes,
# refines and retires terms. A third writer is how a shared artifact gets two
# conflicting formats. Timing says the same thing independently: the canonical
# term is frequently the thing the recommendation renames, so a term captured
# mid-dialogue is captured under the wrong name.
#
# The structural half of this guard is the useful half. Write rules live in
# references/glossary-rules.md; a skill that declares that file is claiming to
# write terms. en-brainstorm must not.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm glossary boundary"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
SKILL_DIR="$REPO_ROOT/skills/en-brainstorm"

# --- 1. it reads the glossary, in the bounded scan ---
# Match the gate's operative instruction, not the words "conflict gate" — the
# scan bullet mentions the gate in passing, and a phrase check was satisfied by
# that mention alone even with the gate itself deleted.
if grep -qF 'docs/CONTEXT.md' "$SKILL" \
   && grep -qiE 'before treating their wording as settled' "$SKILL" \
   && grep -qiE 'use the canonical name' "$SKILL"; then
  pass "the glossary is read in the scan, and conflicts are put to the user before the wording sticks"
else
  fail "en-brainstorm must read docs/CONTEXT.md and challenge conflicting terms before settling them"
fi

# The gate has to fire against a file the skill actually opened, so the glossary
# must be listed in the bounded scan itself — not merely named by the gate. A
# whole-file grep is satisfied by the gate's own mention and would stay green
# with the read removed.
scan_line=$(grep -n 'Existing-context scan' "$SKILL" | head -1 | cut -d: -f1)
next_step=$(awk -v p="$scan_line" 'NR>p && /^[0-9]+\. \*\*/ {print NR; exit}' "$SKILL")
ctx_in_scan=$(awk -v a="$scan_line" -v b="$next_step" 'NR>a && NR<b' "$SKILL" | grep -c 'docs/CONTEXT.md')

[ "${ctx_in_scan:-0}" -ge 1 ] \
  && pass "the glossary is one of the sources the bounded scan reads" \
  || fail "the glossary must be listed in the bounded scan" \
         "the conflict gate would check against a file the skill never opened"

# --- 2. the no-write rule is stated, with the reason ---
if grep -qiE 'Never write the glossary here' "$SKILL" \
   && grep -qiE '`?/en-learn`? owns' "$SKILL"; then
  pass "the no-write rule names /en-learn as the owner"
else
  fail "the no-write rule must be stated and must name the owner"
fi

# --- 3. structural: it must not carry or declare the write rules ---
violations=""
[ -f "$SKILL_DIR/references/glossary-rules.md" ] && violations="$violations carries-glossary-rules"
grep -q 'references/glossary-rules.md' "$SKILL" && violations="$violations declares-glossary-rules"
grep -qiE '(write|append|add) [^.]{0,40}(to )?`docs/CONTEXT\.md`' "$SKILL" && violations="$violations write-instruction"

[ -z "$violations" ] \
  && pass "en-brainstorm claims no write path into the glossary" \
  || fail "en-brainstorm claims no write path into the glossary" "$violations"

# --- 4. the owners are still the owners, so this boundary means something ---
owners=""
for s in en-setup en-learn; do
  grep -q 'references/glossary-rules.md' "$REPO_ROOT/skills/$s/SKILL.md" 2>/dev/null && owners="$owners $s"
done
[ "$(echo $owners | wc -w | tr -d ' ')" -eq 2 ] \
  && pass "the glossary's actual owners still declare the write rules:$owners" \
  || fail "the glossary's actual owners still declare the write rules" "found:${owners:- none}"

report
