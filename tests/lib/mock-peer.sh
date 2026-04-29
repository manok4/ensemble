#!/usr/bin/env bash
# mock-peer.sh — install a PATH-shadow `claude` and `codex` that replay JSON
# fixtures instead of calling the real CLIs. Used by host-detect tests and
# cross-review parser tests.
#
# Usage: source this file with FIXTURE_FILE=<path-to-json> and SHADOW_DIR
# pointing at a tempdir; then add SHADOW_DIR to PATH ahead of system PATH.

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

mock_peer_uninstall() {
  local shadow_dir="$1"
  rm -rf "$shadow_dir"
  unset MOCK_PEER_FIXTURE
}
