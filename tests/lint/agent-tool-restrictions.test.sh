#!/usr/bin/env bash
# tests/lint/agent-tool-restrictions.test.sh
#
# EN24 U1. Every bundled agent called itself read-only in prose, and nothing
# held it to that: Claude Code hands a subagent with no `tools:` line every
# tool the session has. A reviewer that edits what it reviews has lost the
# independence that made the review worth running. The restriction now lives
# in frontmatter, which Claude Code enforces, in three groups:
#
#   - pure readers (dimension-reviewer, test-lane-auditor): `tools: Read, Grep, Glob`.
#   - research agents that write an evidence dossier: `disallowedTools: Edit,
#     NotebookEdit, Bash`. A denylist, so web-research keeps its Context7 MCP
#     tools, whose names differ between plugin and standalone installs.
#   - code-simplifier: `disallowedTools: Edit, Write, NotebookEdit`, keeping Bash
#     for `git blame`.
#
# WHAT THIS DOES NOT ENFORCE. Claude Code has no path-scoped `tools` form and
# ignores frontmatter hooks for plugin-installed subagents, so the research
# agents can still Write anywhere and code-simplifier can still run any Bash.
# For those two tools the body sentence asserted below is the control, and the
# plan records the residual (EN24, Decisions). Codex agent TOML has no tools
# field at all. tests/install/codex-toml-agents.test.sh renders these same files
# and owns that check; running it from here would cost six more minutes per suite.
#
# NEGATIVE CONTROLS (run by hand 2026-10-29, each turned the test red):
#   - removed the `tools:` line from dimension-reviewer.md
#   - added Edit to test-lane-auditor.md's `tools:` list
#   - dropped NotebookEdit from repo-research.md's `disallowedTools:`
#   - deleted the `/tmp/ensemble/` sentence from web-research.md
#   - deleted the `git blame` sentence from code-simplifier.md

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="bundled agents restrict their tools in frontmatter"

fm() {  # <file> <field> -> the field's value from the frontmatter, or empty
  awk -v f="$2" 'NR==1 && $0!="---" { exit } NR>1 && /^---$/ { exit }
    NR>1 && index($0, f ":") == 1 { s = $0; sub("^" f ":[ \t]*", "", s); print s; exit }' "$1"
}
has_tool() {  # <comma list> <tool>
  printf '%s\n' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -qx "$2"
}

PURE="dimension-reviewer test-lane-auditor"
RESEARCH="repo-research learnings-research web-research repo-fact-lookup"
WRITE_SENTENCE='Use `Write` only to `/tmp/ensemble/'
BASH_SENTENCE='Use `Bash` only for `git blame`, `git log` and `git show`'

checked=0
for f in "$REPO_ROOT"/skills/*/agents/*.md; do
  rel="${f#$REPO_ROOT/}"; name="$(fm "$f" name)"
  desc="$(fm "$f" description)"
  # Read-only by its own claim: the description says so, or the body forbids edits.
  case "$desc" in
    *Read-only*|*"never interprets, proposes, or edits"*) ;;
    *) grep -qiE 'you do not edit files|you never write|no edits' "$f" || continue ;;
  esac
  checked=$((checked + 1))
  tools="$(fm "$f" tools)"; deny="$(fm "$f" disallowedTools)"

  if [ -n "$tools" ]; then
    bad=""; for t in Edit Write NotebookEdit Bash; do has_tool "$tools" "$t" && bad="$bad $t"; done
    [ -z "$bad" ] && pass "$rel: tools allowlist grants no mutating tool" \
      || fail "$rel: tools allowlist grants no mutating tool" "grants:$bad"
  elif [ -n "$deny" ]; then
    has_tool "$deny" Edit && has_tool "$deny" NotebookEdit \
      && pass "$rel: disallowedTools removes Edit and NotebookEdit" \
      || fail "$rel: disallowedTools removes Edit and NotebookEdit" "got: $deny"
  else
    fail "$rel: declares a tools: or disallowedTools: line" "a read-only agent with neither gets every tool"
    continue
  fi

  case " $PURE " in *" $name "*)
    assert_eq "Read, Grep, Glob" "$tools" "$rel: pure reader carries exactly Read, Grep, Glob" ;;
  esac
  case " $RESEARCH " in *" $name "*)
    has_tool "$deny" Bash && pass "$rel: research agent has no Bash" || fail "$rel: research agent has no Bash" "got: $deny"
    grep -qF "$WRITE_SENTENCE" "$f" && pass "$rel: body limits Write to the dossier directory" \
      || fail "$rel: body limits Write to the dossier directory" "missing: $WRITE_SENTENCE" ;;
  esac
  if [ "$name" = code-simplifier ]; then
    has_tool "$deny" Write && pass "$rel: code-simplifier has no Write" || fail "$rel: code-simplifier has no Write" "got: $deny"
    grep -qF "$BASH_SENTENCE" "$f" && pass "$rel: body limits Bash to git history reads" \
      || fail "$rel: body limits Bash to git history reads" "missing: $BASH_SENTENCE"
  fi
done
[ "$checked" -ge 13 ] && pass "found all $checked read-only agent files" \
  || fail "found the 13 read-only agent files" "only $checked matched"

# Copies of one agent stay byte-identical, so a restriction cannot land in one.
for n in $PURE $RESEARCH code-simplifier; do
  sums=$(for f in "$REPO_ROOT"/skills/*/agents/"$n".md; do cksum < "$f"; done | sort -u | wc -l | tr -d ' ')
  assert_eq 1 "$sums" "every copy of $n is byte-identical"
done

# setup must still install the new field. A copy rendered for an effort key
# keeps the restriction next to the injected effort: line.
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT INT TERM HUP
H="$WORK/h"; mkdir -p "$H/.claude" "$H/.codex" "$H/.ensemble"
echo '{"agent_effort_claude_evidence":"medium","agent_effort_claude_ceiling":"high"}' > "$H/.ensemble/config.json"
( cd "$WORK" && HOME="$H" bash "$REPO_ROOT/setup" --host claude --copy ) >"$WORK/out" 2>&1
assert_exit_code 0 $? "setup --copy with effort keys exits 0"
rr="$H/.claude/agents/repo-research.md"
assert_eq "medium" "$(fm "$rr" effort)" "rendered repo-research carries the injected effort"
assert_eq "Edit, NotebookEdit, Bash" "$(fm "$rr" disallowedTools)" "rendered repo-research keeps its disallowedTools"
assert_eq "Read, Grep, Glob" "$(fm "$H/.claude/agents/dimension-reviewer.md" tools)" "rendered dimension-reviewer keeps its tools"

report
