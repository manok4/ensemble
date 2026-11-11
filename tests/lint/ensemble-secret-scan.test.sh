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
# The scanner reads every commit a branch pushes, this file's included, so the
# fixture key is written once, under the pragma, and branch lines reference it.
AKIA_FIXTURE="AKIAIOSFODNN7EXAMPLE"  # pragma: ensemble-allow-secret
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

# --- a labelled digest is not a credential -----------------------------------
# Every plan carries `peer_review_plan_hash: <sha256>`. Scanning a branch's
# commits would otherwise warn on every plan branch and stop a hands-off ship
# for a confirmation nobody needs. A hex value with no digest label still warns.
H64=$(printf 'x' | shasum -a 256 | cut -c1-64); H40=$(printf 'x' | shasum | cut -c1-40)
D=$(repo digest)
printf -- '---\npeer_review_plan_hash: %s\n---\nsha256: "%s"\n{"commit": "%s"}\nchecksum=%s\n' "$H64" "$H64" "$H40" "$H64" > "$D/plan.md"
( cd "$D" && git add plan.md ); scan "$D" --staged
assert_eq "0" "$RC" "labelled digests exit 0"
assert_not_contains "$OUT" "long-hex-string" "a hex value labelled hash, sha, commit or checksum is not reported"
D=$(repo bare-hex)
printf 'token = "%s"\nvalue: %s\nshared_secret: %s\nhmac_sha256_key: %s\ncommit_signing_key: %s\nhashicorp_token = %s\n{"commit": "%s", "signing_key": "%s"}\n' \
  "$H40" "$H64" "$H64" "$H64" "$H64" "$H40" "$H40" "$H64" > "$D/k.txt"
( cd "$D" && git add k.txt ); scan "$D" --staged
assert_eq "7" "$(printf '%s\n' "$OUT" | grep -c 'long-hex-string')" \
  "a key that merely contains a digest word still warns, and so does an unlabelled value after a labelled one"

# --- what a push adds: committed lines need --range, not --staged --------------
D=$(repo committed)
( cd "$D" && git branch base-ref && printf 'password = "hunter2xyz"\n' > c.py && git add c.py && git commit -qm c )
scan "$D" --staged
assert_contains "$OUT" "secret-scan: clean" "--staged sees nothing once the lines are committed"
scan "$D" --range base-ref...HEAD
assert_contains "$OUT" "hardcoded-password" "--range <base>...HEAD sees the committed lines a push sends"
# A key added in one commit and removed in the next is pushed in history but
# absent from the net diff; only --commits sees it, and it blocks.
D=$(repo history)
( cd "$D" && git branch base-ref && printf 'const k = "%s";\n' "$AKIA_FIXTURE" > cfg.js && git add cfg.js && git commit -qm add \
  && printf 'const k = process.env.K;\n' > cfg.js && git commit -qam remove )
scan "$D" --range base-ref...HEAD
assert_eq "0" "$RC" "the net diff of an added-then-removed key looks clean"
scan "$D" --commits base-ref..HEAD
assert_eq "1" "$RC" "--commits blocks on a key that any pushed commit added"
assert_not_contains "$OUT" "$AKIA_FIXTURE" "--commits still never prints the credential"
D=$(repo plan-commit)
( cd "$D" && git branch base-ref && printf -- '---\npeer_review_plan_hash: %s\n---\n' "$H64" > plan.md && git add plan.md && git commit -qm plan )
scan "$D" --commits base-ref..HEAD
assert_contains "$OUT" "secret-scan: clean" "a plan branch's commits scan clean"
scan "$D" --commits nosuchref..HEAD
assert_eq "2" "$RC" "an unreadable --commits range is a usage error, never a pass"

