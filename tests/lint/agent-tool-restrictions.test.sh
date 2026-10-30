#!/usr/bin/env bash
# tests/lint/agent-tool-restrictions.test.sh
#
# EN24 U1. Every bundled agent called itself read-only in prose, and nothing
# held it to that: Claude Code hands a subagent with no `tools:` line every
# tool the session has. A reviewer that edits what it reviews has lost the
# independence that made the review worth running. The restriction now lives
# in frontmatter, which Claude Code enforces, in three groups:
#
#   - pure readers (dimension-reviewer, test-lane-auditor): `tools: Read, Grep,
#     Glob`. No shell at all.
#   - research agents that search the repo and write an evidence dossier
#     (repo-research, learnings-research, repo-fact-lookup): `tools: Read,
#     Grep, Glob, Write`.
#   - code-simplifier: `tools: Read, Bash`, because it runs `git blame`.
#   - web-research: `disallowedTools: Edit, NotebookEdit, Bash`. A denylist, so
#     it keeps its Context7 MCP tools, whose names differ between plugin and
#     standalone installs.
#
# HOW SEARCH SURVIVES. On macOS, Linux and WSL, Claude Code leaves Grep and
# Glob out of the default tool set and searches through Bash. They come back
# for a subagent "that lists `Glob` or `Grep` in its `tools` field and leaves
# out `Bash`" (code.claude.com/docs/en/tools-reference, read 2026-10-30). So an
# allowlist keeps search either through Bash or by naming Grep or Glob without
# Bash, and a denylist that removes Bash, with no allowlist, leaves none: that
# was the research agents' first cut. Asserted below for every allowlist.
#
# WHAT THIS DOES NOT ENFORCE. Claude Code has no path- or command-scoped
# `tools` form and ignores frontmatter hooks for plugin-installed subagents, so
# the research agents can still Write anywhere and code-simplifier's Bash can
# still write. For those the body sentence asserted below is the control.
# web-research's denylist also leaves it any MCP tool the session has. Codex agent TOML has no tools
# field at all. tests/install/codex-toml-agents.test.sh renders these same files
# and owns that check; running it from here would cost six more minutes per suite.
#
# NEGATIVE CONTROLS (run by hand 2026-10-29, each turned the test red):
#   - removed the `tools:` line from dimension-reviewer.md
#   - added Edit to test-lane-auditor.md's `tools:` list
#   - dropped NotebookEdit from web-research.md's `disallowedTools:`
#   - set repo-research.md to `tools: Read, Write` (no way to search)
#   - set dimension-reviewer.md to `tools: Read, Grep, Bash` (Grep not restored)
#   - deleted the `/tmp/ensemble/` sentence from web-research.md
#   - deleted the `Bash` sentence from code-simplifier.md (2026-10-30)
#   - put "so you run no commands" back in repo-research.md (2026-10-30)

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
RESEARCH="repo-research learnings-research repo-fact-lookup"
WRITE_SENTENCE='`Write` only to `/tmp/ensemble/'
BASH_SENTENCE='Use `Bash` only to read'
SHELL_SENTENCE='Where your host gives you a shell instead, as Codex does, use it only to read'

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
    bad=""; for t in Edit NotebookEdit; do has_tool "$tools" "$t" && bad="$bad $t"; done
    case "$tools" in *mcp__*) bad="$bad mcp" ;; esac
    [ -z "$bad" ] && pass "$rel: tools allowlist grants no edit or MCP tool" \
      || fail "$rel: tools allowlist grants no edit or MCP tool" "grants:$bad"
    if has_tool "$tools" Bash; then
      pass "$rel: the allowlist keeps a way to search (Bash)"
      grep -qiF "$BASH_SENTENCE" "$f" && pass "$rel: body limits Bash to reading" \
        || fail "$rel: body limits Bash to reading" "missing: $BASH_SENTENCE"
    elif has_tool "$tools" Grep || has_tool "$tools" Glob; then
      pass "$rel: the allowlist keeps a way to search (Grep/Glob, restored without Bash)"
      # Codex renders this body as the agent's instructions and has no Read,
      # Grep or Glob: it reads through its shell. A body that forbids every
      # command left the Codex reviewer reading nothing (live run, 2026-10-30).
      tr '\n' ' ' < "$f" | grep -qF "$SHELL_SENTENCE" && pass "$rel: body lets a shell-only host read" \
        || fail "$rel: body lets a shell-only host read" "missing: $SHELL_SENTENCE"
      grep -qiE 'run no commands' "$f" && fail "$rel: body does not forbid every command" "a Codex agent then cannot read its inputs" \
        || pass "$rel: body does not forbid every command"
    else
      fail "$rel: the allowlist keeps a way to search" "got: $tools; name Grep and Glob, or Bash"
    fi
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
    assert_eq "Read, Grep, Glob, Write" "$tools" "$rel: research agent carries exactly Read, Grep, Glob, Write" ;;
  esac
  [ "$name" = code-simplifier ] && assert_eq "Read, Bash" "$tools" "$rel: code-simplifier carries exactly Read, Bash"
  case " $RESEARCH web-research " in *" $name "*)
    grep -qF "$WRITE_SENTENCE" "$f" && pass "$rel: body limits Write to the dossier directory" \
      || fail "$rel: body limits Write to the dossier directory" "missing: $WRITE_SENTENCE" ;;
  esac
done
[ "$checked" -ge 13 ] && pass "found all $checked read-only agent files" \
  || fail "found the 13 read-only agent files" "only $checked matched"

# Copies of one agent stay byte-identical, so a restriction cannot land in one.
for n in $PURE $RESEARCH code-simplifier web-research; do
  sums=$(for f in "$REPO_ROOT"/skills/*/agents/"$n".md; do hash_file "$f"; done | sort -u | wc -l | tr -d ' ')
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
assert_eq "Read, Grep, Glob, Write" "$(fm "$rr" tools)" "rendered repo-research keeps its tools"
assert_eq "Read, Grep, Glob" "$(fm "$H/.claude/agents/dimension-reviewer.md" tools)" "rendered dimension-reviewer keeps its tools"

report
