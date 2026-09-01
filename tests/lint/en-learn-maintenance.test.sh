#!/usr/bin/env bash
# tests/lint/en-learn-maintenance.test.sh
#
# --refresh and --lint maintain the store. Both predated the artifact-type split
# and kept describing a single flat store, which is a quieter failure than a
# broken check: a maintenance mode that only sees one of three types reports the
# store healthy while two thirds of it goes unmaintained.
#
# The sharpest case is not coverage but MODEL. keep/update/replace/archive is a
# solution lifecycle. An ADR is append-only and amended with a dated Update
# section — "replace" is the operation its format exists to prevent. Pointing one
# lifecycle at three shapes corrupts the two it was not written for.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-learn maintenance"

SKILL="$REPO_ROOT/skills/en-learn/SKILL.md"
LINT="$REPO_ROOT/skills/en-learn/references/learn-lint.md"

REFRESH=$(sed -n '/^## Process — Mode B: `--refresh`/,/^## Process — Mode C/p' "$SKILL")

# --- the dead check is gone --------------------------------------------------
# data-gaps recommended `learn ingest`, removed in U16. A check that recommends a
# mode nobody can run is worse than no check: it reads as actionable.
for token in 'data-gaps' 'learn ingest' 'Suggested ingests'; do
  if grep -qF -- "$token" "$LINT"; then
    fail "learn-lint no longer references: $token"
  else
    pass "learn-lint no longer references: $token"
  fi
done

# --- refresh covers all three types, each with its own lifecycle -------------
for t in 'CONTEXT.md' 'decisions/' 'learnings/'; do
  printf '%s' "$REFRESH" | grep -qF "$t" \
    && pass "refresh covers $t" \
    || fail "refresh covers $t"
done

# An ADR is amended, never replaced. This is the assertion that catches someone
# extending refresh by pointing the solution lifecycle at the other two types.
# Scoped to the Decisions ROW. Matching the whole refresh block also hit the
# Terms paragraph ("rather than deleting it"), so swapping the row for a solution
# lifecycle left this green.
# The guarantee is not "never replaced" — a reversed decision does get a successor
# ADR. It is that replacement is never SILENT: the old file survives with a
# forward pointer, so the reasoning is never lost.
printf '%s' "$REFRESH" | grep '^| \*\*Decisions\*\*' | grep -qi 'never silently replaced' \
  && pass "refresh's Decisions row rules out silent replacement" \
  || fail "refresh's Decisions row rules out silent replacement"

printf '%s' "$REFRESH" | tr '\n' ' ' | grep -qi 'old file is never deleted or rewritten' \
  && pass "a reversed decision keeps its original file intact" \
  || fail "a reversed decision keeps its original file intact"

printf '%s' "$REFRESH" | grep '^| \*\*Decisions\*\*' | grep -qiv 'replace /' \
  && pass "refresh's Decisions row offers no replace disposition" \
  || fail "refresh's Decisions row offers no replace disposition"

printf '%s' "$REFRESH" | grep -qi 'Update, YYYY-MM-DD\|dated update' \
  && pass "refresh amends an ADR with a dated Update section" \
  || fail "refresh amends an ADR with a dated Update section"

# --- grounding is the staleness signal ---------------------------------------
# An entry citing paths that no longer resolve is evidence; reading it and
# judging is opinion. The script already exists.
printf '%s' "$REFRESH" | grep -q 'ensemble-validate-claims' \
  && pass "refresh runs the claim validator across the store" \
  || fail "refresh runs the claim validator across the store"

# --- no stale reference to a section the template dropped --------------------
if printf '%s' "$REFRESH" | grep -q 'TL;DR'; then
  fail "refresh does not read a TL;DR the template no longer produces"
else
  pass "refresh does not read a TL;DR the template no longer produces"
fi

# --- missing-pages is the glossary trigger -----------------------------------
# A concept named in 3+ pages with no definition IS a project-specific term
# nobody defined. That is the accretion trigger, arrived at mechanically.
# Scoped to the missing-pages ROW and its section. CONTEXT.md also appears under
# index-drift, so a file-wide grep passed even with missing-pages unpointed.
grep '^| `missing-pages`' "$LINT" | grep -q 'CONTEXT.md' \
  && pass "the missing-pages row names CONTEXT.md" \
  || fail "the missing-pages row names CONTEXT.md"

sed -n '/^### `missing-pages`/,/^### /p' "$LINT" | grep -q 'CONTEXT.md' \
  && pass "the missing-pages section points at the glossary" \
  || fail "the missing-pages section points at the glossary"

# --- index-drift knows the three sections ------------------------------------
# Scoped to the index-drift SECTION. Scanning all of learn-lint.md also matched
# these words elsewhere in the file, so the check passed for a section that never
# mentioned them.
DRIFT=$(sed -n '/^### `index-drift`/,/^### /p' "$LINT")
for sect in Terms Decisions Solutions; do
  printf '%s' "$DRIFT" | grep -q "$sect" \
    && pass "the index-drift section covers $sect" \
    || fail "the index-drift section covers $sect"
done

# --- all three carriers stay identical ---------------------------------------
n=$(ls "$REPO_ROOT"/skills/*/references/learn-lint.md 2>/dev/null | wc -l | tr -d ' ')
# 3 -> 2 on 2026-09-01: en-review carried learn-lint while naming it nowhere.
# It reviews a branch diff; wiki-graph health is /en-learn's and /en-sweep's.
assert_eq "$n" "2" "learn-lint is carried by two skills"
d=$(for f in "$REPO_ROOT"/skills/*/references/learn-lint.md; do hash_file "$f"; done | sort -u | wc -l | tr -d ' ')
assert_eq "$d" "1" "every carried copy of learn-lint is byte-identical"

report
