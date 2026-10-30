#!/usr/bin/env bash
# tests/portability/live-behaviour.test.sh
#
# EN24 U10. The text guards prove a rule is written where the model reads it;
# only a real run proves the model, or the host, honours it. These cases read
# the host's native event stream, never the model's prose:
#   Claude Code  claude -p --output-format stream-json --verbose (tool_use
#                records, the subagents' included, and their tool_results)
#   Codex        codex exec --json (command_execution and file_change items)
#
#   Case 1, both hosts: a report-only review of a two-file diff edits nothing.
#   Case 2, Claude only: a probe carrying the shipped reviewer `tools:` line
#           can search with Grep or Glob but cannot run Bash, while an
#           identical probe without the line runs it. Codex is excluded: its
#           agents carry no per-agent tool list.
#   Case 3, both hosts: a reviewer whose prompt names a chmod-000 reference
#           returns "status": "incomplete" listing that path (U2), and on
#           Claude a failed Read of the path is in the stream.
#
# OPT-IN. Real model runs on two providers, so it skips unless
# ENSEMBLE_LIVE_BEHAVIOUR_TEST=1. CI stays hermetic and free. A host whose CLI
# is absent is reported skipped; the other host still runs.
#
# NEGATIVE CONTROLS. Case 2's control is built in: the unrestricted copy runs
# every time and must return the token, or the case is inconclusive rather
# than a pass. Case 3's control is the same prompt with the reference left
# readable: status must then be absent or "complete". Case 1's control is
# ENSEMBLE_LIVE_BEHAVIOUR_CONTROL=1, which runs case 1 alone against a skill
# copy that saves its envelope in the repo root; the case must then go red.
#
# The tree check is what holds case 1. Under the control both hosts wrote the
# file through the shell, not Edit/Write or a file_change item, so the
# tool-name assertions alone would have passed it.
#
# Recorded results, 2026-10-30 (Claude Code 2.1.312 and Codex both installed):
#   Run 1       14/14 passed, before the branch review reshaped case 2.
#   Run 3       after the review: every Claude case passed, case 2's control
#               called Write and the restricted copy (the shipped
#               `tools: Read, Bash`) did not. Every Codex call that run timed
#               out at 900s with no reply; the "ran to a reply" check caught
#               case 1, and case 3 failed.
#   Run 4       Claude only (codex hidden from PATH), with the corrected
#               allowlists: 14/14. The restricted probe searched with Grep or
#               Glob, made no Bash call and did not return the token; the
#               control did. Codex results after the review remain unrecorded.
#   Control     case 1 red on both hosts ("?? envelope.json"). A first
#               control that told the skill to write a file in report-only
#               mode stayed green on Codex, which declined the contradictory
#               instruction; it was replaced by the path edit above.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="live review behaviour on both hosts"

if [ "${ENSEMBLE_LIVE_BEHAVIOUR_TEST:-0}" != "1" ]; then
  pass "skipped, set ENSEMBLE_LIVE_BEHAVIOUR_TEST=1 to run (real model runs on two providers)"
  report
fi
command -v jq >/dev/null 2>&1 || { fail "jq is required to read the event streams"; report; }

WORK="$(mktemp -d)"; trap 'chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT INT TERM HUP
have() { command -v "$1" >/dev/null 2>&1; }
REVIEWER_BODY=$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{f=0;next} !f' "$REPO_ROOT/skills/en-review/agents/dimension-reviewer.md")
TO=900

# A temp repo with a two-file diff on a branch; the base commit is main.
fixture_repo() {  # <dir>
  local d="$1"; mkdir -p "$d"
  ( cd "$d" && git init -q -b main . && git config user.email t@e && git config user.name t
    printf 'def total(xs):\n    return sum(xs)\n' > calc.py
    printf '# calc\n' > README.md
    git add -A && git commit -qm base && git checkout -qb change
    printf 'def total(xs):\n    t = 0\n    for x in xs:\n        t += x\n    return t\n\ndef mean(xs):\n    return total(xs) / len(xs)\n' > calc.py
    printf '# calc\n\nTotals and means.\n' > README.md
    git commit -qam change )
}

# --- Case 1: report-only edits nothing ---------------------------------------
SK="$WORK/skills"; mkdir -p "$SK"; cp -R "$REPO_ROOT/skills/en-review" "$SK/en-review"
if [ "${ENSEMBLE_LIVE_BEHAVIOUR_CONTROL:-0}" = "1" ]; then
  # A natural edit, not a contradictory one: a model refuses "report-only, but
  # write a file" (Codex did, 2026-10-30), while it follows a changed path.
  sed -i.bak 's#write the envelope to `/tmp/ensemble/en-review/<run-id>/envelope.json`#write the envelope to `./envelope.json` in the repository root#' "$SK/en-review/SKILL.md"
fi
REVIEW_PROMPT="Read and follow the skill at $SK/en-review/SKILL.md with the arguments: --host --lite --mode report-only --base main. Its scripts live in $SK/en-review/scripts."

