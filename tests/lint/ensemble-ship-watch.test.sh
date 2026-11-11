#!/usr/bin/env bash
# tests/lint/ensemble-ship-watch.test.sh
#
# The failure this script exists to prevent, from a real run: /en-ship described
# its watch loop in prose, the agent hand-wrote a poll script, that script
# swallowed gh's stderr, and it looped in silence for forty minutes against a
# sandbox blocking GitHub with a TLS error. The PR merged with a review finding
# unaddressed.
#
# So the assertions here are mostly about FAILING LOUDLY, not about happy paths:
#
#   A BLOCKED NETWORK IS NAMED     not reported as "checks still pending".
#   A RED CHECK IS SETTLED         exit 0 with a reason, because "not clean" and
#                                  "cannot look" must not share an exit code.
#   NOTHING HANGS                  no checks configured, a fork PR, an external
#                                  merge and a timeout all terminate.
#   SILENCE IS A BUG               a heartbeat fires on wall-clock time whether
#                                  or not the state changed.
#
# Every case drives the real script against a stubbed `gh` on PATH. Nothing here
# touches the network, and a stub that is never called is a test that proves
# nothing, so each case asserts on output the stub had to produce.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-ship-watch"

W="$REPO_ROOT/skills/en-ship/scripts/ensemble-ship-watch"
assert_file_exists "$W" "the watch helper exists"
[ -x "$W" ] && pass "the watch helper is executable" || fail "the watch helper is executable"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

stub() { cat > "$WORK/bin/gh"; chmod +x "$WORK/bin/gh"; }

# Runs the script with the stub on PATH. Sets RC, OUT (stdout) and ERRTXT.
run() {
  OUT=$(PATH="$WORK/bin:$PATH" timeout 30 bash "$W" "$@" 2>"$WORK/err"); RC=$?
  ERRTXT=$(cat "$WORK/err")
}
field() { printf '%s\n' "$OUT" | sed -n "s/^SHIP_WATCH_$1='\(.*\)'$/\1/p"; }

open_pr='{"state":"OPEN","isCrossRepository":false,"headRefOid":"abc123"}'

# --- usage --------------------------------------------------------------------
run --pr notanumber
assert_eq "3" "$RC" "a non-numeric --pr is a usage error"
run
assert_eq "3" "$RC" "a missing --pr is a usage error"

# --- a blocked network is named, not swallowed --------------------------------
# The whole reason the file exists. Two consecutive failures end the watch.
stub <<'S'
#!/usr/bin/env bash
echo "error connecting to api.github.com: x509: certificate signed by unknown authority" >&2
exit 1
S
run --pr 7 --poll-seconds 0
assert_eq "gh-error"   "$(field STATE)"  "a TLS failure ends the watch instead of looping"
assert_eq "network-tls" "$(field REASON)" "a certificate failure is classified as network-tls"
assert_eq "1" "$RC" "an unpollable PR exits non-zero"
printf '%s' "$ERRTXT" | grep -qF "needs outbound network access" \
  && pass "the operator is told the environment is blocking GitHub" \
  || fail "a network failure must say the watch needs network access"
printf '%s' "$(field DETAIL)" | grep -qF "x509" \
  && pass "gh's own stderr is carried out, not discarded" \
  || fail "the captured stderr must reach the caller"

# A DNS/proxy failure classifies differently from a certificate one, because the
# fix differs and a single "network" bucket sends the reader to the wrong place.
stub <<'S'
#!/usr/bin/env bash
echo "dial tcp: lookup api.github.com: no such host" >&2
exit 1
S
run --pr 7 --poll-seconds 0
assert_eq "network-unreachable" "$(field REASON)" "an unreachable host is classified separately"

stub <<'S'
#!/usr/bin/env bash
echo "gh auth login required" >&2
exit 1
S
run --pr 7 --poll-seconds 0
assert_eq "auth" "$(field REASON)" "an auth failure is not reported as a network failure"

# --- ONE failure is tolerated; the loop is not that brittle -------------------
stub <<'S'
#!/usr/bin/env bash
n="$WORK_COUNT"
c=$(cat "$n" 2>/dev/null || echo 0); c=$((c+1)); echo "$c" > "$n"
if [ "$c" -le 1 ]; then echo "transient" >&2; exit 1; fi
case "$2" in
  view)   echo '{"state":"OPEN","isCrossRepository":false,"headRefOid":"abc123"}' ;;
  checks) echo '[{"name":"test","bucket":"pass"}]' ;;
