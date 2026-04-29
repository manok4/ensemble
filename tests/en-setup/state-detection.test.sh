#!/usr/bin/env bash
# State-detection tests — exercise the heuristics from references/setup-state-detection.md
# directly against the sample repos under tests/en-setup/sample-repos/.
#
# Implements the same logic as the SKILL.md, in bash, so we can unit-test the
# detection without invoking a host CLI. If the heuristics in setup-state-detection.md
# change, update this implementation to match — or, better, add a test fixture
# that fails so the change gets caught.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-setup state detection"

# Per references/setup-state-detection.md
detect_state() {
  local repo="$1"
  local has_foundation="false"
  local has_learnings="false"
  local has_source="false"

  [ -f "$repo/docs/foundation.md" ] && has_foundation="true"
  [ -d "$repo/docs/learnings" ] && has_learnings="true"

  # Source-code-present heuristic (subset; full version checks more package files)
  for marker in package.json go.mod Cargo.toml pyproject.toml requirements.txt Gemfile composer.json pom.xml build.gradle; do
    [ -f "$repo/$marker" ] && has_source="true" && break
  done
  if [ "$has_source" = "false" ]; then
    [ -d "$repo/src" ] && [ -n "$(ls -A "$repo/src" 2>/dev/null)" ] && has_source="true"
  fi

  if [ "$has_source" = "false" ] && [ "$has_foundation" = "false" ]; then
    echo "state-1"
    return
  fi

  if [ "$has_foundation" = "true" ] && [ "$has_learnings" = "true" ]; then
    echo "state-3"
    return
  fi

  if [ "$has_source" = "true" ]; then
    echo "state-2"
    return
  fi

  echo "state-1"
}

detect_state2_subvariant() {
  local repo="$1"
  local has_agents="false"; [ -f "$repo/AGENTS.md" ] && has_agents="true"
  local has_claude="false"; [ -f "$repo/CLAUDE.md" ] && has_claude="true"

  if [ "$has_agents" = "false" ] && [ "$has_claude" = "false" ]; then echo "2a"
  elif [ "$has_agents" = "false" ] && [ "$has_claude" = "true" ]; then echo "2b"
  elif [ "$has_agents" = "true" ] && [ "$has_claude" = "false" ]; then echo "2c"
  else echo "2d"
  fi
}

# --- State 1: greenfield ---
state=$(detect_state "$SCRIPT_DIR/sample-repos/state-1-greenfield")
assert_eq "state-1" "$state" "state-1-greenfield → state-1"

# --- State 2 sub-variants ---
state=$(detect_state "$SCRIPT_DIR/sample-repos/state-2a-no-maps")
assert_eq "state-2" "$state" "state-2a-no-maps → state-2"
sub=$(detect_state2_subvariant "$SCRIPT_DIR/sample-repos/state-2a-no-maps")
assert_eq "2a" "$sub" "state-2a sub-variant"

state=$(detect_state "$SCRIPT_DIR/sample-repos/state-2b-claude-only")
assert_eq "state-2" "$state" "state-2b-claude-only → state-2"
sub=$(detect_state2_subvariant "$SCRIPT_DIR/sample-repos/state-2b-claude-only")
assert_eq "2b" "$sub" "state-2b sub-variant"

state=$(detect_state "$SCRIPT_DIR/sample-repos/state-2c-agents-only")
assert_eq "state-2" "$state" "state-2c-agents-only → state-2"
sub=$(detect_state2_subvariant "$SCRIPT_DIR/sample-repos/state-2c-agents-only")
assert_eq "2c" "$sub" "state-2c sub-variant"

state=$(detect_state "$SCRIPT_DIR/sample-repos/state-2d-both-maps")
assert_eq "state-2" "$state" "state-2d-both-maps → state-2"
sub=$(detect_state2_subvariant "$SCRIPT_DIR/sample-repos/state-2d-both-maps")
assert_eq "2d" "$sub" "state-2d sub-variant"

# --- State 3: full + partial both detect as state-3 ---
state=$(detect_state "$SCRIPT_DIR/sample-repos/state-3-fully-set-up")
assert_eq "state-3" "$state" "state-3-fully-set-up → state-3"

state=$(detect_state "$SCRIPT_DIR/sample-repos/state-3-partial")
assert_eq "state-3" "$state" "state-3-partial → state-3 (foundation + learnings dir both present)"

# Diagnostic detection: state-3-partial is missing log.md
if [ ! -f "$SCRIPT_DIR/sample-repos/state-3-partial/docs/learnings/log.md" ]; then
  pass "state-3-partial fixture is missing log.md (as designed)"
else
  fail "state-3-partial should be missing log.md"
fi

# state-3-fully-set-up has all required pieces (per scripts/check-health)
required_paths=(
  "AGENTS.md"
  "CLAUDE.md"
  "docs/foundation.md"
  "docs/architecture.md"
  "docs/learnings/index.md"
  "docs/learnings/log.md"
  "docs/generated/plan-index.md"
  "docs/generated/learning-index.md"
)
for path in "${required_paths[@]}"; do
  if [ -e "$SCRIPT_DIR/sample-repos/state-3-fully-set-up/$path" ]; then
    pass "state-3-fully-set-up has $path"
  else
    fail "state-3-fully-set-up missing $path"
  fi
done

report