# --- user git config cannot blind the parser ----------------------------------
# The scanner parses git's text output, so anything that changes how git renders
# a diff changes what it sees. Colour wraps every `+` in an escape code, and
# noprefix drops the `b/` the path is read from.
D=$(repo colour)
( cd "$D" && git config color.ui always && git config color.diff always )
printf 'const k = "%s";\n' "$AKIA_FIXTURE" > "$D/cfg.js"; ( cd "$D" && git add cfg.js )
scan "$D" --staged
assert_eq "1" "$RC" "color.ui=always does not hide an added key"
assert_contains "$OUT" "aws-access-key-id" "a coloured diff still names the pattern"
D=$(repo noprefix)
( cd "$D" && git config diff.noprefix true )
printf 'const k = "%s";\n' "$AKIA_FIXTURE" > "$D/cfg.js"; ( cd "$D" && git add cfg.js )
scan "$D" --staged
assert_contains "$OUT" "cfg.js:1" "diff.noprefix still yields the real path"

# --- a pure rename reaches the filename tier ----------------------------------
# Rename detection prints `rename to .env` and no `+++` line, so the red-flag
# name was never seen.
D=$(repo rename)
( cd "$D" && printf 'X=1\n' > env.txt && git add env.txt && git commit -qm env && git mv env.txt .env )
scan "$D" --staged
assert_eq "1" "$RC" "a staged rename onto .env blocks"
assert_contains "$OUT" "dotenv-file" "the renamed path is matched by the filename tier"

# --- bytes that are not UTF-8 are not a crash ---------------------------------
D=$(repo latin1)
printf 'caf\351\n' > "$D/menu.txt"; ( cd "$D" && git add menu.txt )
scan "$D" --staged
assert_eq "0" "$RC" "a Latin-1 file with no secret exits 0"
assert_contains "$OUT" "secret-scan: clean" "a Latin-1 file scans clean"
assert_not_contains "$OUT" "Traceback" "a Latin-1 file raises no traceback"

# --- the scanner's own failure is exit 2, never a block -----------------------
# An uncaught Python exception exits 1, which reads exactly like a credential.
# A python3 that is handed a diff path it cannot open stands in for any
# internal failure.
REAL_PY=$(command -v python3)
mkdir -p "$WORK/badpy"
printf '#!/bin/sh\nDIFF_FILE=/nonexistent/ensemble-diff exec "%s" "$@"\n' "$REAL_PY" > "$WORK/badpy/python3"
chmod +x "$WORK/badpy/python3"
D=$(repo internal)
OUT=$( cd "$D" && PATH="$WORK/badpy:$PATH" bash "$S" --staged 2>&1 ); RC=$?
assert_eq "2" "$RC" "an internal error exits 2, never 1"
assert_contains "$OUT" "internal error" "an internal error says so on stderr"

# --- --commits reads what each commit carries: merges, messages, names --------
# A push sends commits, and each carries a patch, a message and the paths it
# adds. Every finding names the commit that added it.
sha() { ( cd "$1" && git rev-parse --short=7 "$2" ); }
diverge() {  # mainline and feat each commit once; feat is checked out
  ( cd "$1" && git branch -m mainline && git checkout -qb feat && printf "$2" > "$3" && git add -A && git commit -qm feat \
      && git checkout -q mainline && printf "$4" > "$5" && git add -A && git commit -qm main && git checkout -q feat )
}
D=$(repo merge-resolution); diverge "$D" 'feat\n' f 'password = "hunter2xyz"\n' f
( cd "$D" && { git merge -q mainline >/dev/null 2>&1; true; } \
    && printf 'password = "hunter2xyz"\nconst k = "%s";\n' "$AKIA_FIXTURE" > f && git add f && git commit -qm merge )
scan "$D" --commits mainline..HEAD
assert_eq "1" "$RC" "a key that exists only in a merge's conflict resolution blocks"
assert_contains "$OUT" "commit $(sha "$D" HEAD)" "the finding names the merge commit"
assert_not_contains "$OUT" "hardcoded-password" "a resolution that keeps the base's line does not rescan it"
D=$(repo merge-clean); diverge "$D" 'feat\n' f.txt 'password = "hunter2xyz"\n' h.py
( cd "$D" && git checkout -q mainline && printf '\000\001' > base.pem && git add base.pem && git commit -qm pem \
    && git checkout -q feat && git merge -q --no-edit mainline >/dev/null 2>&1 )
