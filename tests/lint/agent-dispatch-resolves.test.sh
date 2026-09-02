#!/usr/bin/env bash
# tests/lint/agent-dispatch-resolves.test.sh
#
# A skill that spawns an agent by name needs that agent to exist wherever the
# skill installs. EN13 deleted seven reviewer agent definitions and absorbed
# their scopes into the peer briefs, but five skills kept naming them as
# subagent_type. The dispatch resolved only on machines whose install predated
# the deletion; a fresh install from main would have failed every one.
#
# It survived a full release because nothing checked, and it was found by
# reconciling foundation's agent catalog against the filesystem — a
# documentation audit, not a test. See TD9.
#
# WHAT COUNTS AS A DISPATCH. Two forms, because skills use both:
#   - `subagent_type: "X"` in a dispatch recipe.
#   - prose in SKILL.md: "dispatch the `X` agent". This is how en-brainstorm,
#     en-debug, en-foundation and en-sweep actually dispatch, and the original
#     guard was blind to it.
#
# WHAT DOES NOT COUNT. `references/research-dispatch.md` is library text carried
# byte-identically by twelve skills. Its code block illustrates *parallel-call
# syntax* using two agent names; the file's own matrix is what states which
# skill dispatches which agent, and for some carriers that matrix reads "never".
# Reading carriage requirements out of a shared illustration made a carrier look
# like a dispatcher of every agent the illustration happened to name — which is
# how en-brainstorm's two never-dispatched scouts were certified as live.
# `references/agent-dispatch.md` had the same problem and was fixed at the
# source: its example now uses the `<name>` placeholder it already used
# elsewhere, so no grep can mistake it for a dispatch.
#
# KNOWN GAP. The reverse direction — a carried agent that nothing reaches — is
# NOT checked here. It is systemic (roughly fifteen skill/agent pairs today) and
# belongs to the per-skill refinement pass, not to a guard that would go red on
# main the day it landed.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="agent dispatch resolves"

SHARED_ILLUSTRATION="research-dispatch.md"

# Names dispatched by a skill's own flow: subagent_type recipes outside the
# shared illustration, plus SKILL.md prose dispatches.
dispatched_by() {  # $1 = skill dir
  {
    grep -rhoE 'subagent_type: "[a-z][a-z-]*"' "$1" \
         --exclude="$SHARED_ILLUSTRATION" 2>/dev/null \
      | sed 's/.*"\(.*\)"/\1/'
    grep -hoE '[Dd]ispatch(es|ing)? (the )?`[a-z][a-z-]+`' "$1/SKILL.md" 2>/dev/null \
      | sed 's/.*`\(.*\)`/\1/'
  } | sort -u
}

# --- 1. every name dispatched anywhere resolves to a definition somewhere ---
unresolved=""
count=0
for skill in "$REPO_ROOT"/skills/*/; do
  for a in $(dispatched_by "$skill"); do
    count=$((count + 1))
    ls "$REPO_ROOT"/skills/*/agents/"$a".md >/dev/null 2>&1 || unresolved="$unresolved $a"
  done
done

[ "$count" -ge 3 ] \
  && pass "found agent dispatches to check ($count sites)" \
  || fail "found agent dispatches to check" "only $count — the scan is probably broken"

if [ -z "$unresolved" ]; then
  pass "every dispatched agent has a definition in this repo"
else
  fail "every dispatched agent has a definition in this repo" \
       "undefined:$(echo $unresolved | tr ' ' '\n' | sort -u | tr '\n' ' ')"
fi

# --- 2. a skill that dispatches an agent must CARRY it, since a skill installs
#        alone and cannot reach another skill's directory ---
missing=""
for skill in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$skill")
  for a in $(dispatched_by "$skill"); do
    [ -f "$skill/agents/$a.md" ] || missing="$missing $name->$a"
  done
done
[ -z "$missing" ] && pass "every skill carries the agents it dispatches" \
                  || fail "every skill carries the agents it dispatches" "$missing"

