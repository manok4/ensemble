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

# --- 4. every carried agent is declared, so skill-payload stays consistent ---
undeclared=""
for skill in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$skill")
  for f in "$skill"agents/*.md; do
    [ -f "$f" ] || continue
    a=$(basename "$f" .md)
    grep -q "^  - agents/$a.md\$" "$skill/SKILL.md" || undeclared="$undeclared $name->$a"
  done
done
[ -z "$undeclared" ] && pass "every carried agent is declared in requires:" \
                     || fail "every carried agent is declared in requires:" "$undeclared"

# --- 5. the retired seven must not come back by name ---
if grep -rqE 'subagent_type: "(correctness|testing|maintainability|standards|security|performance|migrations)-reviewer"' "$REPO_ROOT/skills" 2>/dev/null; then
  fail "no skill dispatches the retired per-dimension reviewers"
else
  pass "no skill dispatches the retired per-dimension reviewers"
fi

report
