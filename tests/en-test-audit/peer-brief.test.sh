#!/usr/bin/env bash
# tests/en-test-audit/peer-brief.test.sh
#
# The preservation review is the only independent look a test-audit batch gets
# before it is committed. Two things have to hold for it to mean anything:
# the peer sees the ledger AND the staged change together, and the prompt
# carries this skill's three questions rather than a code-review brief. That a
# failed peer stops the run is guarded in tests/lint/en-test-audit-contract.test.sh;
# peer-failed classification itself belongs to en-review-peer-default.test.sh.
#
# Negative controls at authoring: dropping the staged-diff block from the
# artifact script, removing the nothing-staged refusal, and renaming the
# brief's "What the peer is asked" heading each turned a scenario red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
. "$SELF_DIR/lib.sh"
TEST_NAME="en-test-audit preservation review"

SD="$REPO_ROOT/skills/en-test-audit"
ART="$SD/scripts/ensemble-test-audit-review-artifact"
BUILD="$SD/scripts/ensemble-build-peer-prompt"
BRIEF="$SD/references/peer-brief.md"
for f in "$ART" "$BUILD"; do [ -x "$f" ] || { fail "missing or not executable: $f"; report; exit 1; }; done

R=$(make_audit_repo)
W=$(mktemp -d)
(
  cd "$R" || exit 1
  printf 'pass "old one"\n' > old.test.sh && git add . && git commit -qm more
  mkdir -p docs/test-audits
  cat > docs/test-audits/l.md <<'EOF'
## Ledger

| Test | Mark | Keeper or contract | Evidence | Mutation |
|---|---|---|---|---|
| old.test.sh | D | test.sh::adds two numbers | same assertion | - |
EOF
)

# --- the artifact ---------------------------------------------------------------
out=$(cd "$R" && "$ART" docs/test-audits/l.md --out "$W/none.md" 2>&1); rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$W/none.md" ] && printf '%s' "$out" | grep -q 'nothing is staged' \
  && pass "nothing staged: exit 2, and no file is written" \
  || fail "an empty index must be refused" "rc=$rc out=$out"

(cd "$R" && git rm -q old.test.sh && git add docs/test-audits/l.md)
index_before=$(cd "$R" && git diff --cached)
path=$(cd "$R" && "$ART" docs/test-audits/l.md); rc=$?
index_after=$(cd "$R" && git diff --cached)
if [ "$rc" -eq 0 ] && [ -f "$path" ] && grep -q '^## Ledger file' "$path" && grep -q '^## Staged diff' "$path" \
   && grep -qF '| old.test.sh | D |' "$path" && grep -qF -- '-pass "old one"' "$path" \
   && [ "$index_before" = "$index_after" ]; then
  pass "the artifact holds the ledger and the staged deletion's hunk, and leaves the index alone"
else
  fail "the artifact must hold ledger and staged diff" "rc=$rc path=$path"
fi

# A campaign reviews one boundary group at a time: paths after -- limit the diff.
(cd "$R" && echo '# other group' >> src.sh && git add src.sh)
grp=$(cd "$R" && "$ART" docs/test-audits/l.md -- old.test.sh); rc=$?
if [ "$rc" -eq 0 ] && grep -qF -- '-pass "old one"' "$grp" && ! grep -qF '# other group' "$grp"; then
  pass "paths after -- limit the staged diff to one group"
else
  fail "a path-limited artifact must hold only that group's hunks" "rc=$rc"
fi
out=$(cd "$R" && "$ART" docs/test-audits/l.md --out "$W/nogroup.md" -- nothing-here 2>&1); rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$W/nogroup.md" ] \
  && pass "a group with nothing staged is refused" \
  || fail "an empty group must exit 2" "rc=$rc out=$out"
(cd "$R" && git reset -q HEAD src.sh && git checkout -q -- src.sh)
rm -f "$grp"

# --- the prompt ---------------------------------------------------------------------
prompt=$("$BUILD" --brief "$BRIEF" --project-context "fixture" --goal "Preservation review of a test-audit batch" \
          --artifact-file "$path" --peer-mode cross-agent 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$prompt" | grep -q '### preservation' \
   && printf '%s' "$prompt" | grep -q '### cannot-fail' && printf '%s' "$prompt" | grep -q '### retention' \
   && printf '%s' "$prompt" | grep -qF '| old.test.sh | D |' && printf '%s' "$prompt" | grep -qF -- '-pass "old one"'; then
  pass "the prompt carries the three questions, the ledger rows and the staged hunk"
else
  fail "the prompt must carry this brief's questions and the artifact" "rc=$rc"
fi
if printf '%s' "$prompt" | grep -q '### correctness'; then
  fail "the prompt must not carry en-review's code-review dimensions"
else
  pass "the prompt is this skill's brief, not en-review's"
fi

sed 's/^## What the peer is asked$/## Something else/' "$BRIEF" > "$W/brief.md"
"$BUILD" --brief "$W/brief.md" --project-context x --goal y --artifact-file "$path" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] \
  && pass "a brief without its questions block is refused by the builder" \
  || fail "a brief with no dimensions must be refused" "rc=$rc"

rm -rf "$R" "$W" "$path"
report
