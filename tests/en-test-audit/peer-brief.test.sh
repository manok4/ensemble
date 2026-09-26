#!/usr/bin/env bash
# tests/en-test-audit/peer-brief.test.sh
#
# The preservation review is the only independent look a test-audit batch gets
# before it is committed. Three things have to hold for it to mean anything:
# the peer sees the ledger AND the staged change together, the prompt carries
# this skill's three questions rather than a code-review brief, and a peer that
# fails comes back as a failure the flow can stop on, not as an empty pass.
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
INVOKE="$SD/scripts/ensemble-peer-invoke"
BRIEF="$SD/references/peer-brief.md"
for f in "$ART" "$BUILD" "$INVOKE"; do [ -x "$f" ] || { fail "missing or not executable: $f"; report; exit 1; }; done

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

# --- a failed peer is a failure ------------------------------------------------------
printf '%s\n' '#!/usr/bin/env bash' 'echo "network unreachable" >&2' 'exit 1' > "$W/codex"
chmod +x "$W/codex"
printf '%s' "$prompt" > "$W/prompt"
d=$(bash --noprofile --norc -c '
      set -eu
      . "$1"
      ensemble_peer_invoke --peer-cmd "$2" --peer-format "--json" --prompt-file "$3" \
        --out-file /dev/null --peer-mode cross-agent --access read-tree || true
    ' _ "$INVOKE" "$W/codex" "$W/prompt" 2>/dev/null)
printf '%s' "$d" | grep -q '"reason":"peer-failed' \
  && pass "a peer that fails returns a peer-failed decision, which the flow stops on" \
  || fail "a failing peer must come back as peer-failed" "decision=$d"

rm -rf "$R" "$W" "$path"
report