scan "$D" --commits mainline..HEAD
assert_not_contains "$OUT" "hardcoded-password" "a clean merge does not rescan the lines its base already holds"
assert_not_contains "$OUT" "cert-or-key-file" "a clean merge does not re-flag a file its base added"
assert_eq "1" "$( cd "$D" && git rev-list --merges mainline..HEAD | wc -l | tr -d ' ')" "the clean-merge fixture really holds a merge"

D=$(repo message)
( cd "$D" && git branch base-ref && printf 'x\n' > m.txt && git add m.txt \
    && git commit -qm "subject" -m "token ghp_$(printf 'a%.0s' $(seq 36))" )
scan "$D" --commits base-ref..HEAD
assert_eq "1" "$RC" "a token in a commit message blocks"
assert_contains "$OUT" "<commit-message>:3" "a message finding carries the message's own line"

D=$(repo rename-commit)
( cd "$D" && git branch base-ref && printf 'X=1\n' > env.txt && git add env.txt && git commit -qm a && git mv env.txt .env && git commit -qm b )
scan "$D" --commits base-ref..HEAD
assert_contains "$OUT" "dotenv-file  .env  commit $(sha "$D" HEAD)" "a commit that renames onto .env blocks, attributed to it"

D=$(repo binary)
( cd "$D" && git branch base-ref && printf '\000\001' > deploy.key && git add deploy.key && git commit -qm key )
scan "$D" --commits base-ref..HEAD
assert_contains "$OUT" "cert-or-key-file" "a binary key file blocks on its name"
D=$(repo merge-binary); diverge "$D" 'feat\n' f.txt 'main\n' m.txt
( cd "$D" && git merge -q --no-commit mainline >/dev/null 2>&1 && printf '\000\001' > deploy.key && git add deploy.key && git commit -qm merge )
scan "$D" --commits mainline..HEAD
assert_contains "$OUT" "cert-or-key-file  deploy.key  commit $(sha "$D" HEAD)" "a binary that only a merge introduces blocks, attributed to the merge"

# Paths git quotes, or pads with a tab, are matched as the real path.
D=$(repo odd-names)
( cd "$D" && git branch base-ref && mkdir "$(printf 'dir\tx')" "$(printf 'nl\ny')" \
    && printf '\000\001' > "$(printf 'dir\tx')/.env" && printf 'X=1\n' > "$(printf 'nl\ny')/env.txt" \
    && git add -A && git commit -qm odd && git mv "$(printf 'nl\ny')/env.txt" "$(printf 'nl\ny')/.env" && git commit -qm mv )
scan "$D" --commits base-ref..HEAD --json
paths=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(sorted(repr(f["path"]) for f in json.load(sys.stdin)["findings"]))')
assert_eq "[\"'dir\\\\tx/.env'\", \"'nl\\\\ny/.env'\"]" "$paths" "tab and newline directory names reach the filename tier decoded"
D=$(repo quoted-staged)
mkdir "$D/$(printf 'dir\tx')"; printf 'const k = "%s";\n' "$AKIA_FIXTURE" > "$D/$(printf 'dir\tx')/cfg.js"; ( cd "$D" && git add -A )
scan "$D" --staged --json
assert_eq "'dir\\tx/cfg.js'" "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(repr(json.load(sys.stdin)["findings"][0]["path"]))')" \
  "a staged line finding under a quoted path carries the real path"
D=$(repo spaced)
mkdir "$D/my dir"; printf 'X=1\n' > "$D/my dir/.env"; ( cd "$D" && git add -f "my dir/.env" )
scan "$D" --staged
assert_contains "$OUT" "dotenv-file  my dir/.env" "a path with a space is not read with git's trailing tab"

# A pushed .gitattributes can mark text as binary, and git then prints "Binary
# files differ" in place of every line the file adds.
for attr in -diff binary; do
  D=$(repo "attr$attr")
  ( cd "$D" && git branch base-ref && printf '*.txt %s\n' "$attr" > .gitattributes \
      && printf 'const k = "%s";\n' "$AKIA_FIXTURE" > a.txt && git add -A && git commit -qm attr )
  scan "$D" --commits base-ref..HEAD
  assert_eq "1" "$RC" "a pushed '*.txt $attr' attribute does not hide a key in a .txt"
