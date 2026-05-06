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

# --- Scenario: recursion guard short-circuit ---
# When ENSEMBLE_PEER_REVIEW=true, detect must skip the work entirely and
# emit PEER_AVAILABLE=false. Tests pass even with no CLIs installed,
# because the guard fires before any CLI lookup.
recursion_tmp=$(mktemp -d)
recursion_out=$(env -i PATH="/usr/bin:/bin" HOME="$recursion_tmp" \
  ENSEMBLE_PEER_REVIEW=true "$DETECT" 2>/dev/null)
unset HOST PEER PEER_MODE PEER_CMD PEER_AVAILABLE
eval "$recursion_out"
assert_eq "false" "${PEER_AVAILABLE:-}" "[recursion-guard] PEER_AVAILABLE=false"
assert_eq "off" "${PEER_MODE:-}" "[recursion-guard] PEER_MODE=off"
if echo "$recursion_out" | grep -q "DETECT_REASON=recursion-guard"; then
  pass "[recursion-guard] emits DETECT_REASON=recursion-guard"
else
  fail "[recursion-guard] should emit DETECT_REASON=recursion-guard" "$recursion_out"
fi
# Cache file should NOT be written when recursion guard fires
if [ ! -f "$recursion_tmp/.ensemble/host-cache.env" ]; then
  pass "[recursion-guard] does not write cache"
else
  fail "[recursion-guard] should not write cache" "cache file exists at $recursion_tmp/.ensemble/host-cache.env"
fi
rm -rf "$recursion_tmp"

# --- Scenario: cache hit on second invocation ---
cache_tmp=$(mktemp -d)
cache_shim="$cache_tmp/bin"
cache_home="$cache_tmp/home"
mkdir -p "$cache_shim" "$cache_home/.ensemble"
cat > "$cache_shim/claude" <<'EOF'
#!/usr/bin/env bash
echo "{}"
EOF
chmod +x "$cache_shim/claude"
cat > "$cache_shim/codex" <<'EOF'
#!/usr/bin/env bash
echo "{}"
EOF
chmod +x "$cache_shim/codex"
cat > "$cache_home/.ensemble/config.json" <<EOF
{ "peer_mode_override": "auto" }
EOF

# First invocation: cache miss → script runs full path
out1=$(env -i PATH="$cache_shim:/usr/bin:/bin" HOME="$cache_home" \
  CLAUDE_CODE_VERSION=test "$DETECT" 2>/dev/null)
if [ -f "$cache_home/.ensemble/host-cache.env" ]; then
  pass "[cache] first invocation writes cache file"
else
  fail "[cache] first invocation should write cache" "no cache file at $cache_home/.ensemble/host-cache.env"
fi

# Tamper with the cache file so we can prove the second invocation reads from it
echo "HOST='cache-marker'" > "$cache_home/.ensemble/host-cache.env"
echo "PEER_AVAILABLE='cache-marker-flag'" >> "$cache_home/.ensemble/host-cache.env"

# Second invocation: cache hit → emits the tampered content (proving it didn't re-run detection)
out2=$(env -i PATH="$cache_shim:/usr/bin:/bin" HOME="$cache_home" \
  CLAUDE_CODE_VERSION=test "$DETECT" 2>/dev/null)
unset HOST PEER_AVAILABLE
eval "$out2"
assert_eq "cache-marker" "${HOST:-}" "[cache] second invocation reads from cache (HOST tampered)"
assert_eq "cache-marker-flag" "${PEER_AVAILABLE:-}" "[cache] second invocation reads from cache (PEER_AVAILABLE tampered)"

# --no-cache flag bypasses cache → re-runs detection
out3=$(env -i PATH="$cache_shim:/usr/bin:/bin" HOME="$cache_home" \
  CLAUDE_CODE_VERSION=test "$DETECT" --no-cache 2>/dev/null)
unset HOST PEER_AVAILABLE
eval "$out3"
assert_eq "claude-code" "${HOST:-}" "[cache] --no-cache bypasses cache and re-runs detection"

# ENSEMBLE_DETECT_NO_CACHE env var also bypasses cache
out4=$(env -i PATH="$cache_shim:/usr/bin:/bin" HOME="$cache_home" \
  CLAUDE_CODE_VERSION=test ENSEMBLE_DETECT_NO_CACHE=true "$DETECT" 2>/dev/null)
unset HOST PEER_AVAILABLE
eval "$out4"
assert_eq "claude-code" "${HOST:-}" "[cache] ENSEMBLE_DETECT_NO_CACHE=true bypasses cache"

rm -rf "$cache_tmp"

# --- Scenario: stale cache (TTL exceeded) is bypassed ---
ttl_tmp=$(mktemp -d)
ttl_home="$ttl_tmp/home"
ttl_shim="$ttl_tmp/bin"
mkdir -p "$ttl_home/.ensemble" "$ttl_shim"
cat > "$ttl_shim/claude" <<'EOF'
#!/usr/bin/env bash
echo "{}"
EOF
chmod +x "$ttl_shim/claude"
cat > "$ttl_shim/codex" <<'EOF'
#!/usr/bin/env bash
echo "{}"
EOF
chmod +x "$ttl_shim/codex"
cat > "$ttl_home/.ensemble/config.json" <<EOF
{ "peer_mode_override": "auto" }
EOF

# Plant a stale cache (mtime in the past) with tampered content
echo "HOST='stale-marker'" > "$ttl_home/.ensemble/host-cache.env"
# Set mtime to 2 hours ago (well beyond default 60-minute TTL)
touch -t "$(date -v-2H +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M.%S)" \
  "$ttl_home/.ensemble/host-cache.env" 2>/dev/null

out5=$(env -i PATH="$ttl_shim:/usr/bin:/bin" HOME="$ttl_home" \
  CLAUDE_CODE_VERSION=test "$DETECT" 2>/dev/null)
unset HOST
eval "$out5"
assert_eq "claude-code" "${HOST:-}" "[cache-ttl] stale cache (2h old) is bypassed; detection re-runs"

rm -rf "$ttl_tmp"

report
