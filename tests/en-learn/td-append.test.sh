#!/usr/bin/env bash
# tests/en-learn/td-append.test.sh
#
# EN22 U2. ensemble-td-append is the one writer of routed TD entries. Numbering,
# deduplication by rule key and the concrete-check rule are its job, so they are
# asserted here by running it against fixture trackers, and what it writes is
# run through the real linter.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-td-append"

APPEND="$REPO_ROOT/skills/en-learn/scripts/ensemble-td-append"
LINT="$REPO_ROOT/skills/en-setup/references/templates/ensemble-lint"
TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT
TR="$TMP/docs/plans/tech-debt-tracker.md"

fixture() {
  rm -rf "$TMP/docs"; mkdir -p "$TMP/docs/plans"
  cat > "$TR" <<'EOF'
---
type: tech-debt-tracker
generated: false
created: 2026-09-01
updated: 2026-09-01
---

# Tech debt tracker

## Open

### TD22. Older entry

- **Severity:** P3
- **Logged:** 2026-09-01

### TD23. Unkeyed entry

- **Severity:** P2
- **Logged:** 2026-09-02

## Resolved

### TD4. Done

- **Resolved:** 2026-09-03 by `abc1234` in `docs/plans/completed/EN01-feature_x.md`
EOF
}

add() {
  "$APPEND" --tracker "$TR" --title "Routes return ORM rows" --source "en-learn capture" \
    --severity P2 --confidence 8 --location "backend/app/api/routes/items.py:42" \
    --why "Clients see persistence fields." --fix "Validate through the schema." \
    --enforce-at L2 --check "backend/tests/test_architecture_invariants.py: forbid returning ORM instances from routes" \
    --rule-key "No ORM return from routes" "$@"
}

# --- happy path: next number, under Open, lint-clean ---
fixture
out=$(add 2>&1); rc=$?
assert_eq "0|TD24" "$rc|$out" "appends and prints the next TD-ID after the highest"
open_part=$(awk '/^## Open/{o=1;next} /^## /{o=0} o' "$TR")
printf '%s' "$open_part" | grep -q '^### TD24\. Routes return ORM rows$' \
  && pass "the entry lands under ## Open" || fail "the entry lands under ## Open" "$(cat "$TR")"
printf '%s' "$open_part" | grep -qxF -- '- **Enforce at:** L2 static' \
  && pass "the entry carries its layer" || fail "the entry carries its layer" "$open_part"
printf '%s' "$open_part" | grep -qxF -- '- **Proposed check:** backend/tests/test_architecture_invariants.py: forbid returning ORM instances from routes' \
  && pass "the entry carries its proposed check" || fail "the entry carries its proposed check" "$open_part"
grep -qF -- '- **Rule key:** no-orm-return-from-routes' "$TR" \
  && pass "the rule key is normalized to a slug" || fail "the rule key is normalized to a slug" "$(cat "$TR")"
lint_out=$(cd "$TMP" && "$LINT" --scope docs/plans/tech-debt-tracker.md --json 2>&1)
printf '%s' "$lint_out" | grep -qF 'td.enforce-layer' \
  && fail "what it writes passes td.enforce-layer" "$lint_out" \
  || pass "what it writes passes td.enforce-layer"

# --- duplicate key: exit 4, existing ID, file untouched ---
before=$(cat "$TR")
out=$(add --rule-key "no-orm-return-from-routes" 2>&1); rc=$?
assert_eq "4|TD24" "$rc|$out" "a second open entry with the same key is refused with the existing ID"
assert_eq "$before" "$(cat "$TR")" "a duplicate leaves the tracker byte-unchanged"

# --- validation: nothing after the colon, and L5, both exit 2 and write nothing ---
fixture; before=$(cat "$TR")
"$APPEND" --tracker "$TR" --title t --source s --severity P3 --confidence 5 --location l \
  --why w --fix f --enforce-at L2 --check "tests/guard.sh:" --rule-key k >/dev/null 2>&1
