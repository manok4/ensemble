#!/usr/bin/env bash
# tests/lint/ensemble-secret-scan.test.sh
#
# The scan was prose plus a pattern table, so every run hand-rolled greps. Two
# consequences, both real:
#
#   THE (?i) PATTERNS DID NOT WORK.  `grep -E` has no portable inline
#   case-insensitive flag, so half the reference's patterns were quietly
#   case-sensitive in whatever the agent typed that run.
#
#   THE OUTPUT COULD LEAK.  A hand-rolled `grep -n` prints the matching line,
#   which puts the credential in the terminal, the PR body and the transcript.
#   A scanner whose output is itself a leak has moved the secret, not caught it.
#
# So the assertions below care about masking and about the reference and the
# implementation naming the same patterns, as much as about detection.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-secret-scan"

S="$REPO_ROOT/skills/en-ship/scripts/ensemble-secret-scan"
REF="$REPO_ROOT/skills/en-ship/references/secret-patterns.md"
assert_file_exists "$S" "the secret-scan helper exists"
[ -x "$S" ] && pass "the secret-scan helper is executable" || fail "the secret-scan helper is executable"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
repo() {
  d="$WORK/$1"; mkdir -p "$d"
  ( cd "$d" && git init -q . && git config user.email t@example.com && git config user.name tester \
      && printf 'base\n' > base.txt && git add base.txt && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$d"
}
scan() { d="$1"; shift; OUT=$( cd "$d" && bash "$S" "$@" 2>&1 ); RC=$?; }

# --- a credential shape blocks ------------------------------------------------
D=$(repo aws)
printf 'const k = "AKIAIOSFODNN7EXAMPLE";\n' > "$D/cfg.js"; ( cd "$D" && git add cfg.js )
scan "$D" --staged
assert_eq "1" "$RC" "a high-confidence match blocks the push"
printf '%s' "$OUT" | grep -qF "aws-access-key-id" \
  && pass "the finding names the pattern that matched" || fail "the pattern must be named"
printf '%s' "$OUT" | grep -qF "cfg.js:1" \
  && pass "the finding carries path and line" || fail "the finding must carry path:line"

# --- and the credential itself never reaches the output -----------------------
# The assertion that matters most here. A scanner that echoes the line has moved
# the secret into every place this output is pasted.
printf '%s' "$OUT" | grep -qF "AKIAIOSFODNN7EXAMPLE" \
  && fail "the scanner LEAKED the matched credential into its own output" \
  || pass "the matched credential is never printed"
printf '%s' "$OUT" | grep -qE 'AKIA\*+' \
  && pass "the preview is masked after four characters" || fail "the preview must be masked"

# --- case-insensitive patterns really are ------------------------------------
# This is the one grep -E could not do portably, so it is the one most likely to
# have been silently broken in a hand-rolled scan.
D=$(repo caseless)
printf 'AWS_SECRET_ACCESS_KEY = "abcdefghij0123456789ABCDEFGHIJ0123456789"\n' > "$D/up.txt"
( cd "$D" && git add up.txt ); scan "$D" --staged
assert_eq "1" "$RC" "an uppercase aws_secret_access_key still matches"

# --- red-flag filenames block on the path alone -------------------------------
D=$(repo dotenv)
printf 'X=1\n' > "$D/.env"; ( cd "$D" && git add -f .env ); scan "$D" --staged
assert_eq "1" "$RC" "a .env file blocks even with innocuous contents"
printf '%s' "$OUT" | grep -qF "dotenv-file" && pass "the filename rule names itself" \
  || fail "the filename finding must name its rule"

# --- heuristics warn, never block ---------------------------------------------
D=$(repo heuristic)
printf 'password = "hunter2xyz"\n' > "$D/h.py"; ( cd "$D" && git add h.py ); scan "$D" --staged
assert_eq "0" "$RC" "a heuristic match warns instead of blocking"
printf '%s' "$OUT" | grep -qF "WARN" && pass "the heuristic match is surfaced as a warning" \
  || fail "a heuristic match must still be reported"

# --- the pragma is per-line and counted ---------------------------------------
D=$(repo pragma)
printf 'const k = "AKIAIOSFODNN7EXAMPLE";  // pragma: ensemble-allow-secret\n' > "$D/cfg.js"
( cd "$D" && git add cfg.js ); scan "$D" --staged
assert_eq "0" "$RC" "a pragma line does not block"
printf '%s' "$OUT" | grep -qF "suppressed" \
  && pass "suppressed lines are counted, so nobody forgets they exist" \
  || fail "the pragma count must be reported"

# --- removed lines are not scanned --------------------------------------------
# A credential already in history is a different problem, and refusing the push
# cannot fix it. Blocking on it trains people to pass --allow-secrets by reflex.
D=$(repo removal)
printf 'const k = "AKIAIOSFODNN7EXAMPLE";\n' > "$D/old.js"
( cd "$D" && git add old.js && git commit -qm add && git rm -q old.js )
scan "$D" --staged
assert_eq "0" "$RC" "deleting a line that contains a key is not a new leak"

# --- --allow-secrets downgrades rather than silences --------------------------
D=$(repo allowflag)
printf 'const k = "AKIAIOSFODNN7EXAMPLE";\n' > "$D/cfg.js"; ( cd "$D" && git add cfg.js )
scan "$D" --staged --allow-secrets
assert_eq "0" "$RC" "--allow-secrets exits 0"
printf '%s' "$OUT" | grep -qF "WARN" \
  && pass "--allow-secrets still reports the match as a warning" \
  || fail "--allow-secrets must downgrade, never silence"

# --- --json shape --------------------------------------------------------------
scan "$D" --staged --json
shape=$(printf '%s' "$OUT" | python3 -c 'import json,sys
d=json.load(sys.stdin)
print(",".join(k for k in ("blocking","findings","warnings","suppressed_by_pragma","allow_secrets") if k in d))')
assert_eq "blocking,findings,warnings,suppressed_by_pragma,allow_secrets" "$shape" \
  "--json carries the documented fields"

# --- the reference and the implementation name the same patterns --------------
# secret-patterns.md is the source of truth for the list. A vendor adds a token
# shape, someone edits the table, and the scanner never learns about it: the
# reference itself asks for this check under "Updating patterns".
missing=""
for probe in 'AKIA\[0-9A-Z\]{16}' 'ghp_' 'gho_' 'ghu_' 'ghs_' 'xox\[bpoa\]' 'sk-ant-' 'BEGIN (RSA ' 'bearer'; do
  grep -qF "$(printf '%s' "$probe" | sed 's/\\//g')" "$REF" || continue
  grep -qF "$(printf '%s' "$probe" | sed 's/\\//g')" "$S" || missing="$missing $probe"
done
[ -z "$missing" ] \
  && pass "every high-confidence pattern in the reference is implemented" \
  || fail "the scanner is missing a pattern the reference documents" "missing:$missing"

# --- every skill that commits reaches the scanner -----------------------------
# The gap this closes: /en-resolve-pr pushed to a PR head with zero mentions of
# secrets, and it commonly runs --orchestrated with nobody watching. A fix
# written from a review comment introduces a credential exactly as any other
# edit can.
for skill in en-ship en-resolve-pr; do
  f="$REPO_ROOT/skills/$skill/SKILL.md"
  grep -qF 'scripts/ensemble-secret-scan' "$f" \
    && pass "$skill scans before it commits" \
    || fail "$skill must scan the staged diff before committing"
  [ -x "$REPO_ROOT/skills/$skill/scripts/ensemble-secret-scan" ] \
    && pass "$skill carries the scanner it names" \
    || fail "$skill names the scanner but does not carry it"
done

# --- usage --------------------------------------------------------------------
scan "$D" --nonsense
assert_eq "2" "$RC" "an unknown argument is a usage error"

report