done

# --cc ignores --text, so a merge's resolution of a -diff file needs the
# attributes themselves switched off.
D=$(repo attr-merge); ( cd "$D" && printf '*.txt -diff\n' > .gitattributes && git add .gitattributes && git commit -qm attrs )
diverge "$D" 'feat\n' f.txt 'main\n' f.txt
( cd "$D" && { git merge -q mainline >/dev/null 2>&1; true; } \
    && printf 'const k = "%s";\n' "$AKIA_FIXTURE" > f.txt && git add f.txt && git commit -qm merge )
scan "$D" --commits mainline..HEAD
assert_eq "1" "$RC" "a key in a merge's resolution of a -diff file blocks"
# A git before 2.40 ignores GIT_ATTR_SOURCE; the merge cannot be read, so the
# scan says so and exits 2 rather than calling it clean.
OUT=$( cd "$D" && ENSEMBLE_SECRET_SCAN_ASSUME_OLD_GIT=1 bash "$S" --commits mainline..HEAD 2>&1 ); RC=$?
assert_eq "2" "$RC" "without attribute pinning, a binary merge diff exits 2, never clean"
# .git/info/attributes outranks GIT_ATTR_SOURCE (PR #149 review), so a local
# `-diff` there hides a merge resolution even on a new git: same fail-closed exit.
D=$(repo info-attr-merge)
diverge "$D" 'feat\n' f.txt 'main\n' f.txt
( cd "$D" && printf 'f.txt -diff\n' >> .git/info/attributes && { git merge -q mainline >/dev/null 2>&1; true; } \
    && printf 'const k = "%s";\n' "$AKIA_FIXTURE" > f.txt && git add f.txt && git commit -qm merge )
scan "$D" --commits mainline..HEAD
assert_ne "0" "$RC" "a local .git/info/attributes -diff cannot make a merge resolution scan clean"

# Config that re-encodes or narrows git's output is outranked by the scanner's pins.
D=$(repo log-encoding)
( cd "$D" && git branch base-ref && git config i18n.logOutputEncoding UTF-16 && printf 'x\n' > m.txt && git add m.txt \
    && git commit -qm "subject" -m "token ghp_$(printf 'a%.0s' $(seq 36))" )
scan "$D" --commits base-ref..HEAD
assert_eq "1" "$RC" "a UTF-16 i18n.logOutputEncoding does not hide a token in a message"
D=$(repo relative)
( cd "$D" && git config diff.relative true && mkdir sub other && printf 'const k = "%s";\n' "$AKIA_FIXTURE" > other/cfg.js && git add other/cfg.js )
OUT=$( cd "$D/sub" && bash "$S" --staged 2>&1 ); RC=$?
assert_eq "1" "$RC" "diff.relative run from a subdirectory still sees the whole index"

# A scan git could not run is exit 2, never an empty diff read as clean.
D=$(repo corrupt-index); printf 'garbage' > "$D/.git/index"
scan "$D" --staged
assert_eq "2" "$RC" "a corrupt index is exit 2, not clean"
scan "$D" --working
assert_eq "2" "$RC" "a corrupt index under --working is exit 2, not clean"

# git revert and cherry-pick -x write "commit <sha>" into the message.
D=$(repo revert)
( cd "$D" && git branch base-ref && printf 'x\n' > r.txt && git add r.txt && git commit -qm add && git revert --no-edit HEAD >/dev/null )
scan "$D" --commits base-ref..HEAD
assert_contains "$( cd "$D" && git log -1 --format=%B )" "This reverts commit" "the revert fixture holds a revert message"
assert_not_contains "$OUT" "long-hex-string" "a revert message's commit SHA does not warn"

