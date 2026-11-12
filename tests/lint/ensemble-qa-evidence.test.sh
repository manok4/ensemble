#!/usr/bin/env bash
# tests/lint/ensemble-qa-evidence.test.sh
#
# /en-qa keeps a video of each verified flow and renders the run as one page.
# The script that does it sits between a driver's recorder and a reviewer, so
# the assertions are about what must never happen on the way:
#
#   THE SOURCE SURVIVES      the recorder's file is only ever read, on every
#                            path, including a failed encode and a source that
#                            already sits where the output would go.
#   A NAME MEANS A FILE      `video: <file>` is printed only when that file
#                            exists and is non-empty; anything else is
#                            `video: unavailable: <reason>`, and still exit 0.
#   THE PAGE LINKS ONLY      a flows.json value reaches a src or href only when
#   LOCAL MEDIA              it is a plain relative path; a scheme, an absolute
#                            path, a `..` or an escape renders as text.
#
# Every case drives the real script. ffmpeg is stubbed on PATH, and a stub that
# is never called proves nothing, so the encode cases assert on its argv log.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-qa-evidence"

S="$REPO_ROOT/skills/en-qa/scripts/ensemble-qa-evidence"
assert_file_exists "$S" "the evidence helper exists"
[ -x "$S" ] && pass "the evidence helper is executable" || fail "the evidence helper is executable"

WORK=$(mktemp -d); trap 'chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

# A PATH with no ffmpeg on it, built from links to the tools the script uses,
# so the no-encoder case holds on a runner that ships ffmpeg in /usr/bin.
BARE="$WORK/bare"; mkdir -p "$BARE"
for t in bash cp mv rm mkdir tr dirname basename cat python3 git ln find sed date id; do
  p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$BARE/$t"
done
STUB="$WORK/stub"; mkdir -p "$STUB"

# An ffmpeg stub: logs its argv, writes a non-empty file at its last argument
# when $1 is ok, exits 1 when it is fail.
ffmpeg_stub() {
  cat > "$STUB/ffmpeg" <<EOF
#!/bin/sh
printf '%s\n' "\$@" >> "$WORK/ffmpeg.argv"
[ "$1" = ok ] || exit 1
for last; do :; done
printf 'encoded' > "\$last"
EOF
  chmod +x "$STUB/ffmpeg"; : > "$WORK/ffmpeg.argv"
}

# run <path-dirs> <args...>: sets RC, OUT (stdout) and ERRTXT.
run() {
  local p="$1"; shift
  OUT=$(PATH="$p" bash "$S" "$@" 2>"$WORK/err"); RC=$?
  ERRTXT=$(cat "$WORK/err")
}

D="$WORK/run"; mkdir -p "$D"
printf 'raw-recording-bytes' > "$WORK/rec.webm"

# --- video: encode when ffmpeg is present -------------------------------------
ffmpeg_stub ok
run "$STUB:$BARE" video --run-dir "$D" --flow F3 --src "$WORK/rec.webm"
assert_eq "0" "$RC" "video exits 0 on an encode"
assert_eq "video: F3.mp4" "$OUT" "an encode prints the mp4 name, and only that line"
[ -s "$D/F3.mp4" ] && pass "the encoded clip is in the run dir" || fail "the encoded clip is in the run dir"
grep -q 'mpdecimate' "$WORK/ffmpeg.argv" \
  && pass "the encode strips idle frames" || fail "the encode strips idle frames" "$(cat "$WORK/ffmpeg.argv")"
assert_file_exists "$WORK/rec.webm" "the source survives an encode"

# --- video: no ffmpeg keeps the raw recording ---------------------------------
printf 'upper-case-ext' > "$WORK/rec.WEBM"
run "$BARE" video --run-dir "$D" --flow F3 --src "$WORK/rec.WEBM"
assert_eq "video: F3.webm" "$OUT" "without ffmpeg the raw file is kept, extension lowercased"
cmp -s "$WORK/rec.WEBM" "$D/F3.webm" && pass "the kept copy is byte-identical" || fail "the kept copy is byte-identical"
assert_file_exists "$WORK/rec.WEBM" "the source survives a copy"
printf 'no-extension' > "$WORK/rec"
run "$BARE" video --run-dir "$D" --flow F4 --src "$WORK/rec"
assert_eq "video: F4.webm" "$OUT" "a source with no extension is kept as webm"

