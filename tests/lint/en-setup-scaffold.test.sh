#!/usr/bin/env bash
# tests/lint/en-setup-scaffold.test.sh
#
# What /en-setup creates is the shape every downstream skill assumes. If it still
# creates the retired directories, a fresh repo starts in the layout the rest of
# the system stopped supporting, and nothing announces the mismatch — capture
# writes flat while setup built somewhere else.
#
# The scaffold is executed by a model following SKILL.md, so these assertions
# check the specification and the verification checklist that the run reports
# against. Nothing here runs ./setup: the live install must not be touched.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-setup scaffold"

SKILL="$REPO_ROOT/skills/en-setup/SKILL.md"

# --- the skeleton creates the new layout -------------------------------------
# Scoped to the fenced skeleton block. Grepping the whole file also matched the
# checklist and the seeding step, so a line removed from the skeleton itself
# left these green.
SKEL=$(awk '/Create directory skeleton/,/^   - Use the platform/' "$SKILL")

for want in 'CONTEXT.md' 'decisions/' 'learnings/'; do
  printf '%s' "$SKEL" | grep -q "$want" \
    && pass "the skeleton block creates $want" \
    || fail "the skeleton block creates $want"
done

# --- and no longer the retired one -------------------------------------------
# The braces form is what the skeleton used, so match it directly.
if printf '%s' "$SKEL" | grep -q 'learnings/{bugs,patterns,decisions,sources}'; then
  fail "the skeleton no longer creates the retired directories"
else
  pass "the skeleton no longer creates the retired directories"
fi

# --- the verification checklist matches what is created ----------------------
# A checklist that asserts the old shape would report a correct run as broken,
# or worse, pass a run that built the wrong tree.
for want in 'docs/decisions/' 'docs/CONTEXT.md'; do
  grep -q "| \`$want\`" "$SKILL" \
    && pass "the verification checklist covers $want" \
    || fail "the verification checklist covers $want"
done

if grep -q '| `docs/learnings/{bugs,patterns,decisions,sources}/`' "$SKILL"; then
  fail "the checklist no longer asserts the four retired directories"
else
  pass "the checklist no longer asserts the four retired directories"
fi

