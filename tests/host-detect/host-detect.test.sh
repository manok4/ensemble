#!/usr/bin/env bash
# Host-detection tests.
#
# Mock the environment (CLAUDE_CODE_VERSION, CODEX_HOME, ENSEMBLE_HOST,
# ~/.ensemble/config.json) and PATH (presence of `claude` / `codex` shims),
# then `eval` bin/ensemble-detect-host's output and assert the resolved
# variables.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="host-detect"

DETECT="$REPO_ROOT/bin/ensemble-detect-host"

# Helper: set up a mocked environment and run detect.
# $1 = scenario label (for failure diagnostics)
# Then a series of KEY=VALUE pairs describing the scenario:
#   has_claude=true|false
#   has_codex=true|false
#   env_claude=true|false   (CLAUDE_CODE_VERSION set)
#   env_codex=true|false    (CODEX_HOME set)
#   override=auto|cross-agent-only|single-agent-only|off  (~/.ensemble/config.json)
#   ensemble_host=<value>   (ENSEMBLE_HOST env var)
#
# Returns by setting OUTPUT_HOST, OUTPUT_PEER, OUTPUT_PEER_MODE, OUTPUT_PEER_CMD,
# OUTPUT_PEER_AVAILABLE.

run_scenario() {
  local label="$1"; shift
  local has_claude="false" has_codex="false"
  local env_claude="false" env_codex="false"
  local override="auto"
  local ensemble_host=""

  while [ $# -gt 0 ]; do
    case "$1" in
      has_claude=*)    has_claude="${1#has_claude=}";    shift ;;
      has_codex=*)     has_codex="${1#has_codex=}";      shift ;;
      env_claude=*)    env_claude="${1#env_claude=}";    shift ;;
      env_codex=*)     env_codex="${1#env_codex=}";      shift ;;
      override=*)      override="${1#override=}";        shift ;;
      ensemble_host=*) ensemble_host="${1#ensemble_host=}"; shift ;;
      *) shift ;;
    esac
  done

  local tmpdir
  tmpdir=$(mktemp -d)
  local shim_dir="$tmpdir/bin"
  local home_dir="$tmpdir/home"
  mkdir -p "$shim_dir" "$home_dir/.ensemble"

  # PATH shims: only include the CLIs we want to be "installed"
  if [ "$has_claude" = "true" ]; then
    cat > "$shim_dir/claude" <<'EOF'
#!/usr/bin/env bash
echo "{}"
EOF
    chmod +x "$shim_dir/claude"
  fi
  if [ "$has_codex" = "true" ]; then
    cat > "$shim_dir/codex" <<'EOF'
#!/usr/bin/env bash
echo "{}"
EOF
    chmod +x "$shim_dir/codex"
  fi

  # ~/.ensemble/config.json with the chosen override
  cat > "$home_dir/.ensemble/config.json" <<EOF
{ "peer_mode_override": "$override" }
EOF

  # Run detect with mocked PATH and HOME
  local env_args=()
  [ "$env_claude" = "true" ] && env_args+=("CLAUDE_CODE_VERSION=test")
  [ "$env_codex" = "true" ]  && env_args+=("CODEX_HOME=$home_dir/.codex")
  [ -n "$ensemble_host" ]    && env_args+=("ENSEMBLE_HOST=$ensemble_host")

  local detect_output
  detect_output=$(env -i PATH="$shim_dir:/usr/bin:/bin" HOME="$home_dir" "${env_args[@]}" "$DETECT" 2>/dev/null)

  # Eval the output to populate our shell with the detected variables
  unset HOST PEER PEER_MODE PEER_CMD PEER_FORMAT PEER_AVAILABLE
  eval "$detect_output"

  OUTPUT_HOST="${HOST:-}"
  OUTPUT_PEER="${PEER:-}"
  OUTPUT_PEER_MODE="${PEER_MODE:-}"
  OUTPUT_PEER_CMD="${PEER_CMD:-}"
  OUTPUT_PEER_AVAILABLE="${PEER_AVAILABLE:-}"

  rm -rf "$tmpdir"
}

# --- Scenario: Claude env present, both CLIs installed → cross-agent ---
run_scenario "claude-env-both-clis" \
  env_claude=true has_claude=true has_codex=true override=auto