# A decoded path is for matching only. Printed raw, a name holding a newline and
# an escape sequence could forge a clean-looking report line.
D=$(repo control-bytes)
mkdir "$D/$(printf 'x\ny\033z')"; printf 'X=1\n' > "$D/$(printf 'x\ny\033z')/.env"; ( cd "$D" && git add -f -A )
scan "$D" --staged
assert_eq "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "a path with a newline and ESC prints as one line"
assert_contains "$OUT" 'dotenv-file  x\x0ay\x1bz/.env' "control bytes in a printed path are escaped"
D=$(repo unicode-controls)
U=$(printf 'a\342\200\256b\342\200\250c\302\205d')   # U+202E bidi override, U+2028, U+0085
mkdir "$D/$U"; printf 'X=1\n' > "$D/$U/.env"; ( cd "$D" && git add -f -A )
scan "$D" --staged
assert_eq "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "a path with Unicode separators prints as one line"
assert_contains "$OUT" 'a\u202eb\u2028c\x85d/.env' "bidi overrides and Unicode separators in a printed path are escaped"

D=$(repo root-commit)
( cd "$D" && git config log.showRoot false && git branch -m mainline && git checkout -q --orphan other && git rm -rqf . \
    && printf 'const k = "%s";\n' "$AKIA_FIXTURE" > cfg.txt && git add cfg.txt && git commit -qm root )
scan "$D" --commits mainline..other
assert_eq "1" "$RC" "a root commit's patch is scanned even with log.showRoot=false"
assert_contains "$OUT" "commit $(sha "$D" other)" "the finding names the root commit"

# --- --outgoing: only unpushed commits block ----------------------------------
# A refused push cannot unexpose a commit origin already holds, so its findings
# are notices: reported, never blocking, never re-prompting on each re-ship.
D=$(repo outgoing); ORIGIN="$WORK/outgoing-origin.git"; git init -q --bare "$ORIGIN"
( cd "$D" && git branch -m mainline && git remote add origin "$ORIGIN" && git push -q origin mainline 2>/dev/null \
    && git fetch -q origin && git checkout -qb feat && printf 'password = "hunter2xyz"\n' > a.py && git add a.py && git commit -qm A \
    && git push -q origin feat 2>/dev/null && git fetch -q origin && printf 'ok\n' > b.txt && git add b.txt && git commit -qm B )
A=$(sha "$D" HEAD~1)
scan "$D" --outgoing origin/mainline
assert_eq "0" "$RC" "a finding in an already-pushed commit does not block"
assert_contains "$OUT" "NOTICE  hardcoded-password  a.py:1" "a pushed commit's match is a notice"
assert_contains "$OUT" "commit $A" "the notice names the pushed commit"
assert_not_contains "$OUT" "WARN" "a pushed commit's match does not warn again"
scan "$D" --outgoing origin/mainline --json
assert_eq "1:$A" "$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("{}:{}".format(len(d["notices"]), d["notices"][0]["commit"]))')" \
  "--json lists notices with their commit"
( cd "$D" && printf 'const k = "%s";\n' "$AKIA_FIXTURE" > c.js && git add c.js && git commit -qm C )
scan "$D" --outgoing origin/mainline
assert_eq "1" "$RC" "an unpushed commit with a key blocks"
assert_contains "$OUT" "commit $(sha "$D" HEAD)" "the block names the unpushed commit"
D=$(repo never-pushed)
( cd "$D" && git branch base-ref && printf 'const k = "%s";\n' "$AKIA_FIXTURE" > c.js && git add c.js && git commit -qm C )
scan "$D" --outgoing base-ref
assert_eq "1" "$RC" "with no remote-tracking refs every commit counts as unpushed"
scan "$D" --outgoing nosuchref
assert_eq "2" "$RC" "an unknown --outgoing base is exit 2"
# Blocking tiers demote too, and --remote picks which remote counts as pushed.
D=$(repo pushed-block); ORIGIN="$WORK/pushed-block-origin.git"; OTHER="$WORK/pushed-block-other.git"
git init -q --bare "$ORIGIN"; git init -q --bare "$OTHER"
( cd "$D" && git branch -m mainline && git remote add origin "$ORIGIN" && git remote add other "$OTHER" \
    && git push -q origin mainline 2>/dev/null && git push -q other mainline 2>/dev/null && git fetch -q --all \
    && git checkout -qb feat && printf 'const k = "%s";\n' "$AKIA_FIXTURE" > c.js && printf '\000\001' > deploy.key \
    && git add -A && git commit -qm A && git push -q origin feat 2>/dev/null && git fetch -q origin )