# --- seeding is wired and ordered --------------------------------------------
# CONTEXT.md must be seeded after the skeleton exists, not before.
skel_ln=$(grep -n 'Create directory skeleton' "$SKILL" | head -1 | cut -d: -f1)
seed_ln=$(grep -n 'Seed `docs/CONTEXT.md`' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$skel_ln" ] && [ -n "$seed_ln" ] && [ "$skel_ln" -lt "$seed_ln" ]; then
  pass "CONTEXT.md is seeded after the skeleton exists"
else
  fail "CONTEXT.md is seeded after the skeleton exists" "skeleton=$skel_ln seed=$seed_ln"
fi

# --- State-3 detection still works on the new layout -------------------------
# State 3 means "Ensemble is already here". It probes docs/learnings/, which
# survives the change — asserted so a later edit cannot point it at a directory
# that no longer exists and silently reclassify every existing repo as State 2.
flat "$SKILL" | grep -q 'docs/learnings/ both prese' \
  && pass "State-3 detection probes a directory the new layout still creates" \
  || fail "State-3 detection probes a directory the new layout still creates"

# --- a declined install is recorded, not re-offered --------------------------
# en-sweep.yml sat in the REQUIRED artifact table, so declining it left every
# future run and every State-3 diagnostic reporting a missing required artifact
# and re-offering the install. A gate that fires on a deliberate choice is how a
# verification report becomes something you skim.

REQ=$(sed -n '/\*\*Required artifacts\*\*/,/\*\*Optional artifacts\*\*/p' "$SKILL")
OPT=$(sed -n '/\*\*Optional artifacts\*\*/,/\*\*Environment dependencies\*\*/p' "$SKILL")

if printf '%s' "$REQ" | grep -q 'en-sweep.yml'; then
  fail "en-sweep.yml is not a required artifact"
else
  pass "en-sweep.yml is not a required artifact"
fi

printf '%s' "$OPT" | grep -q 'en-sweep.yml' \
  && pass "en-sweep.yml is listed as an opt-in" \
  || fail "en-sweep.yml is listed as an opt-in"

flat "$SKILL" | grep -qi 'decline is recorded, never silent' \
  && pass "a declined install is recorded rather than left as a hole" \
  || fail "a declined install is recorded rather than left as a hole"

flat "$SKILL" | grep -qi 'sweep.enabled: false' \
  && pass "the install step honours a recorded decline" \
  || fail "the install step honours a recorded decline"

flat "$SKILL" | grep -qi 'do not re-prompt\|Do not re-prompt' \
  && pass "a recorded decline is not re-prompted" \
  || fail "a recorded decline is not re-prompted"

# --- one opt-in round (D96) --------------------------------------------------
# The retrofit used to stop up to seven times, one y/n per step. The round is
# asserted on its own heading, on the table carrying every item, and on the
# absence of the serial prompt shapes it replaced. Negative control at authoring:
# restoring the step-13a "Install now? (`y` / `n`)" prompt turned the last
# clause red.
flat "$SKILL" | grep -q 'Probe once, then ask once' \
  && pass "the retrofit asks its opt-ins in one round" \
  || fail "the retrofit asks its opt-ins in one round"
round_ok=1
for item in 'step 2)' 'step 9)' 'step 11)' 'step 12)' 'step 13)' 'step 13a)' 'step 14)' 'step 16)' 'step 18)'; do
  grep -qF "($item" "$SKILL" || { round_ok=0; fail "round lists the opt-in for $item"; }
done
[ "$round_ok" -eq 1 ] && pass "the round lists all nine opt-ins"
if grep -qE 'Install now\? \(|Install\? \(`y` / `n`\)|\(y/n; default y\)' "$SKILL"; then
  fail "no serial y/n prompt shape survives outside the round"
else
  pass "no serial y/n prompt shape survives outside the round"
fi
flat "$SKILL" | grep -q 'runs through step 18 without stopping' \
  && pass "after the round the install does not stop" \
  || fail "after the round the install does not stop"

# --- payload: en-setup dispatches nothing (2026-09-02) -----------------------
# It carried repo-research, learnings-research and the dispatch matrix it has no
# row in, and its SKILL.md named neither agent. Fifth instance of this defect.
ES="$REPO_ROOT/skills/en-setup/SKILL.md"
for gone in agents references/research-dispatch.md references/agent-dispatch.md \
            references/host-detect.md scripts/ensemble-detect-host references/recursion-guard.md; do
  [ -e "$REPO_ROOT/skills/en-setup/$gone" ] \
    && fail "en-setup no longer carries $gone" \
    || pass "en-setup no longer carries $gone"
done

# HOST was set at step 1 and read nowhere. If a use appears, the detection has to
# come back with it — so this fails rather than letting the variable be used unset.
# The sigil form only. Without it this matched the sentence explaining that the
# variables are gone — the rule forbidding its own explanation, the same shape
# the harness hash guard had. A use is `$PEER_AVAILABLE`; a mention is not.
if grep -qE '\$HOST\b|\$PEER_AVAILABLE\b' "$ES"; then
  fail "en-setup uses no host variable" "a use returned without the detection that sets it"
else
  pass "en-setup uses no host variable"
fi
grep -qF "read neither" "$ES" \
  && pass "the skill records why it carries no host detection" \
  || fail "the skill records why it carries no host detection"

# --- step citations: the off-by-one class a general guard cannot see ---------
# intra-file-step-citations catches a citation to a step that does not exist. It
# cannot catch a citation naming a real but WRONG step — five of those survived
# here because "step 13" resolves fine when 14 was meant. Each is pinned to the
# artifact its step actually installs.
cites() {  # $1=artifact substring  $2=expected step number
  line=$(grep -F -- "$1" "$ES" | grep -oE 'step [0-9]+' | head -1)
  if [ "$line" = "step $2" ]; then
    pass "$1 cites step $2"
  else
    fail "$1 cites step $2" "found '$line'"
  fi
}
cites "claude-code-review.yml\` (step" 14
cites "REVIEW.md\` (step" 16
cites "guardrail PreToolUse hook (step" 13
cites ".ensemble/config.local.yaml\` (step" 12

# The step that installs the bin scripts must not cite itself, which it did.
if grep -qF "en-sweep workflow in step 11" "$ES"; then
  pass "the bin-script step cites the workflow step, not itself"
else
  fail "the bin-script step cites the workflow step, not itself"
fi

report
