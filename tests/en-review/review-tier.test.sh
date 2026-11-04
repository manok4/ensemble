#!/usr/bin/env bash
# Tests for skills/en-review/scripts/ensemble-review-tier (EN26 U1).
#
# The script decides how deep a branch diff must be reviewed. Every fixture is a
# real repo with a `main` and a `feature` branch in a temp dir.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="review tier"

T="$REPO_ROOT/skills/en-review/scripts/ensemble-review-tier"
[ -x "$T" ] && pass "the script is executable" || fail "the script is executable"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

new_repo() {  # -> path on stdout; main holds one neutral source file
  d=$(mktemp -d "$WORK/rXXXXXX"); mkdir -p "$d/src"
  (
    cd "$d" && git init -q -b main . && git config user.email t@example.com && git config user.name tester
    printf 'first\nsecond\nthird\n' > src/base.js
    git add -A && git commit -qm init && git checkout -qb feature
  ) >/dev/null 2>&1
  printf '%s\n' "$d"
}

plain_lines() {  # $1=count $2=path relative to cwd
  mkdir -p "$(dirname "$2")"
  i=0; while [ "$i" -lt "$1" ]; do i=$((i + 1)); printf 'value%d\n' "$i"; done > "$2"
}

on_main() {  # $1=shell snippet: commit it on main and merge it into feature, so it precedes the merge base
  git checkout -q main && eval "$1" && git add -A && git commit -qm base && git checkout -q feature && git merge -q main
}

classify() {  # $1=repo -> leaves JSON in OUT
  OUT=$(cd "$1" && "$T" --base main --json); RC=$?
}

field() {  # $1=key -> value from OUT, arrays comma-joined
  printf '%s' "$OUT" | python3 -c 'import json,sys
v=json.load(sys.stdin)[sys.argv[1]]
print(",".join(v) if isinstance(v,list) else v)' "$1"
}

expect() {  # $1=tier $2=reason $3=description
  assert_eq "$1" "$(field tier)" "$3: tier"
  assert_contains "$(field reasons)" "$2" "$3: reason"
}

in_repo() {  # $1=shell snippet, run on a fresh feature branch; classifies it
  R=$(new_repo)
  ( cd "$R" && eval "$1" ) >/dev/null 2>&1
  classify "$R"
}

# --- size ---------------------------------------------------------------------
in_repo 'plain_lines 10 src/a.js'
expect quick under-limits "10 lines in 1 file"
assert_exit_code 0 "$RC" "a printed tier exits 0"

in_repo 'plain_lines 120 src/a.js; plain_lines 1 src/b.js; plain_lines 1 src/c.js'
expect standard size-standard "122 lines in 3 files"

in_repo 'plain_lines 301 src/a.js'
expect full over-300-lines "301 lines"

in_repo 'for i in 1 2 3 4 5 6 7 8 9 10 11; do plain_lines 1 src/f$i.js; done'
expect full over-10-files "11 files of one line"

# --- the table's boundaries ---------------------------------------------------
in_repo 'plain_lines 49 src/a.js'
expect quick under-limits "49 lines"
in_repo 'plain_lines 50 src/a.js'
expect standard size-standard "50 lines"
in_repo 'plain_lines 300 src/a.js'
expect standard size-standard "300 lines"
in_repo 'for i in 1 2 3 4 5 6 7 8 9 10; do plain_lines 1 src/f$i.js; done'
expect quick under-limits "10 files"
in_repo 'for i in 1 2 3 4 5 6 7 8 9 10 11 12 13; do plain_lines 3 src/f$i.js; done'
expect full over-10-files "13 files, 39 lines"

# --- exclusions ---------------------------------------------------------------
in_repo 'plain_lines 5000 package-lock.json'
expect full risk:dependency "a lockfile alone"
assert_eq "0" "$(field lines)" "a lockfile's lines do not count"
assert_contains "$(field excluded)" "package-lock.json" "the lockfile is listed as excluded"

in_repo 'plain_lines 400 docs/generated/index.md; plain_lines 10 src/a.js'
expect quick under-limits "400 generated lines plus 10 of source"
assert_eq "10" "$(field lines)" "only the source lines count"
assert_contains "$(field excluded)" "docs/generated/index.md" "the generated file is listed as excluded"

in_repo 'plain_lines 400 dist/app.min.js; plain_lines 2 src/a.js'
expect quick under-limits "a minified file"

in_repo 'printf "out/** linguist-generated\n" > .gitattributes; plain_lines 400 out/x.js'
expect quick under-limits "a linguist-generated file"
assert_contains "$(field excluded)" "out/x.js" "the attribute excludes the file"

# --- what the diff is ---------------------------------------------------------
in_repo 'git add -A; plain_lines 60 src/new.js'
expect standard size-standard "an untracked new file counts"

R=$(new_repo)
classify "$R"
expect quick empty-diff "no changes"

in_repo 'plain_lines 60 src/a.js; git add -A; git commit -qm c1'
expect standard size-standard "committed work counts"