# --- video: the flow id is sanitized, and a re-run replaces the clip ----------
ffmpeg_stub ok
run "$STUB:$BARE" video --run-dir "$D" --flow 'F 3/x' --src "$WORK/rec.webm"
assert_eq "video: F-3-x.mp4" "$OUT" "a flow id outside [A-Za-z0-9._-] is sanitized"
assert_file_exists "$D/F-3-x.mp4" "the sanitized clip is written inside the run dir"
printf 'stale' > "$D/F5.webm"
printf 'fresh' > "$WORK/fresh.webm"
run "$BARE" video --run-dir "$D" --flow F5 --src "$WORK/fresh.webm"
assert_eq "fresh" "$(cat "$D/F5.webm")" "a second call for the same flow overwrites its clip"

# --- video: a missing source is unavailable, not an error ---------------------
run "$BARE" video --run-dir "$D" --flow F6 --src "$WORK/nope.webm"
assert_eq "0" "$RC" "a missing source still exits 0"
assert_eq "video: unavailable: no recording at $WORK/nope.webm" "$OUT" "a missing source is named"
: > "$WORK/empty.webm"
run "$BARE" video --run-dir "$D" --flow F6 --src "$WORK/empty.webm"
assert_eq "video: unavailable: no recording at $WORK/empty.webm" "$OUT" "an empty source counts as missing"

# --- video: a failed encode falls back to the raw file, leaving no debris -----
ffmpeg_stub fail
rm -f "$D"/F7.*
run "$STUB:$BARE" video --run-dir "$D" --flow F7 --src "$WORK/rec.webm"
assert_eq "video: F7.webm" "$OUT" "a failed encode keeps the raw recording"
assert_contains "$ERRTXT" "ffmpeg failed; kept the raw recording" "a failed encode says so on stderr"
assert_file_missing "$D/F7.mp4" "a failed encode leaves no mp4"
leftover=$(ls -A "$D" | grep -c '^\.F7\.tmp\.' || true)
assert_eq "0" "$leftover" "a failed encode leaves no temp file"

# --- video: a source already in place is never touched ------------------------
# The P1 the plan's review found twice: encoding or copying a file over itself.
printf 'in-place-bytes' > "$D/F8.mp4"; cp "$D/F8.mp4" "$WORK/F8.orig"
ffmpeg_stub fail
run "$STUB:$BARE" video --run-dir "$D" --flow F8 --src "$D/F8.mp4"
assert_eq "video: F8.mp4" "$OUT" "an aliased source is reported in place (failing encoder)"
cmp -s "$D/F8.mp4" "$WORK/F8.orig" && pass "an aliased source is byte-identical after a failing encoder" \
  || fail "an aliased source is byte-identical after a failing encoder"
ffmpeg_stub ok
run "$STUB:$BARE" video --run-dir "$D" --flow F8 --src "$D/F8.mp4"
assert_eq "video: F8.mp4" "$OUT" "an aliased source is reported in place (working encoder)"
cmp -s "$D/F8.mp4" "$WORK/F8.orig" && pass "an aliased source is byte-identical after a working encoder" \
  || fail "an aliased source is byte-identical after a working encoder"
[ -s "$WORK/ffmpeg.argv" ] && fail "no encode runs on an aliased source" "$(cat "$WORK/ffmpeg.argv")" \
  || pass "no encode runs on an aliased source"

# --- video: a write that cannot happen is unavailable, and exits 0 ------------
if [ "$(id -u)" = 0 ]; then
  pass "permission cases skipped: running as root, where chmod does not bite"
else
  printf 'locked' > "$WORK/locked.webm"; chmod 000 "$WORK/locked.webm"
  run "$BARE" video --run-dir "$D" --flow F9 --src "$WORK/locked.webm"
  assert_eq "0" "$RC" "an unreadable source exits 0"
  assert_contains "$OUT" "video: unavailable: could not write F9.webm:" "an unreadable source is unavailable"
  assert_file_missing "$D/F9.webm" "an unreadable source leaves no clip"
  chmod 644 "$WORK/locked.webm"
  RO="$WORK/ro"; mkdir -p "$RO"; chmod 555 "$RO"
  run "$BARE" video --run-dir "$RO" --flow F9 --src "$WORK/rec.webm"
  assert_eq "0" "$RC" "a read-only run dir exits 0"
  assert_contains "$OUT" "video: unavailable: could not write F9.webm:" "a read-only run dir is unavailable"
  chmod 755 "$RO"