scan "$D" --outgoing origin/mainline
assert_eq "0" "$RC" "a key and a key file already on origin do not block"
assert_contains "$OUT" "NOTICE  aws-access-key-id" "a pushed high-confidence match is a notice"
assert_contains "$OUT" "NOTICE  cert-or-key-file" "a pushed red-flag filename is a notice"
assert_not_contains "$OUT" "BLOCK" "nothing already pushed blocks"
scan "$D" --outgoing origin/mainline --remote other
assert_eq "1" "$RC" "--remote other counts a commit only origin holds as unpushed"

# --- usage errors --------------------------------------------------------------
# A value starting with '-' would reach git as an option.
for args in "--remote x --staged" "--outgoing --output=/tmp/x" "--range --output=/tmp/x" "--commits -x" "--outgoing" "--remote"; do
  # shellcheck disable=SC2086  # each row is split into arguments on purpose
  scan "$D" $args
  assert_eq "2" "$RC" "usage error: $args"
done

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
# edit can. en-sweep is doc-only, which is not secret-free: a drift fix that
# pastes a config block puts a key in docs/, and its PRs can auto-merge
# unattended, so it is the path where nobody is watching at all.
for skill in en-ship en-resolve-pr en-sweep; do
  f="$REPO_ROOT/skills/$skill/SKILL.md"
  grep -qF 'scripts/ensemble-secret-scan' "$f" \
    && pass "$skill scans before it commits" \
    || fail "$skill must scan the staged diff before committing"
  [ -x "$REPO_ROOT/skills/$skill/scripts/ensemble-secret-scan" ] \
    && pass "$skill carries the scanner it names" \
    || fail "$skill names the scanner but does not carry it"
done

# --- /en-ship scans what the push sends, in both staging cases ----------------
SHIP="$REPO_ROOT/skills/en-ship/SKILL.md"
step6=$(awk '/^6\. \*\*Secret scan/{f=1} f&&/^6a\. /{exit} f' "$SHIP")
assert_contains "$step6" 'ensemble-secret-scan" --outgoing origin/<base>' "step 6 scans every outgoing commit, not just the index"
assert_contains "$step6" '**Exit 2** → stop' "step 6 treats an unreadable range as a stop"
# A finding in a commit cannot be cleared by restoring a file, and --allow-secrets
# would push it anyway: the remedy has to name the commit and rule that out.
assert_contains "$step6" '`commit <sha>` → rewrite that commit' "step 6 gives a committed finding a remedy that clears it"
assert_contains "$step6" 'never `--allow-secrets`' "step 6 rules out --allow-secrets for a committed finding"
assert_contains "$step6" '**`NOTICE`**' "step 6 says what a notice asks of the user"
# Step 8's flip and step 10's commit and message exist only after step 6 ran.
step11=$(awk '/^11\. \*\*Push/{f=1} f&&/^12\. /{exit} f' "$SHIP")
assert_contains "$step11" 'ensemble-secret-scan" --outgoing origin/<base>' "step 11 scans the outgoing commits again before the push"
assert_contains "$step11" 'git reset --soft HEAD~1' "step 11 names how the user unwinds a blocked ship commit"
assert_contains "$(grep -F 'Secret scan' "$REPO_ROOT/skills/en-ship/references/ship-failures.md")" "step 11" \
  "the failures table names the pre-push scan"
for want in '--outgoing <base-ref>' 'NOTICE' '## Remedy by source'; do
  assert_contains "$(cat "$REF")" "$want" "secret-patterns.md documents $want"
done
step7=$(awk '/^7\. \*\*Resolve what to commit/{f=1} f&&/^8\. /{exit} f' "$SHIP")
last7=$(printf '%s\n' "$step7" | grep -v '^[[:space:]]*$' | tail -1)
assert_contains "$last7" "step 6's \`--staged\` scan" "step 7 ends with the staged scan, after any scope revision"

# --- usage --------------------------------------------------------------------
scan "$D" --nonsense
assert_eq "2" "$RC" "an unknown argument is a usage error"

report