in_repo 'plain_lines 60 "src/with space.js"'
expect standard size-standard "a path with a space"
in_repo 'plain_lines 60 "src/$(printf "caf\303\251").js"'
expect standard size-standard "a non-ASCII path"
assert_eq "1" "$(field files)" "a non-ASCII path counts as one file"

R=$(new_repo)
( cd "$R" && on_main 'plain_lines 20 src/old.js' && git mv src/old.js src/renamed.js && git commit -qm mv ) >/dev/null 2>&1
classify "$R"
assert_eq "0" "$(field lines)" "a pure rename adds no lines"
expect quick under-limits "a pure rename"

in_repo 'on_main "plain_lines 2 src/auth/x.js"; git mv src/auth src/moved; git commit -qm mv'
assert_contains "$(field reasons)" "risk:auth" "a rename checks its old path too"

# --- risk on paths ------------------------------------------------------------
in_repo 'plain_lines 1 src/auth/x.js'
expect full risk:auth "a file under auth/"
in_repo 'plain_lines 1 src/Billing/x.js'
expect full risk:payments "a path segment in another case"
in_repo 'plain_lines 1 db/migrations/001.js'
expect full risk:migrations "a file under migrations/"
in_repo 'plain_lines 1 .env.local'
expect full risk:secrets "an .env variant"
in_repo 'plain_lines 1 requirements-dev.txt'
expect full risk:dependency "a requirements file"
in_repo 'plain_lines 1 src/authentication/x.js'
expect full risk:auth "a file under authentication/"
in_repo 'plain_lines 1 src/authoring/x.js'
expect quick under-limits "a segment that only starts with auth"

# --- risk on content ----------------------------------------------------------
add_line() { printf '%s\n' "$1" > "$2"; }
for hit in 'const refresh_token = 1' 'const refreshToken = 1' 'x.headers.jwt = y' 'const apiKey = 1' 'send(Webhook)' 'const q = "backfill"' 'authenticate(user)' 'if (isAuthorized) go()' 'use_oauth2()' 'h["x-api-key"] = v'; do
  in_repo "add_line '$hit' src/a.js"
  assert_eq "full" "$(field tier)" "content '$hit' raises the tier"
done
in_repo "add_line 'const q = \"DROP TABLE x\"' src/a.js"
expect full risk:migrations "SQL inside a string"
in_repo "add_line 'db.run(\"UPDATE users SET a = 1\")' src/a.js"
expect full risk:data-mutation "an UPDATE statement"

for miss in 'const max_tokens = 1' 'const maxTokens = 1' 'const author = 1' 'const oracle = 1' 'update the cache and set it'; do
  in_repo "add_line '$miss' src/a.js"
  expect quick under-limits "content '$miss'"
done

in_repo "add_line '// rotate the token' src/a.js"
expect quick under-limits "a word only in a comment"
in_repo "add_line 'rotate the token' src/notes.md"
expect quick under-limits "a word only in a markdown file"
in_repo "add_line 'token==1.0' requirements.txt"
expect full risk:auth "requirements.txt is not prose"

R=$(new_repo)
( cd "$R" && on_main 'printf "password\nkeep\n" > src/old.js' && printf 'keep\n' > src/old.js ) >/dev/null 2>&1
classify "$R"
assert_contains "$(field reasons)" "risk:auth" "a removed line counts"

R=$(new_repo)
( cd "$R" && on_main 'printf -- "--- password\nkeep\n" > src/old.sql' && printf 'keep\n' > src/old.sql ) >/dev/null 2>&1
classify "$R"
expect quick under-limits "a removed SQL comment is skipped, not read as a file header"

# --- eval-able output ---------------------------------------------------------
R=$(new_repo)
( cd "$R" && plain_lines 60 src/a.js ) >/dev/null 2>&1
LINES=$(cd "$R" && "$T" --base main)
eval "$LINES"
assert_eq "standard|size-standard|1|60" "$REVIEW_TIER|$REVIEW_TIER_REASONS|$REVIEW_TIER_FILES|$REVIEW_TIER_LINES" "the default output is eval-able"

# --- error paths --------------------------------------------------------------
R=$(new_repo)
OUT=$(cd "$R" && "$T" --base no-such-ref --json); RC=$?
assert_exit_code 0 "$RC" "a base that does not resolve exits 0"
expect full diff-unreadable "a base that does not resolve"

OUT=$(cd "$WORK" && "$T" --base main --json); RC=$?
assert_exit_code 0 "$RC" "outside a repo exits 0"
expect full diff-unreadable "outside a repo"

( cd "$R" && "$T" ) >/dev/null 2>&1; RC=$?
assert_exit_code 3 "$RC" "a missing --base exits 3"
( cd "$R" && "$T" --base ) >/dev/null 2>&1; RC=$?
assert_exit_code 3 "$RC" "--base with no value exits 3"
( cd "$R" && "$T" --base main --bogus ) >/dev/null 2>&1; RC=$?
assert_exit_code 3 "$RC" "an unknown flag exits 3"

report