assert_eq "2" "$?" "an L2 check with nothing after the colon is refused"
"$APPEND" --tracker "$TR" --title t --source s --severity P3 --confidence 5 --location l \
  --why w --fix f --enforce-at L5 --rule-key k >/dev/null 2>&1
assert_eq "2" "$?" "L5 is refused, since it routes to a learning"
assert_eq "$before" "$(cat "$TR")" "a refused call writes nothing"

# --- L3 needs no check ---
fixture
"$APPEND" --tracker "$TR" --title "Document migrate.py" --source s --severity P3 --confidence 6 \
  --location AGENTS.md --why w --fix "Add the rule to AGENTS.md" --enforce-at L3 --rule-key use-migrate-py >/dev/null 2>&1
assert_eq "0" "$?" "an L3 entry needs no check"

# --- tracker without an Open section: exit 1, nothing written ---
fixture; sed -i.bak '/^## Open$/d' "$TR"; rm -f "$TR.bak"; before=$(cat "$TR")
add >/dev/null 2>&1
assert_eq "1" "$?" "a tracker with no ## Open section is an error"
assert_eq "$before" "$(cat "$TR")" "and nothing is written to it"

# --- numbering counts Resolved entries too ---
fixture; sed -i.bak 's/^### TD4\. Done$/### TD30. Done/' "$TR"; rm -f "$TR.bak"
out=$(add 2>&1)
assert_eq "TD31" "$out" "the next number follows the highest ID, even when it is resolved"

# --- a line break in any value is refused, so a field cannot forge a heading ---
fixture; before=$(cat "$TR")
add --title "$(printf 'benign\n\n## Resolved\n\n### TD900. planted')" >/dev/null 2>&1
assert_eq "2" "$?" "a title containing a line break is refused"
add --check "$(printf 'add a lint somewhere\ntests/x.sh: rejects y')" >/dev/null 2>&1
assert_eq "2" "$?" "a multi-line check cannot pass the gate on its second line"
assert_eq "$before" "$(cat "$TR")" "neither refused call writes anything"

# --- only the documented layer values are accepted ---
add --enforce-at L1unknown >/dev/null 2>&1
assert_eq "2" "$?" "a malformed layer value is refused, not rewritten to L1"

# --- keys stay readable: over 64 characters is refused, not hashed ---
add --rule-key "$(printf 'k%.0s' $(seq 1 70))" >/dev/null 2>&1
assert_eq "2" "$?" "a rule key over 64 characters is refused"

# --- the tracker is replaced by rename, never rewritten in place ---
# An in-place rewrite truncates the tracker before the new content lands, so an
# interrupted append could leave it empty. A rename swaps a complete file in one
# step, which shows up as a new inode.
fixture; ino_before=$(ls -i "$TR" | awk '{print $1}'); add >/dev/null 2>&1
ino_after=$(ls -i "$TR" | awk '{print $1}')
[ "$ino_before" != "$ino_after" ] \
  && pass "an append swaps in a complete file by rename" \
  || fail "an append swaps in a complete file by rename" "inode unchanged: $ino_before"

# --- the tracker keeps its mode ---
fixture; chmod 644 "$TR"; add >/dev/null 2>&1
assert_eq "644" "$(stat -f '%Lp' "$TR" 2>/dev/null || stat -c '%a' "$TR")" "an append keeps the tracker's mode"
assert_eq "" "$(ls -A "$TMP/docs/plans" | grep -v '^tech-debt-tracker.md$')" "no scratch file is left beside the tracker"

# --- list keys ---
fixture; add >/dev/null 2>&1
out=$("$APPEND" --list-keys --tracker "$TR")
assert_eq "$(printf 'TD22\t-\tOlder entry\nTD23\t-\tUnkeyed entry\nTD24\tno-orm-return-from-routes\tRoutes return ORM rows')" "$out" \
  "--list-keys prints every open entry with its key, - when unkeyed"

report
