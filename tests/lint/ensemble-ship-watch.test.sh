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

# --- the eval contract --------------------------------------------------------
# The caller eval's this. A missing field is a caller referencing an unset var.
missing=""
for f in STATE REASON PR HEAD CHECKS_TOTAL CHECKS_FAILED CHECKS_PENDING FAILED_NAMES ELAPSED DETAIL; do
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