# --- 3. the shared illustration must stay an illustration ---
if grep -q 'subagent_type: "<name>"' "$REPO_ROOT/skills/en-brainstorm/references/agent-dispatch.md" 2>/dev/null; then
  pass "agent-dispatch.md teaches the mechanism with a placeholder, not a live agent name"
else
  fail "agent-dispatch.md must use the <name> placeholder" \
       "a real agent name there reads as a dispatch to every grep that looks"
fi

# --- 4. every carried agent is actually dispatched by its skill ---
# This asked whether the agent appeared in the requires: manifest. That question
# died with the manifest, and the better one was always available: an agent a
# skill ships but never dispatches is payload nobody invokes.
undispatched=""
reached=$( cd "$REPO_ROOT" && python3 tests/lib/skill-payload.py derive 2>/dev/null )
for skill in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$skill")
  for f in "$skill"agents/*.md; do
    [ -f "$f" ] || continue
    a=$(basename "$f" .md)
    printf '%s\n' "$reached" | grep -qxF "$name	agents/$a.md" \
      || undispatched="$undispatched $name->$a"
  done
done
[ -z "$undispatched" ] && pass "every carried agent is dispatched by its own skill" \
                       || fail "every carried agent is dispatched by its own skill" "$undispatched"

# --- 5. the retired seven must not come back by name ---
if grep -rqE 'subagent_type: "(correctness|testing|maintainability|standards|security|performance|migrations)-reviewer"' "$REPO_ROOT/skills" 2>/dev/null; then
  fail "no skill dispatches the retired per-dimension reviewers"
else
  pass "no skill dispatches the retired per-dimension reviewers"
fi

# --- the three rules survive compression -------------------------------------
# agent-dispatch.md went from 41 lines to 15 on 2026-09-02. Only its placeholder
# was asserted, so the compression could have dropped a rule and stayed green.
# Prose that was just shortened is exactly what drifts next, so each rule is now
# anchored on its own.
AD="$REPO_ROOT/skills/en-brainstorm/references/agent-dispatch.md"

rule() { grep -qF -- "$1" "$AD" && pass "$2" || fail "$2" "not in agent-dispatch.md"; }

rule "Dispatch by name"          "the normal path is a named dispatch"
rule "When the name does not resolve" \
                                 "the fallback names the condition that triggers it"
rule "general-purpose agent with that body as its prompt" \
                                 "the fallback says how to dispatch from the file"

# The ordering rule is the one worth losing sleep over: without it a skill could
# fall back every time, and a registry that stopped publishing would look fine.
rule "Only after the named dispatch fails" "the fallback is second, never first"
# Anchored on a fragment that sits on ONE line: grep is line-based, and the
# phrase this originally used spans a wrap in the source file.
rule "a broken registry publish behind a path" "the reason for that ordering is recorded"

# Every carrier stays byte-identical — the compression touched nine files.
# hash_file from assert.sh, not `md5 -q` directly: that spelling is macOS-only,
# and the harness forbids it for the same reason CI caught a BSD-vs-GNU grep
# difference in #63 — a suite that works on one platform proves nothing on the other.
distinct=$(for f in "$REPO_ROOT"/skills/*/references/agent-dispatch.md; do hash_file "$f"; done | sort -u | wc -l | tr -d " ")
assert_eq "1" "$distinct" "every agent-dispatch.md carrier is byte-identical"