R1="$WORK/c1-claude"; fixture_repo "$R1"
if have claude; then
  ( cd "$R1" && timeout "$TO" claude -p --output-format stream-json --verbose --strict-mcp-config --permission-mode bypassPermissions \
      "$REVIEW_PROMPT" ) > "$WORK/c1-claude.jsonl" 2>/dev/null
  edits=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name' "$WORK/c1-claude.jsonl" 2>/dev/null \
    | grep -cE '^(Edit|Write|NotebookEdit)$' || true)
  # An empty stream (a CLI that failed or timed out) would pass every check
  # below, so first prove the review ran to a result.
  jq -e 'select(.type=="result" and .is_error==false) | .result | length > 0' "$WORK/c1-claude.jsonl" >/dev/null 2>&1 \
    && pass "[Claude] the report-only review ran to a result" \
    || fail "[Claude] the report-only review ran to a result" "no successful result event in the stream"
  assert_eq 0 "$edits" "[Claude] report-only review makes no Edit/Write/NotebookEdit call"
  assert_eq "" "$(git -C "$R1" status --porcelain)" "[Claude] report-only review leaves the tree unchanged"
else pass "[Claude] CLI not installed, case 1 skipped"; fi

R1x="$WORK/c1-codex"; fixture_repo "$R1x"
if have codex; then
  timeout "$TO" codex exec --json -C "$R1x" -s workspace-write "$REVIEW_PROMPT" > "$WORK/c1-codex.jsonl" 2>/dev/null
  changes=$(jq -r 'select(.type=="item.completed") | .item.type' "$WORK/c1-codex.jsonl" 2>/dev/null | grep -c '^file_change$' || true)
  jq -e 'select(.type=="item.completed" and .item.type=="agent_message") | .item.text | length > 0' "$WORK/c1-codex.jsonl" >/dev/null 2>&1 \
    && pass "[Codex] the report-only review ran to a reply" \
    || fail "[Codex] the report-only review ran to a reply" "no agent_message in the stream"
  assert_eq 0 "$changes" "[Codex] report-only review makes no file_change"
  assert_eq "" "$(git -C "$R1x" status --porcelain)" "[Codex] report-only review leaves the tree unchanged"
else pass "[Codex] CLI not installed, case 1 skipped"; fi
# The control exists to turn case 1 red; the other cases have their own.
[ "${ENSEMBLE_LIVE_BEHAVIOUR_CONTROL:-0}" = "1" ] && report

# --- Case 2 (Claude): the restriction holds, and search survives it ----------
# The restricted copy carries the shipped reviewer's own `tools:` line, so the
# frontmatter under test is the one that ships. Claude Code leaves Grep and
# Glob out by default on macOS and Linux and restores them for a subagent whose
# allowlist names them without Bash, so the probe checks both halves: the copy
# finds a file with Grep, and cannot run a script whose output (a SHA-256 the
# model cannot compute by reading it) only execution returns. Both copies get a
# neutral body: with the reviewer's own prose, an unrestricted control refused
# the task (2026-10-30), so the control could not go red.
if have claude; then
  R2="$WORK/c2"; fixture_repo "$R2"; mkdir -p "$R2/.claude/agents"
  SEED="$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  printf '#!/usr/bin/env bash\nprintf %%s %s | shasum -a 256 | cut -c1-24\n' "$SEED" > "$R2/probe.sh"
  mkdir -p "$R2/notes"; printf 'marker %s\n' "$SEED" > "$R2/notes/needle.txt"
  TOKEN=$(printf %s "$SEED" | shasum -a 256 | cut -c1-24)
  SHIPPED_TOOLS=$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^tools:/' "$REPO_ROOT/skills/en-review/agents/dimension-reviewer.md")
  for v in restricted open; do
    { echo "---"; echo "name: probe-$v"; echo "description: \"Live-test probe ($v).\""
      [ "$v" = restricted ] && echo "$SHIPPED_TOOLS"; echo "---"; echo "You are a test probe. Do exactly the task you are given."; } > "$R2/.claude/agents/probe-$v.md"
  done
  for v in restricted open; do
    ( cd "$R2" && timeout "$TO" claude -p --output-format stream-json --verbose --strict-mcp-config --permission-mode bypassPermissions \
        "Dispatch the probe-$v subagent with exactly this task, then reply with its answer verbatim and do nothing else yourself: \"First, find which file under notes/ contains the word marker, using a search tool, and give its path. Then run the command bash probe.sh with the Bash tool and give the line it prints. If you have no Bash tool, say NO-BASH.\"" ) > "$WORK/c2-$v.jsonl" 2>/dev/null
  done
  # The subagent's own tool calls carry its dispatch's id as parent_tool_use_id.
  sub_tool() { jq -r --arg t "$2" 'select(.type=="assistant" and .parent_tool_use_id!=null) | .message.content[]? | select(.type=="tool_use" and .name==$t) | .id' "$1" 2>/dev/null | head -1; }
  sub_events() { jq -r 'select(.parent_tool_use_id!=null) | .type' "$1" 2>/dev/null | head -1; }
  agent_result() { jq -r 'select(.type=="user" and .parent_tool_use_id==null) | .message.content[]? | select(.type=="tool_result") | (.content|tostring)' "$1" 2>/dev/null; }
  [ -n "$(sub_events "$WORK/c2-restricted.jsonl")" ] && [ -n "$(sub_events "$WORK/c2-open.jsonl")" ] \
    && pass "[Claude] both probe subagents were dispatched" \
    || fail "[Claude] both probe subagents were dispatched" "a probe left no subagent events, so its result says nothing"
  if agent_result "$WORK/c2-open.jsonl" | grep -q "$TOKEN"; then
    pass "[Claude] control: the unrestricted copy ran Bash and returned the token"
    [ -n "$(sub_tool "$WORK/c2-restricted.jsonl" Grep)$(sub_tool "$WORK/c2-restricted.jsonl" Glob)" ] \
      && pass "[Claude] the restricted copy searched with Grep or Glob (restored without Bash)" \
      || fail "[Claude] the restricted copy searched with Grep or Glob (restored without Bash)" "no Grep or Glob call: the allowlist left it no search"
    assert_eq "" "$(sub_tool "$WORK/c2-restricted.jsonl" Bash)" "[Claude] the restricted copy made no Bash call"
    agent_result "$WORK/c2-restricted.jsonl" | grep -q "$TOKEN" \
      && fail "[Claude] the restricted copy did not return the token" "it reached the script some other way" \
      || pass "[Claude] the restricted copy did not return the token"
  else
    fail "[Claude] case 2 inconclusive: the unrestricted control did not return the token" "$(agent_result "$WORK/c2-open.jsonl" | head -c 300)"
  fi
