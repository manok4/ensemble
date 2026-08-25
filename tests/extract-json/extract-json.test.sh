#!/usr/bin/env bash
# Tests for bin/ensemble-extract-json and its wiring into ensemble-peer-invoke.
# Drives the REAL function, so the recovery contract is behaviourally tested
# rather than asserted in prose (D41).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-extract-json"

. "$REPO_ROOT/bin/ensemble-extract-json"

ok_case() { # $1=label $2=input $3=expected
  local got; got=$(printf '%s' "$2" | ensemble_extract_json 2>/dev/null) || got="<exit-1>"
  if [ "$got" = "$3" ]; then pass "$1"; else fail "$1" "expected [$3] got [$got]"; fi
}
fail_case() { # $1=label $2=input — must exit non-zero so the caller's retry still fires
  if printf '%s' "$2" | ensemble_extract_json >/dev/null 2>&1; then
    fail "$1" "should have exited non-zero"
  else
    pass "$1"
  fi
}

# --- the failure this actually exists for: fences and prose ---
ok_case "bare object survives untouched"      '{"a":1}'                    '{"a":1}'
ok_case "json-fenced response recovered"      '```json
{"a":1}
```'                                                                        '{"a":1}'
ok_case "unlabelled fence recovered"          '```
{"a":1}
```'                                                                        '{"a":1}'
ok_case "prose preamble stripped"             'Here is my review:
{"a":1}'                                                                    '{"a":1}'
ok_case "quotes in prose do not confuse it"   'The "verdict" follows:
{"a":1}'                                                                    '{"a":1}'
ok_case "trailing commentary stripped"        '{"a":1}
Hope that helps!'                                                           '{"a":1}'

# --- string-awareness: braces inside literals must not move the depth counter ---
ok_case "brace inside a string literal"       '{"a":"}"}'                   '{"a":"}"}'
ok_case "escaped quote inside a string"       '{"a":"\""}'                  '{"a":"\""}'
ok_case "nested objects and arrays"           'x {"a":{"b":[1,2]},"c":"}"} y' '{"a":{"b":[1,2]},"c":"}"}'

# --- must FAIL so the existing retry is not pre-empted ---
fail_case "no JSON at all"                    'no json here'
fail_case "unterminated object"               '{"a":1'
fail_case "balanced but invalid JSON"         '{"a":1,}'
fail_case "empty input"                       ''

# --- wiring: a successful peer call is normalised in place ---
FAKE="${TMPDIR:-/tmp}/ejfake.$$"; OUT="${TMPDIR:-/tmp}/ejout.$$"; PF="${TMPDIR:-/tmp}/ejpf.$$"
cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'Sure:\n```json\n{"verdict":"approve","findings":[],"summary":"a { b"}\n```\ndone\n'
EOF
chmod +x "$FAKE"; printf 'p' > "$PF"
( . "$REPO_ROOT/bin/ensemble-peer-invoke"
  ensemble_peer_invoke --peer-cmd "$FAKE" --peer-format "" \
    --prompt-file "$PF" --out-file "$OUT" --peer-mode cross-agent >/dev/null 2>&1 )
if [ "$(cat "$OUT")" = '{"verdict":"approve","findings":[],"summary":"a { b"}' ]; then
  pass "peer-invoke normalises a fenced peer response in place"
else
  fail "peer-invoke must normalise the out-file" "got [$(cat "$OUT")]"
fi

# --- wiring fail-safe: an unrecoverable response is left BYTE-FOR-BYTE intact ---
cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'total garbage, no object here\n'
EOF
chmod +x "$FAKE"
( . "$REPO_ROOT/bin/ensemble-peer-invoke"
  ensemble_peer_invoke --peer-cmd "$FAKE" --peer-format "" \
    --prompt-file "$PF" --out-file "$OUT" --peer-mode cross-agent >/dev/null 2>&1 )
if [ "$(cat "$OUT")" = "total garbage, no object here" ]; then
  pass "unrecoverable response left intact for the caller's retry"
else
  fail "must not partially overwrite an unrecoverable response" "got [$(cat "$OUT")]"
fi
rm -f "$FAKE" "$OUT" "$PF"

report
