#!/usr/bin/env bash
# tests/install/claude-effort-agents.test.sh
#
# D104. Claude Code reads a subagent's effort from the installed agent file's
# `effort:` line and nowhere else; a file without one inherits the session
# level. An operator's agent_effort_claude_* key can therefore only bind at
# install time: setup publishes the agent as a COPY with the line injected
# when a key applies, and links the checkout's file as before when none does.
# Every property below is one a wrong render would violate silently, because
# Claude Code does not report which effort a subagent ran at.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="setup renders Claude agent effort at install time"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
run_setup() {  # <home> [flags...]
  local home="$1"; shift
  mkdir -p "$home/.claude" "$home/.codex" "$home/.ensemble"
  ( cd "$WORK" && HOME="$home" bash "$REPO_ROOT/setup" --host claude "$@" ) >"$WORK/out" 2>&1
}
effort_of() { awk 'NR==1&&$0!="---"{exit} NR>1&&/^---$/{exit} /^effort:/{sub(/^effort:[ \t]*/,""); print; exit}' "$1"; }
effort_lines() { awk 'NR==1&&$0!="---"{exit} NR>1&&/^---$/{exit} /^effort:/{n++} END{print n+0}' "$1"; }

# --- 1. no effort key: every agent is a symlink, exactly as before ---
H1="$WORK/h1"; echo '{}' > "$WORK/h1.json"; mkdir -p "$H1/.ensemble"; cp "$WORK/h1.json" "$H1/.ensemble/config.json"
run_setup "$H1" --symlink; rc=$?
assert_exit_code 0 "$rc" "setup with no effort key exits 0"
links=$(find "$H1/.claude/agents" -type l | wc -l | tr -d ' '); files=$(find "$H1/.claude/agents" -type f | wc -l | tr -d ' ')
[ "$files" -eq 0 ] && [ "$links" -gt 0 ] && pass "no effort key: all $links agents are symlinks, no copies" || fail "no effort key: all agents are symlinks" "links=$links files=$files"

# --- 2. a tier effort key: evidence agents become copies with the line, others stay links ---
H2="$WORK/h2"; mkdir -p "$H2/.ensemble"
echo '{"agent_effort_claude_evidence":"medium"}' > "$H2/.ensemble/config.json"
run_setup "$H2" --symlink; rc=$?
assert_exit_code 0 "$rc" "setup with an evidence effort key exits 0"
[ -f "$H2/.claude/agents/repo-research.md" ] && [ ! -L "$H2/.claude/agents/repo-research.md" ] && pass "repo-research (evidence) is published as a copy" || fail "repo-research (evidence) is published as a copy"
assert_eq "medium" "$(effort_of "$H2/.claude/agents/repo-research.md")" "the copy carries effort: medium"
assert_eq "1" "$(effort_lines "$H2/.claude/agents/repo-research.md")" "exactly one effort line"
[ -L "$H2/.claude/agents/repo-fact-lookup.md" ] && pass "repo-fact-lookup (retrieval, no key) stays a symlink" || fail "repo-fact-lookup (retrieval, no key) stays a symlink"
[ -L "$H2/.claude/agents/dimension-reviewer.md" ] && pass "dimension-reviewer (ceiling, no key) stays a symlink" || fail "dimension-reviewer (ceiling, no key) stays a symlink"
# body identical to the source apart from the injected line
src=$(ls "$REPO_ROOT"/skills/*/agents/repo-research.md | head -1)
diff <(grep -v '^effort:' "$H2/.claude/agents/repo-research.md") "$src" >/dev/null && pass "the copy differs from its source only by the effort line" || fail "the copy differs from its source only by the effort line"
grep -q "rendered agents/repo-research.md as a copy with effort: medium" "$WORK/out" && pass "the log names the rendered effort" || fail "the log names the rendered effort" "$(grep repo-research "$WORK/out" | head -2)"
grep -q "$H2/.claude/agents/repo-research.md" "$H2/.ensemble/install-manifest-claude.txt" && pass "the copy is recorded in the manifest" || fail "the copy is recorded in the manifest"

# --- 3. an existing effort line is replaced, not duplicated ---
H3="$WORK/h3"; mkdir -p "$H3/.ensemble"
echo '{"agent_effort_claude_ceiling":"xhigh"}' > "$H3/.ensemble/config.json"
run_setup "$H3" --symlink
assert_eq "xhigh" "$(effort_of "$H3/.claude/agents/dimension-reviewer.md")" "dimension-reviewer's shipped effort: high is replaced by the ceiling key"
assert_eq "1" "$(effort_lines "$H3/.claude/agents/dimension-reviewer.md")" "still exactly one effort line"
[ -L "$H3/.claude/agents/repo-research.md" ] && pass "evidence agents stay symlinks when only the ceiling key is set" || fail "evidence agents stay symlinks when only the ceiling key is set"

# --- 4. removing the key and re-running returns the agent to a symlink (manifest sweep) ---
echo '{}' > "$H2/.ensemble/config.json"
run_setup "$H2" --symlink
[ -L "$H2/.claude/agents/repo-research.md" ] && pass "after the key is removed, a re-run restores the symlink" || fail "after the key is removed, a re-run restores the symlink"

# --- 5. repo-local config never binds a machine-wide file ---
H5="$WORK/h5"; mkdir -p "$H5/.ensemble" "$WORK/repo5/.ensemble"
echo '{}' > "$H5/.ensemble/config.json"; printf 'agent_effort_claude_evidence: low\n' > "$WORK/repo5/.ensemble/config.local.yaml"
( cd "$WORK/repo5" && HOME="$H5" bash "$REPO_ROOT/setup" --host claude --symlink ) >"$WORK/out5" 2>&1
[ -L "$H5/.claude/agents/repo-research.md" ] && pass "a repo-local effort key does not render the machine-wide agent" || fail "a repo-local effort key does not render the machine-wide agent"

report
