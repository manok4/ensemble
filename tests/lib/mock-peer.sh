#!/usr/bin/env bash
# mock-peer.sh — install a PATH-shadow `claude` and `codex` that replay JSON
# fixtures instead of calling the real CLIs. Used by host-detect tests,
# cross-review parser tests, and (via mock_peer_install_sequence) the
# /en-plan finalize-loop tests where successive peer calls must return
# different verdicts (e.g. revise → revise → approve).

# --- Single-fixture mode (legacy behavior) ---
# Every invocation of `claude` or `codex` returns the same fixture.
mock_peer_install() {
  local shadow_dir="$1"
  local fixture_file="$2"

  mkdir -p "$shadow_dir"

  # Shared stub — both `claude` and `codex` print the fixture's stdout to
  # stdout and the fixture's stderr to stderr, then exit with the recorded
  # exit code. The fixture is JSON: {"stdout":"...","stderr":"...","exit_code":N}.
  cat > "$shadow_dir/_mock_replay" <<'EOF'
#!/usr/bin/env bash
fixture="${MOCK_PEER_FIXTURE:-}"
if [ -z "$fixture" ] || [ ! -f "$fixture" ]; then
  echo "mock-peer: MOCK_PEER_FIXTURE not set or fixture missing" >&2
  exit 99
fi

exit_code=$(jq -r '.exit_code' "$fixture")
jq -r '.stdout' "$fixture"
jq -r '.stderr' "$fixture" >&2
exit "$exit_code"
EOF
  chmod +x "$shadow_dir/_mock_replay"

  # Symlink claude and codex to the shared replay
  ln -sf "$shadow_dir/_mock_replay" "$shadow_dir/claude"
  ln -sf "$shadow_dir/_mock_replay" "$shadow_dir/codex"

  export MOCK_PEER_FIXTURE="$fixture_file"
}

# --- Sequenced-fixture mode ---
# Each call to `claude` or `codex` returns the next fixture in a list and
# advances a counter file. After the list is exhausted, further calls error.
# This is what /en-plan finalize-loop tests use to simulate
# revise → revise → approve sequences.
#
# Usage:
#   mock_peer_install_sequence "$SHADOW_DIR" /tmp/iter-1.json /tmp/iter-2.json /tmp/iter-3.json
mock_peer_install_sequence() {
  local shadow_dir="$1"; shift
  mkdir -p "$shadow_dir"

  local sequence_file="$shadow_dir/_sequence"
  local counter_file="$shadow_dir/_counter"
  : > "$sequence_file"
  for fixture in "$@"; do
    if [ ! -f "$fixture" ]; then
      echo "mock-peer: sequenced fixture missing: $fixture" >&2
      return 99
    fi
    printf '%s\n' "$fixture" >> "$sequence_file"
  done
  echo "0" > "$counter_file"

  cat > "$shadow_dir/_mock_replay" <<EOF
#!/usr/bin/env bash
SEQ_FILE="$sequence_file"
COUNTER_FILE="$counter_file"
EOF
  cat >> "$shadow_dir/_mock_replay" <<'EOF'

idx=$(cat "$COUNTER_FILE")
fixture=$(awk -v n="$idx" 'NR==n+1{print; exit}' "$SEQ_FILE")
total=$(wc -l < "$SEQ_FILE")

if [ -z "$fixture" ]; then
  echo "mock-peer: sequence exhausted (called $((idx+1)) times; sequence has $total entries)" >&2
  exit 99
fi

# Increment the counter for the next call
echo "$((idx+1))" > "$COUNTER_FILE"

exit_code=$(jq -r '.exit_code' "$fixture")
jq -r '.stdout' "$fixture"
jq -r '.stderr' "$fixture" >&2
exit "$exit_code"
EOF
  chmod +x "$shadow_dir/_mock_replay"

  ln -sf "$shadow_dir/_mock_replay" "$shadow_dir/claude"
  ln -sf "$shadow_dir/_mock_replay" "$shadow_dir/codex"
}

# Returns how many times the sequenced mock has been invoked so far.
mock_peer_sequence_calls() {
  local shadow_dir="$1"
  cat "$shadow_dir/_counter" 2>/dev/null || echo "0"
}

mock_peer_uninstall() {
  local shadow_dir="$1"
  rm -rf "$shadow_dir"
  unset MOCK_PEER_FIXTURE
}