fi

# --- video: usage -------------------------------------------------------------
run "$BARE" video --flow F3 --src "$WORK/rec.webm"
assert_eq "64" "$RC" "video without --run-dir is a usage error"
assert_contains "$ERRTXT" "usage:" "a usage error prints a usage line"
run "$BARE" frobnicate
assert_eq "64" "$RC" "an unknown subcommand is a usage error"

# --- page: renders flows, video and text --------------------------------------
P="$WORK/page"; mkdir -p "$P"
cat > "$P/flows.json" <<'J'
{"run_id": "20261112T161420Z", "flows": [
  {"id": "F3", "name": "Sign in", "outcome": "Pass", "reason": "", "video": "F3.mp4",
   "screenshots": ["shots/F3-1.png", "/etc/x.png", "javascript:alert(1)",
                   "https://example.com/x.png", "%2e%2e/x.png", "shots/F3 1.png"]},
  {"id": "F4", "name": "<script>x</script>", "outcome": "Skip", "reason": "no driver",
   "video": "unavailable: no recorder", "screenshots": []},
  {"id": "F5", "name": "Escape", "outcome": "Fail", "reason": "wrong page",
   "video": "../secret.mp4", "screenshots": []}
]}
J
run "$BARE" page --run-dir "$P"
assert_eq "0" "$RC" "page exits 0"
assert_eq "page: $P/index.html" "$OUT" "page names the file it wrote"
H=$(cat "$P/index.html" 2>/dev/null)
assert_contains "$H" "<title>QA run 20261112T161420Z</title>" "the page is titled by run id"
assert_contains "$H" '<video controls preload="metadata">' "a relative video renders a player"
assert_contains "$H" '<source src="F3.mp4" type="video/mp4">' "the player sources the clip with its type"
assert_contains "$H" "unavailable: no recorder" "an unavailable video renders as text"
assert_contains "$H" "prefers-color-scheme: dark" "the page carries a dark palette"
assert_not_contains "$H" "<script>x</script>" "a flow name is escaped"
assert_contains "$H" "&lt;script&gt;x&lt;/script&gt;" "the escaped name still shows"
assert_contains "$H" 'src="shots/F3-1.png"' "a local screenshot is an image"
assert_contains "$H" 'href="shots/F3-1.png"' "a local screenshot is a link"
# The two local values are the only attributes on the page. Matching the whole
# set, not each hostile value, because an encoder can rewrite a value
# (javascript: -> javascript%3A) that still reaches an attribute.
attrs=$(printf '%s' "$H" | grep -oE '(src|href)="[^"]*"' | sort -u | tr '\n' ' ')
assert_eq 'href="shots/F3-1.png" src="F3.mp4" src="shots/F3-1.png" ' "$attrs" \
  "only plain relative paths reach a src or href"
for bad in ../secret.mp4 /etc/x.png 'javascript:alert(1)' https://example.com/x.png %2e%2e/x.png 'shots/F3 1.png'; do
  assert_contains "$H" "$bad" "$bad renders as text"
done
printf '%s' "$H" | grep -qE '(src|href)="https?:|<link |<script' \
  && fail "the page loads no external asset and runs no script" \
  || pass "the page loads no external asset and runs no script"

# --- page: a missing or malformed ledger is an error --------------------------
E="$WORK/empty"; mkdir -p "$E"
run "$BARE" page --run-dir "$E"
assert_eq "1" "$RC" "page with no flows.json exits 1"
assert_contains "$ERRTXT" "page: no readable flows.json in $E" "a missing ledger is named"
printf '{"flows": 3}' > "$E/flows.json"
run "$BARE" page --run-dir "$E"
assert_eq "1" "$RC" "page with a non-list flows exits 1"
assert_file_missing "$E/index.html" "a malformed ledger writes no page"

report