esac
S
WORK_COUNT="$WORK/count" OUT=$(WORK_COUNT="$WORK/count" PATH="$WORK/bin:$PATH" timeout 30 bash "$W" --pr 7 --poll-seconds 0 2>/dev/null); RC=$?
assert_eq "checks-settled" "$(field STATE)" "a single transient gh failure does not end the watch"

# --- a red check is settled, not an error -------------------------------------
# "not clean" and "cannot look" must never share an exit code: the caller
# repairs the first and stops for the second.
stub <<'S'
#!/usr/bin/env bash
case "$2" in
  view)   echo '{"state":"OPEN","isCrossRepository":false,"headRefOid":"abc123"}' ;;
  checks) echo '[{"name":"backend-test","bucket":"fail"},{"name":"lint","bucket":"pass"}]' ;;
esac
S
run --pr 7 --poll-seconds 0
assert_eq "checks-settled" "$(field STATE)"        "a failing check is a settled state"
assert_eq "checks-failed"  "$(field REASON)"       "the reason distinguishes red from green"
assert_eq "0"              "$RC"                   "a red check exits 0; the caller decides what to do"
assert_eq "backend-test"   "$(field FAILED_NAMES)" "the failing check is named for the repair step"

stub <<'S'
#!/usr/bin/env bash
case "$2" in
  view)   echo '{"state":"OPEN","isCrossRepository":false,"headRefOid":"abc123"}' ;;
  checks) echo '[{"name":"test","bucket":"pass"}]' ;;
esac
S
run --pr 7 --poll-seconds 0
assert_eq "checks-green" "$(field REASON)" "an all-green run reports checks-green"

# --- nothing hangs ------------------------------------------------------------
# Each of these used to be a plausible way to wait forever.
stub <<'S'
#!/usr/bin/env bash
[ "$2" = view ] && echo '{"state":"MERGED","isCrossRepository":false,"headRefOid":"abc"}' || echo '[]'
S
run --pr 7 --poll-seconds 0
assert_eq "merged" "$(field STATE)" "an externally merged PR ends the watch"

stub <<'S'
#!/usr/bin/env bash
[ "$2" = view ] && echo '{"state":"CLOSED","isCrossRepository":false,"headRefOid":"abc"}' || echo '[]'
S
run --pr 7 --poll-seconds 0
assert_eq "closed" "$(field STATE)" "an externally closed PR ends the watch"

stub <<'S'
#!/usr/bin/env bash
[ "$2" = view ] && echo '{"state":"OPEN","isCrossRepository":false,"headRefOid":"newsha"}' || echo '[]'
S
run --pr 7 --head oldsha --poll-seconds 0
assert_eq "head-moved" "$(field STATE)" "a moved head ends the watch rather than acting on dead results"

stub <<'S'
#!/usr/bin/env bash
[ "$2" = view ] && echo '{"state":"OPEN","isCrossRepository":true,"headRefOid":"abc"}' || echo '[]'
S
run --pr 7 --poll-seconds 0
assert_eq "doctor-failed"        "$(field STATE)"  "a fork PR is reported, never driven"
assert_eq "fork-pr-not-driveable" "$(field REASON)" "the fork refusal names itself"

# A repo with no checks at all: waiting for checks that will never run is the
# same silent hang in a different costume.
stub <<'S'
#!/usr/bin/env bash
[ "$2" = view ] && echo '{"state":"OPEN","isCrossRepository":false,"headRefOid":"abc"}' || echo '[]'
S
run --pr 7 --poll-seconds 0
assert_eq "no-checks-configured" "$(field REASON)" "a repo with no checks settles instead of waiting"

# --- the timeout is real, and it beats while it waits -------------------------
stub <<'S'
#!/usr/bin/env bash
case "$2" in
  view)   echo '{"state":"OPEN","isCrossRepository":false,"headRefOid":"abc"}' ;;
  checks) echo '[{"name":"backend-test","bucket":"pending"}]' ;;
esac
S
run --pr 7 --poll-seconds 1 --max-seconds 3 --heartbeat-seconds 1
assert_eq "timeout" "$(field STATE)" "pending checks eventually time out"
assert_eq "2"       "$RC"            "a timeout has its own exit code"
beats=$(printf '%s' "$ERRTXT" | grep -c 'still watching' || true)
[ "${beats:-0}" -ge 1 ] \
  && pass "a heartbeat fires while nothing is changing ($beats seen)" \
  || fail "silence is the bug this script exists to prevent" "no heartbeat in ${ERRTXT}"