assert_eq "claude-code" "$OUTPUT_HOST" "[both-clis] HOST=claude-code"
assert_eq "codex" "$OUTPUT_PEER" "[both-clis] PEER=codex"
assert_eq "cross-agent" "$OUTPUT_PEER_MODE" "[both-clis] PEER_MODE=cross-agent"
assert_eq "codex exec" "$OUTPUT_PEER_CMD" "[both-clis] PEER_CMD=codex exec"
assert_eq "true" "$OUTPUT_PEER_AVAILABLE" "[both-clis] PEER_AVAILABLE=true"

# --- Scenario: Claude env present, only Claude CLI installed → single-agent fallback ---
run_scenario "claude-env-claude-only" \
  env_claude=true has_claude=true has_codex=false override=auto
assert_eq "claude-code" "$OUTPUT_HOST" "[claude-only] HOST=claude-code"
assert_eq "claude-code" "$OUTPUT_PEER" "[claude-only] PEER=claude-code (self-fallback)"
assert_eq "single-agent-fallback" "$OUTPUT_PEER_MODE" "[claude-only] PEER_MODE=single-agent-fallback"
assert_eq "claude -p" "$OUTPUT_PEER_CMD" "[claude-only] PEER_CMD=claude -p"
assert_eq "true" "$OUTPUT_PEER_AVAILABLE" "[claude-only] PEER_AVAILABLE=true"

# --- Scenario: Codex env present, only Codex CLI installed → single-agent fallback ---
run_scenario "codex-env-codex-only" \
  env_codex=true has_claude=false has_codex=true override=auto
assert_eq "codex" "$OUTPUT_HOST" "[codex-only] HOST=codex"
assert_eq "codex" "$OUTPUT_PEER" "[codex-only] PEER=codex (self-fallback)"
assert_eq "single-agent-fallback" "$OUTPUT_PEER_MODE" "[codex-only] PEER_MODE=single-agent-fallback"
assert_eq "codex exec" "$OUTPUT_PEER_CMD" "[codex-only] PEER_CMD=codex exec"

# --- Scenario: peer_mode_override=off → PEER disabled regardless ---
run_scenario "override-off" \
  env_claude=true has_claude=true has_codex=true override=off
assert_eq "off" "$OUTPUT_PEER_MODE" "[override-off] PEER_MODE=off"
assert_eq "false" "$OUTPUT_PEER_AVAILABLE" "[override-off] PEER_AVAILABLE=false"

# --- Scenario: peer_mode_override=cross-agent-only with no other CLI → off + warning ---
run_scenario "cross-agent-only-no-peer-cli" \
  env_claude=true has_claude=true has_codex=false override=cross-agent-only
assert_eq "off" "$OUTPUT_PEER_MODE" "[cross-only-no-peer] PEER_MODE=off"
assert_eq "false" "$OUTPUT_PEER_AVAILABLE" "[cross-only-no-peer] PEER_AVAILABLE=false"

# --- Scenario: peer_mode_override=single-agent-only forces fallback even with both CLIs ---
run_scenario "single-only-with-both" \
  env_claude=true has_claude=true has_codex=true override=single-agent-only
assert_eq "single-agent-fallback" "$OUTPUT_PEER_MODE" "[single-only] PEER_MODE=single-agent-fallback"
assert_eq "claude -p" "$OUTPUT_PEER_CMD" "[single-only] PEER_CMD=claude -p"

# --- Scenario: ENSEMBLE_HOST=codex override ---
run_scenario "ensemble-host-codex" \
  has_claude=true has_codex=true override=auto ensemble_host=codex
assert_eq "codex" "$OUTPUT_HOST" "[ENSEMBLE_HOST=codex] HOST=codex"
assert_eq "claude" "$OUTPUT_PEER" "[ENSEMBLE_HOST=codex] PEER=claude"

# --- Scenario: shell-escape round-trip with eval ---
# Ensure values with spaces (HOST_CMD=claude -p) round-trip correctly.
run_scenario "shell-escape-round-trip" \
  env_claude=true has_claude=true has_codex=true override=auto

# After eval, $PEER_CMD should be a single string "codex exec" and unquoted
# expansion should split it into 2 args.
set -- $OUTPUT_PEER_CMD
assert_eq "2" "$#" "PEER_CMD splits into 2 args under unquoted expansion"
assert_eq "codex" "$1" "PEER_CMD first arg is codex"
assert_eq "exec" "$2" "PEER_CMD second arg is exec"

report