# A carrier that ships the dispatch doc but has no agents to dispatch is payload
# nothing reaches — the defect this campaign found in en-foundation and en-learn.
orphan=""
for d in "$REPO_ROOT"/skills/*/references/agent-dispatch.md; do
  skill=$(basename "$(dirname "$(dirname "$d")")")
  ls "$REPO_ROOT/skills/$skill"/agents/*.md >/dev/null 2>&1 || orphan="$orphan $skill"
done
[ -z "$orphan" ] \
  && pass "every carrier of the dispatch doc actually carries agents" \
  || fail "every carrier of the dispatch doc actually carries agents" "$orphan"

# --- the tier policy is stated, and the agents obey it -----------------------
# Every agent already declared a tier; nothing said why, so a new agent had no
# rule to follow and the assignments were unauditable.
rule "Which model a bundled agent runs on" "the dispatch doc states a tier policy"
# Single-line fragments only. grep is line-based and this file wraps, which has
# now cost two clauses in this suite alone.
rule "Three layers, the same separation"   "the tier policy separates policy from binding"
rule "volatile CLI"                        "the reason tiers are not model IDs is recorded"

# The host scoping. `model:` frontmatter is Claude Code's loader convention, and
# ./setup installs the SAME agent files into a Codex host, where the field names
# a model Codex cannot select. A policy that does not say which host it binds on
# reads as universal and is wrong half the time.
rule "only Claude Code"                    "the tier binding names the host it applies to"
rule "take the default model and select nothing" \
                                           "Codex takes its default, as stated policy"
rule "a second mapping to maintain"        "the reason for not mapping on Codex is recorded"

# The table and the frontmatter must agree. This is the drift that matters: a
# tier row is documentation, a `model:` line is what actually binds, and nothing
# connected them until dimension-reviewer moved rows and its file did not.
tier_row() {  # $1=tier -> the agent names listed in that row
  # awk on the field, not sed on the line: `.*| *` is greedy and consumed through
  # the row's trailing pipe, so this returned EMPTY and the loop below never ran.
  # The check passed for any input until its own negative control caught it.
  grep -E "^\| .$1. \|" "$AD" | awk -F'|' '{print $4}' | tr -d '`' | tr ',' ' '
}
mismatch=""
for pair in "evidence sonnet" "ceiling opus" "retrieval haiku"; do
  set -- $pair
  for agent in $(tier_row "$1"); do
    case "$agent" in "(none"*|"today)"|"") continue ;; esac
    f=$(find "$REPO_ROOT"/skills -path "*/agents/$agent.md" | head -1)
    [ -n "$f" ] || { mismatch="$mismatch $agent(no-file)"; continue; }
    grep -qE "^model: *$2$" "$f" || mismatch="$mismatch $agent(row:$1 file:$(grep -m1 '^model:' "$f" | cut -d' ' -f2))"
  done
done
[ -z "$mismatch" ] \
  && pass "every agent's declared model matches the tier row it is listed in" \
  || fail "every agent's declared model matches the tier row it is listed in" "$mismatch"
rule "omit any model override"             "call sites let the declaration decide"
rule "only retrieves"                      "the retrieve-vs-decide line is named"

# The no-concrete-model-ID rule, enforced rather than asserted. A model ID is a
# volatile CLI literal: D44 cost a whole plan when one was scattered across nine
# files. Character classes so this pattern cannot match itself.
badmodel=""
for f in "$REPO_ROOT"/skills/*/agents/*.md; do
  [ -f "$f" ] || continue
  grep -qE '^model:[[:space:]]*(claude[-]|gpt[-]|gemini[-]|o[0-9])' "$f" && badmodel="$badmodel $(basename "$f")"
done
[ -z "$badmodel" ] \
  && pass "no agent pins a concrete model ID" \
  || fail "no agent pins a concrete model ID" "$badmodel"

# Every agent must declare SOME tier: an agent with no model line inherits the
# orchestrator's, which is the most expensive tier reached by omission rather
# than by decision.
notier=""
for f in "$REPO_ROOT"/skills/*/agents/*.md; do
  [ -f "$f" ] || continue
  grep -q '^model:' "$f" || notier="$notier $(basename "$f")"
done
[ -z "$notier" ] \
  && pass "every agent declares a tier rather than inheriting by omission" \
  || fail "every agent declares a tier rather than inheriting by omission" "$notier"

report