printf '%s' "$ERRTXT" | grep -qF 'backend-test' \
  && pass "the heartbeat names what is still pending" \
  || fail "the heartbeat must name the pending checks"

# --- a review bot still reviewing is not settled -------------------------------
# PR #147: the checks went green at 112s while the Codex connector's code and
# security reviews were still running, step 13 fetched findings once and exited
# clean, and the bot's P2 finding landed after. The connector is not a status
# check; it says what it is doing in a marker inside a PR comment.
#
# The stub serves the REST comments read (`gh api .../issues/7/comments`) from
# $COMMENTS_JSON, so each case below only writes the comments the watch sees.
export COMMENTS_JSON="$WORK/comments.json"
bot_stub() {  # $1 = what `gh pr checks` prints
  cat > "$WORK/bin/gh" <<S
#!/usr/bin/env bash
case "\$*" in
  *comments*) cat "\$COMMENTS_JSON" ;;
  *"pr view"*) echo '{"state":"OPEN","isCrossRepository":false,"headRefOid":"abc123def"}' ;;
  *"pr checks"*) echo '$1' ;;
esac
S
  chmod +x "$WORK/bin/gh"
}
bot_stub '[{"name":"test","bucket":"pass"}]'

# comments <spec>... prints one page of REST comments. A spec is
# login|type|code status|security status|commit sha[|text appended to the body].
# The body copies the comment the connector posted on PR #147: each review
# carries its own commit_sha, and other markers share the comment.
comments() {
  python3 - "$@" <<'PY'
import json, sys
page = []
for spec in sys.argv[1:]:
    login, kind, code, sec, sha, *extra = spec.split("|")
    review = lambda status: {"commit_sha": sha, "has_any_findings": None, "status": status}
    state = {"code_review": review(code), "security_review": review(sec)}
    body = ("<!-- codex-pull-request-review-summary -->\n"
            "<!-- codex-review-state:v1 " + json.dumps(state, separators=(",", ":")) + " -->\n"
            "<!-- codex-security-review:v1 {\"headSha\":\"" + sha + "\",\"status\":\"running\"} -->\n"
            "Codex is reviewing this PR." + "".join(extra))
    page.append({"user": {"login": login, "type": kind}, "body": body,
                 "created_at": "2026-11-10T21:27:15Z", "updated_at": "2026-11-10T21:33:54Z"})
print(json.dumps(page))
PY
}
CODEX="chatgpt-codex-connector[bot]|Bot"
BOTH_PENDING="chatgpt-codex-connector:code_review,chatgpt-codex-connector:security_review"

comments "$CODEX|running|running|abc123def" > "$COMMENTS_JSON"
run --pr 7 --poll-seconds 1 --max-seconds 3 --heartbeat-seconds 1
assert_eq "timeout" "$(field STATE)" "a running Codex review keeps green checks from settling"
assert_eq "2"       "$RC"            "a bot still reviewing at the deadline takes the timeout path"
assert_eq "$BOTH_PENDING" "$(field REVIEW_BOTS_PENDING)" "the evidence names each review still running"
printf '%s' "$ERRTXT" | grep 'still watching' | grep -qF 'chatgpt-codex-connector:code_review' \
  && pass "the heartbeat names the review bot it is waiting on" \
  || fail "the heartbeat must name the running review bot" "$ERRTXT"
BOT_TIMEOUT_OUT="$OUT"