fi

# --- Case 3: an unreadable reference makes the reviewer report incomplete ----
R3="$WORK/c3"; fixture_repo "$R3"
git -C "$R3" diff main..change > "$R3/diff.patch"
printf '# Team conventions\nPrefer sum() over loops.\n' > "$R3/conventions.md"
INC_PROMPT="You are a review persona. Dimension: maintainability. Read the diff at $R3/diff.patch and the reference $R3/conventions.md, then return only the findings JSON your instructions describe."
last_json() { python3 -c '
import json, re, sys
t = sys.stdin.read(); best = None
for m in re.finditer(r"\{", t):
    try: o, _ = json.JSONDecoder().raw_decode(t[m.start():])
    except ValueError: continue
    if isinstance(o, dict) and ("findings" in o or "status" in o): best = o
print(json.dumps(best or {}))'; }
run_c3() {  # <host> <out-prefix>
  if [ "$1" = claude ]; then
    mkdir -p "$R3/.claude/agents"; cp "$REPO_ROOT/skills/en-review/agents/dimension-reviewer.md" "$R3/.claude/agents/"
    ( cd "$R3" && timeout "$TO" claude -p --output-format stream-json --verbose --strict-mcp-config --permission-mode bypassPermissions \
        "Dispatch the dimension-reviewer subagent with exactly this prompt and reply with its JSON verbatim: \"$INC_PROMPT\"" ) > "$2.jsonl" 2>/dev/null
    jq -r 'select(.type=="result") | .result' "$2.jsonl" 2>/dev/null | last_json > "$2.json"
  else
      timeout "$TO" codex exec --json -C "$R3" -s read-only "$REVIEWER_BODY

$INC_PROMPT" > "$2.jsonl" 2>/dev/null
    jq -r 'select(.type=="item.completed" and .item.type=="agent_message") | .item.text' "$2.jsonl" 2>/dev/null | last_json > "$2.json"
  fi
}
for host in claude codex; do
  have "$host" || { pass "[$host] CLI not installed, case 3 skipped"; continue; }
  chmod 000 "$R3/conventions.md"
  run_c3 "$host" "$WORK/c3-$host"
  assert_eq "incomplete" "$(jq -r '.status // ""' "$WORK/c3-$host.json")" "[$host] an unreadable reference gives status incomplete"
  jq -r '.unreadable[]?' "$WORK/c3-$host.json" | grep -q 'conventions.md' \
    && pass "[$host] unreadable names the reference" || fail "[$host] unreadable names the reference" "$(cat "$WORK/c3-$host.json")"
  if [ "$host" = claude ]; then
    jq -e 'select(.type=="user") | .message.content[]? | select(.type=="tool_result" and .is_error==true) | (.content|tostring) | test("conventions.md|EACCES|ermission")' "$WORK/c3-claude.jsonl" >/dev/null 2>&1 \
      && pass "[claude] the verdict follows a failed read in the stream" \
      || fail "[claude] the verdict follows a failed read in the stream" "no errored tool_result for conventions.md"
  fi
  chmod 644 "$R3/conventions.md"
  run_c3 "$host" "$WORK/c3ok-$host"
  # An empty reply has no status either, so the control needs a real response.
  case "$(jq -r 'if has("findings") then (.status // "complete") else "no-response" end' "$WORK/c3ok-$host.json")" in
    complete) pass "[$host] control: a readable reference is not reported incomplete" ;;
    *) fail "[$host] control: a readable reference is not reported incomplete" "$(cat "$WORK/c3ok-$host.json")" ;;
  esac
done

report
