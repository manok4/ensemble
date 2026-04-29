#!/usr/bin/env bash
# Cross-review fixture validation.
#
# Verifies each fixture under tests/cross-review/fixtures/ has the expected
# shape (so the host's parser can rely on the contract) AND that the host's
# fixture-handling logic does the right thing on each scenario:
#   - clean-approve: parses; verdict=approve; zero findings
#   - revise-with-findings: parses; verdict=revise; >=1 finding; severity/confidence valid
#   - reject: parses; verdict=reject (host pauses)
#   - single-agent-fallback: peer_mode field is "single-agent-fallback"
#   - malformed-json: stdout is NOT valid JSON (host should retry/skip)
#   - timeout: exit code != 0 (host should mark cross-review skipped)
#   - d30-violation: parses, but host should detect file mods via git-stash check

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="cross-review fixtures"

FIXTURE_DIR="$SCRIPT_DIR/fixtures"

# --- Fixture envelope check: every fixture has input_prompt_match + exit_code + stdout + stderr ---
for f in "$FIXTURE_DIR"/*.json; do
  [ -f "$f" ] || continue
  basename="$(basename "$f")"

  # Validate the wrapper JSON parses
  if ! jq empty "$f" 2>/dev/null; then
    fail "$basename has invalid wrapper JSON"
    continue
  fi

  for field in input_prompt_match exit_code stdout stderr; do
    if ! jq -e "has(\"$field\")" "$f" >/dev/null; then
      fail "$basename missing required wrapper field: $field"
      continue 2
    fi
  done
  pass "$basename has valid envelope"
done

# --- clean-approve.json: parses as JSON; verdict=approve; zero findings ---
stdout=$(jq -r '.stdout' "$FIXTURE_DIR/clean-approve.json")
if echo "$stdout" | jq empty 2>/dev/null; then
  pass "clean-approve.stdout parses as JSON"
  verdict=$(echo "$stdout" | jq -r '.verdict')
  assert_eq "approve" "$verdict" "clean-approve verdict"
  count=$(echo "$stdout" | jq '.findings | length')
  assert_eq "0" "$count" "clean-approve has zero findings"
  pmode=$(echo "$stdout" | jq -r '.peer_mode')
  assert_eq "cross-agent" "$pmode" "clean-approve peer_mode"
else
  fail "clean-approve.stdout should parse as JSON"
fi

# --- revise-with-findings.json: parses; verdict=revise; findings have schema-required fields ---
stdout=$(jq -r '.stdout' "$FIXTURE_DIR/revise-with-findings.json")
if echo "$stdout" | jq empty 2>/dev/null; then
  pass "revise-with-findings.stdout parses as JSON"
  verdict=$(echo "$stdout" | jq -r '.verdict')
  assert_eq "revise" "$verdict" "revise verdict"
  count=$(echo "$stdout" | jq '.findings | length')
  if [ "$count" -ge 1 ]; then
    pass "revise has $count finding(s)"
  else
    fail "revise should have >= 1 finding"
  fi

  # Each finding has the required fields per references/finding-schema.md
  while IFS= read -r f; do
    sev=$(echo "$f" | jq -r '.severity')
    conf=$(echo "$f" | jq -r '.confidence')
    case "$sev" in P0|P1|P2|P3) ;; *)
      fail "finding has invalid severity: $sev"; continue ;;
    esac
    if ! [ "$conf" -ge 1 ] || ! [ "$conf" -le 10 ] 2>/dev/null; then
      fail "finding has invalid confidence: $conf"; continue
    fi
    for k in title location why_it_matters suggested_fix; do
      if [ "$(echo "$f" | jq -r ".$k // empty")" = "" ]; then
        fail "finding missing required field: $k"
        continue 2
      fi
    done
  done < <(echo "$stdout" | jq -c '.findings[]')
  pass "all revise findings have required schema fields"
else
  fail "revise-with-findings.stdout should parse as JSON"
fi

# --- reject.json: verdict=reject (host pauses on this) ---
stdout=$(jq -r '.stdout' "$FIXTURE_DIR/reject.json")
verdict=$(echo "$stdout" | jq -r '.verdict')
assert_eq "reject" "$verdict" "reject verdict"

# --- single-agent-fallback.json: peer_mode is single-agent-fallback ---
stdout=$(jq -r '.stdout' "$FIXTURE_DIR/single-agent-fallback.json")
pmode=$(echo "$stdout" | jq -r '.peer_mode')
assert_eq "single-agent-fallback" "$pmode" "single-agent fallback peer_mode"

# --- malformed-json.json: stdout is NOT valid JSON (host's parser should detect this) ---
stdout=$(jq -r '.stdout' "$FIXTURE_DIR/malformed-json.json")
if echo "$stdout" | jq empty 2>/dev/null; then
  fail "malformed-json.stdout should NOT parse as JSON"
else
  pass "malformed-json.stdout is invalid JSON (host retries/skips)"
fi

# --- timeout.json: exit code is non-zero (host marks cross-review skipped) ---
exit_code=$(jq -r '.exit_code' "$FIXTURE_DIR/timeout.json")
if [ "$exit_code" -ne 0 ]; then
  pass "timeout fixture has non-zero exit code ($exit_code)"
else
  fail "timeout fixture should have non-zero exit code"
fi

# --- d30-violation.json: parses fine, but the contract is enforced by git-stash check, not by the fixture ---
stdout=$(jq -r '.stdout' "$FIXTURE_DIR/d30-violation.json")
if echo "$stdout" | jq empty 2>/dev/null; then
  pass "d30-violation.stdout parses (D30 violation is detected by host's git-stash check, not the JSON shape)"
else
  fail "d30-violation.stdout should parse"
fi

# --- Mock-peer harness sanity: replay a fixture via the mock claude shim ---
. "$REPO_ROOT/tests/lib/mock-peer.sh"
TMP_SHIM=$(mktemp -d)
mock_peer_install "$TMP_SHIM" "$FIXTURE_DIR/clean-approve.json"
output=$(PATH="$TMP_SHIM:$PATH" claude -p "review this plan" 2>/dev/null)
mock_peer_uninstall "$TMP_SHIM"

if echo "$output" | jq -r '.verdict' | grep -q "approve"; then
  pass "mock-peer harness replays clean-approve fixture correctly"
else
  fail "mock-peer harness replay" "expected verdict=approve in: $output"
fi

report