# held <description>: the comments now in $COMMENTS_JSON must hold the watch.
held() {
  run --pr 7 --poll-seconds 1 --max-seconds 2
  assert_eq "timeout" "$(field STATE)" "$1"
  printf '%s' "$(field REVIEW_BOTS_PENDING)" | grep -qF 'chatgpt-codex-connector:code_review' \
    && pass "$1 (the review is named)" \
    || fail "$1 (the review is named)" "got '$(field REVIEW_BOTS_PENDING)'"
}
comments "$CODEX|running|completed|abc123d" > "$COMMENTS_JSON"
held "a seven-character commit prefix of the head holds it"
{ comments "mallory|User|completed|completed|abc123def"; comments "$CODEX|running|running|abc123def"; } > "$COMMENTS_JSON"
held "a running review on a later page of --paginate output still holds the watch"
comments "$CODEX|running|running|abc123def" "chatgpt-codex-connector|User|completed|completed|abc123def" > "$COMMENTS_JSON"
held "a completed marker from a person cannot clear the bot's running review"
comments "$CODEX|running|running|abc123def|
<!-- codex-review-state:v1 {\"code_review\":{\"commit_sha\":\"abc123def\",\"status\":\"completed\"}} -->" > "$COMMENTS_JSON"
held "a second marker appended to the comment cannot clear the first"
comments "$CODEX|running|running|abc123def" "$CODEX|completed|completed|abc123def" > "$COMMENTS_JSON"
held "any bot comment reporting a review running on this head holds it"

# The review finishes mid-watch: the watch waits for it, then settles green.
# The stub flips the marker to completed on its third comments read.
stub <<'S'
#!/usr/bin/env bash
case "$*" in
  *comments*)
    c=$(cat "$WORK_COUNT" 2>/dev/null || echo 0); c=$((c+1)); echo "$c" > "$WORK_COUNT"
    if [ "$c" -ge 3 ]; then cat "$COMMENTS_DONE"; else cat "$COMMENTS_JSON"; fi ;;
  *"pr view"*) echo '{"state":"OPEN","isCrossRepository":false,"headRefOid":"abc123def"}' ;;
  *"pr checks"*) echo '[{"name":"test","bucket":"pass"}]' ;;
esac
S
comments "$CODEX|completed|completed|abc123def" > "$WORK/done.json"
comments "$CODEX|running|completed|abc123def" > "$COMMENTS_JSON"
rm -f "$WORK/count"
OUT=$(WORK_COUNT="$WORK/count" COMMENTS_DONE="$WORK/done.json" PATH="$WORK/bin:$PATH" \
  timeout 30 bash "$W" --pr 7 --poll-seconds 0 --max-seconds 20 2>"$WORK/err"); RC=$?
ERRTXT=$(cat "$WORK/err")
assert_eq "checks-settled" "$(field STATE)"  "the watch settles once the review bot completes"
assert_eq "checks-green"   "$(field REASON)" "a completed review leaves the checks' own reason"
assert_eq "" "$(field REVIEW_BOTS_PENDING)" "nothing is pending once the bot completes"
reads=$(cat "$WORK/count" 2>/dev/null || echo 0)
[ "$reads" -ge 3 ] \
  && pass "the watch polled the bot until it completed" \
  || fail "the watch must keep polling a running review bot" "reads: $reads"
printf '%s' "$ERRTXT" | grep -qF 'chatgpt-codex-connector:code_review' \
  && pass "the wait on the bot is reported while it lasts" \
  || fail "the watch must say it is waiting on a review bot" "$ERRTXT"

# Negative controls: the gate is a recognised marker from the bot account about
# this head, nothing looser. Each of these must settle green on the first poll.
bot_stub '[{"name":"test","bucket":"pass"}]'
neg() {  # $1=description
  run --pr 7 --poll-seconds 1 --max-seconds 3
  assert_eq "checks-green" "$(field REASON)" "$1"
  assert_eq "" "$(field REVIEW_BOTS_PENDING)" "$1 (no bot pending)"
}
comments "$CODEX|completed|completed|abc123def" > "$COMMENTS_JSON"
neg "a completed Codex review does not hold the watch"
comments "chatgpt-codex-connector|User|running|running|abc123def" > "$COMMENTS_JSON"
neg "a person whose login is the bot's name cannot hold the watch"
comments "chatgpt-codex-connector[bot]|User|running|running|abc123def" > "$COMMENTS_JSON"
neg "the bot's login on an account that is not a Bot is ignored"
comments "other-reviewer[bot]|Bot|running|running|abc123def" > "$COMMENTS_JSON"
neg "a marker from a different bot is ignored"
comments "$CODEX|running|running|0ldc0mm1t" > "$COMMENTS_JSON"
neg "a running review of another commit does not hold this head"
comments "$CODEX|running|running|abc" > "$COMMENTS_JSON"
neg "a commit prefix too short to identify the head does not hold it"
printf '%s\n' '[{"user":{"login":"chatgpt-codex-connector[bot]","type":"Bot"},"body":"Codex is running, see 👀"}]' > "$COMMENTS_JSON"
neg "a bot comment without the marker is not guessed at"
printf '%s\n' '[{"user":{"login":"chatgpt-codex-connector[bot]","type":"Bot"},"body":"see <!-- codex-review-state:v1 {\"code_review\":{\"commit_sha\":\"abc123def\",\"status\":\"running\"}} -->"}]' > "$COMMENTS_JSON"
neg "a marker that does not start a line is not a marker"
printf '%s\n' '[{"user":{"login":"chatgpt-codex-connector[bot]","type":"Bot"},"body":"<!-- codex-review-state:v1 {\"code_review\":{\"status\":\"running\"}} -->"}]' > "$COMMENTS_JSON"
neg "a running review that names no commit does not hold this head"
printf '%s\n' '[{"user":{"login":"chatgpt-codex-connector[bot]","type":"Bot"},"body":"<!-- codex-review-state:v1 {not json $(touch '"$WORK"'/pwned)} -->"}]' > "$COMMENTS_JSON"
neg "an unparseable marker is ignored"
[ ! -e "$WORK/pwned" ] \
  && pass "comment text is parsed, never executed" \
  || fail "the watch executed text from a PR comment"

