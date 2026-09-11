#!/usr/bin/env bash
# tests/lint/en-review-outcome-event.test.sh
#
# /en-review's corroboration split is the answer to the parked peer question,
# and it is the ONE thing no helper can observe: the buckets exist only in the
# reconciliation the model performs, and ensemble-peer-invoke contains no notion
# of corroboration. So this single call point is model-emitted on purpose, and
# what a lint can guard is the shape of the contract around it.
#
#   IT EXISTS, AFTER RECONCILIATION   an outcome recorded before the buckets are
#                                     computed would record nothing.
#   ITS KEYS SURVIVE THE ALLOWLIST    both sides are parsed and compared, so a
#                                     key added to one and not the other fails
#                                     here rather than becoming a column that is
#                                     quietly always zero.
#   THE PAYLOAD IS CARRIED            en-review holds the helper and the
#                                     reference, so the call is not a mention.
#   AND IT REACHES THE REPORT         an end-to-end run asserts the numbers come
#                                     back out of `ensemble-metrics --peer-value`.
#
# Negative controls at authoring: renaming one key in the SKILL.md call turned
# the allowlist cross-check red; moving the call above step 10 turned the
# ordering assertion red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review outcome event"

SK="$REPO_ROOT/skills/en-review/SKILL.md"
RM="$REPO_ROOT/skills/en-review/scripts/ensemble-run-metrics"
MET="$REPO_ROOT/bin/ensemble-metrics"

# --- the call exists, in a numbered step, after reconciliation ---------------
emit_line=$(grep -n -- '--kind outcome' "$SK" | head -1 | cut -d: -f1)
[ -n "$emit_line" ] \
  && pass "en-review records an outcome event" \
  || fail "en-review has no --kind outcome call" \
          "the corroboration split is the one thing no helper can see"

recon_line=$(grep -nE '^10\. \*\*Synthesize' "$SK" | head -1 | cut -d: -f1)
[ -n "$recon_line" ] \
  && pass "the reconciliation step is findable" \
  || fail "cannot find the reconciliation step to order against"

[ -n "$emit_line" ] && [ -n "$recon_line" ] && [ "$emit_line" -gt "$recon_line" ] \
  && pass "the outcome is recorded after reconciliation, not before" \
  || fail "the outcome call precedes reconciliation" \
          "emit at line $emit_line, reconciliation at line $recon_line; the buckets would not exist yet"

step=$(sed -n "1,${emit_line}p" "$SK" | grep -cE '^[0-9]+[a-z]?\. \*\*' || true)
[ "$step" -ge 10 ] \
  && pass "the call sits inside the numbered process flow" \
  || fail "the outcome call is not reachable from the process flow"

# --- both sides of the allowlist agree ---------------------------------------
# Parsed from each file rather than compared against a list written here: a
# fixed list in this test would be a third copy to drift.
skill_keys=$(grep -o -- '--kind outcome --json .*' "$SK" \
  | grep -oE '"[a-z_]+":' | tr -d '":' | sort -u)
allow_keys=$(sed -n '/"outcome":/,/]/p' "$RM" | grep -oE '"[a-z_]+"' | tr -d '"' \
  | grep -v '^outcome$' | sort -u)
[ -n "$skill_keys" ] && pass "the SKILL.md call names keys" || fail "no keys parsed from the call"
[ -n "$allow_keys" ] && pass "the allowlist names keys" || fail "no keys parsed from the allowlist"

missing=$(comm -23 <(printf '%s\n' "$skill_keys") <(printf '%s\n' "$allow_keys"))
[ -z "$missing" ] \
  && pass "every key the skill emits survives the allowlist" \
  || fail "the skill emits keys the allowlist drops" \
          "dropped at the write, so they would be silently always absent: $(printf '%s' "$missing" | tr '\n' ' ')"

# --- the payload is carried, so the call is not a mention --------------------
assert_file_exists "$RM" "en-review carries the run-metrics helper"
assert_file_exists "$REPO_ROOT/skills/en-review/references/run-metrics.md" \
  "en-review carries the event-vocabulary reference"

# --- end to end, through the report -----------------------------------------
# A key that survives the allowlist but is named differently from what the
# report reads would pass every assertion above. This one drives the whole
# chain: emit, rollup, report.
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT INT TERM HUP
export ENSEMBLE_ANALYTICS_DIR="$W/analytics"
( cd "$W" && git init -q . && git config user.email t@e && git config user.name t )
L=$( cd "$W" && bash "$RM" start --skill en-review )
( cd "$W" && bash "$RM" emit --kind peer --json '{"peer":"codex","decision":"on","elapsed_s":126}' )
( cd "$W" && bash "$RM" emit --kind outcome \
    --json '{"verdict":"revise","findings_total":9,"peer_only":3,"corroborated":4,"host_only":2,"applied":6,"deferred":2,"disagreed":1}' )
assert_eq "null" "$(grep '"kind":"outcome"' "$L" | tail -1 | jq -r '.dropped')" \
  "the documented payload loses no key at the write"
( cd "$W" && bash "$RM" finish "$L" )

roll="$ENSEMBLE_ANALYTICS_DIR/$(basename "$W").jsonl"
assert_file_exists "$roll" "the run reaches the durable rollup"
assert_eq "3" "$(jq -r '.outcome.peer_only' "$roll")"     "the rollup carries peer_only"
assert_eq "1" "$(jq -r '.counts.outcome' "$roll")"        "and counts the outcome event"

j=$("$MET" --peer-value --json --repo "$(basename "$W")" --analytics-dir "$ENSEMBLE_ANALYTICS_DIR")
assert_eq "1" "$(printf '%s' "$j" | jq -r '.runs_scored')" "--peer-value scores the run"
assert_eq "3" "$(printf '%s' "$j" | jq -r '.rows[0].peer_only')"    "and reports the peer-only count"
assert_eq "4" "$(printf '%s' "$j" | jq -r '.rows[0].corroborated')" "the corroborated count"
assert_eq "2" "$(printf '%s' "$j" | jq -r '.rows[0].host_only')"    "and the host-only count"

report