# Checks that go back to pending after the bot was seen running leave no stale
# bot in the evidence: the timeout names what is pending now.
cat > "$WORK/bin/gh" <<'S'
#!/usr/bin/env bash
case "$*" in
  *comments*) cat "$COMMENTS_JSON" ;;
  *"pr view"*) echo '{"state":"OPEN","isCrossRepository":false,"headRefOid":"abc123def"}' ;;
  *"pr checks"*)
    c=$(cat "$WORK_COUNT" 2>/dev/null || echo 0); c=$((c+1)); echo "$c" > "$WORK_COUNT"
    if [ "$c" -le 1 ]; then echo '[{"name":"test","bucket":"pass"}]'
    else echo '[{"name":"test","bucket":"pending"}]'; fi ;;
esac
S
comments "$CODEX|running|running|abc123def" > "$COMMENTS_JSON"
rm -f "$WORK/count"
OUT=$(WORK_COUNT="$WORK/count" PATH="$WORK/bin:$PATH" timeout 30 bash "$W" --pr 7 --poll-seconds 1 --max-seconds 3 2>"$WORK/err"); RC=$?
assert_eq "timeout" "$(field STATE)" "a re-run check that stays pending times out"
assert_eq "" "$(field REVIEW_BOTS_PENDING)" "a bot read before the checks unsettled is not reported as pending"

# A failed comments read is never "no bot running". The doctor and checks
# calls succeed here, so only the comments read fails: twice in a row is
# gh-error, the same rule as every other gh call.
stub <<'S'
#!/usr/bin/env bash
case "$*" in
  *comments*) echo "error connecting to api.github.com: x509: certificate signed by unknown authority" >&2; exit 1 ;;
  *"pr view"*) echo '{"state":"OPEN","isCrossRepository":false,"headRefOid":"abc123def"}' ;;
  *"pr checks"*) echo '[{"name":"test","bucket":"pass"}]' ;;
esac
S
run --pr 7 --poll-seconds 0 --max-seconds 20
assert_eq "gh-error"    "$(field STATE)"  "a failing comments read ends the watch instead of settling"
assert_eq "network-tls" "$(field REASON)" "the comments read failure is classified like any gh failure"

bot_stub '[{"name":"test","bucket":"pass"}]'
printf 'not json\n' > "$COMMENTS_JSON"
run --pr 7 --poll-seconds 0 --max-seconds 20
assert_eq "unparseable-comments" "$(field REASON)" "comments gh cannot have meant are an error, not an empty list"

OUT="$BOT_TIMEOUT_OUT"


# --- the eval contract --------------------------------------------------------
# The caller eval's this. A missing field is a caller referencing an unset var.
missing=""
for f in STATE REASON PR HEAD CHECKS_TOTAL CHECKS_FAILED CHECKS_PENDING FAILED_NAMES REVIEW_BOTS_PENDING ELAPSED DETAIL; do
  printf '%s\n' "$OUT" | grep -q "^SHIP_WATCH_$f='" || missing="$missing $f"
done
[ -z "$missing" ] \
  && pass "every documented SHIP_WATCH_ field is emitted" \
  || fail "the eval contract is incomplete" "missing:$missing"

if ( eval "$OUT" ) >/dev/null 2>&1; then
  pass "the emitted block is eval-safe"
else
  fail "the emitted block must be eval-safe"
fi

report
