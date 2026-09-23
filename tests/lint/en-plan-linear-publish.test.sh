#!/usr/bin/env bash
# tests/lint/en-plan-linear-publish.test.sh
#
# EN18 U3. On `plan_store: linear`, promotion publishes the reviewed plan to
# Linear instead of committing it. Every invariant below is one U1 measured
# against a live workspace or one the peer raised as a recovery gap, and each
# is the kind that fails silently: a read-back that verifies seven empty
# fields, a tracked source archived into a gitignored directory, a retry that
# creates a second parent. Prose is the only artifact here (all Linear I/O is
# model-driven MCP, per the plan's accepted risk), so these clauses are what
# stands between the contract and drift.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan linear publish"

SKILL="$REPO_ROOT/skills/en-plan/SKILL.md"
PUB="$REPO_ROOT/skills/en-plan/references/linear-publish.md"
FMT="$REPO_ROOT/skills/en-plan/references/linear-plan-format.md"
IGNORE="$REPO_ROOT/.gitignore"

has()   { grep -qiE -- "$2" "$1" && pass "$3" || fail "$3" "missing from $(basename "$1"): $2"; }
hasnt() { grep -qiE -- "$2" "$1" && fail "$3" "present in $(basename "$1") but should not be: $2" || pass "$3"; }
# Across line breaks, so a clause can require two facts TOGETHER. BSD grep -z
# does not match across newlines despite the flag and rejects intervals above
# 255; flattening with tr avoids both.
has_near() { tr '\n' ' ' < "$1" | grep -qiE -- "$2" && pass "$3" || fail "$3" "not found together in $(basename "$1"): $2"; }

# --- 0. the step exists and the skill routes to it ---------------------------
# Asserted first: every clause below passes against an orphaned reference that
# no step tells the agent to read.
[ -f "$PUB" ] && pass "references/linear-publish.md exists" \
  || { fail "references/linear-publish.md must exist"; report; }
has "$SKILL" 'references/linear-publish\.md' "en-plan SKILL.md routes to the publish step"
has "$SKILL" 'plan_store' "en-plan SKILL.md branches on plan_store at promotion"
# The flags ARE the mechanism. U2 built --strict for this key and the first
# draft of this unit named only the key, so `plan_store: Linear` fell through
# to local and the operator promoted believing a plan was published. Asserted
# in both the skill and the reference, because the review found the fix applied
# to en-build's side only.
has "$SKILL" '\-\-strict' "and reads it fail-closed, with --strict"
has "$PUB" 'allowed local,linear' "the publish step spells out the allowed set"
has "$PUB" '\-\-strict' "and --strict, so an invalid value cannot fall through"
has "$PUB" 'linear_team' "linear_team is resolved"
has "$PUB" '\-\-required' "with --required, since it has no sensible default"

# --- 1. local mode is untouched, and still commits ---------------------------
# The whole feature is opt-in. A future edit that quietly stops local mode
# committing would pass every Linear-mode clause in this file.
has "$SKILL" 'Auto-commit the plan file' "local mode still has the auto-commit step"
has "$PUB" '(local|`local`).*(unchanged|no change)' "the publish step states local mode is unchanged"
has "$PUB" 'skip.*auto-commit|auto-commit.*skip' \
  "linear mode skips the auto-commit step, so promotion makes no plan commit"

# --- 2. publish order and read-back verification -----------------------------
has "$PUB" 'dependency order' "units publish in dependency order"
has "$PUB" 'read.back|read it back' "the published plan is read back"

# The gate is the full mapping, not the hash alone. A hash-only gate verifies
# clean and then fails at /en-build step 4 on a field the hash never covered,
# which is the failure this clause exists to prevent.
has "$PUB" 'field.by.field|full invertible mapping|every field' \
  "verification compares the full invertible mapping, not only the hashed fields"
has "$PUB" 'ensemble-plan-hash' "the hash comparison is one clause of that verification"
has "$PUB" 'necessary but not sufficient|not the whole gate|one clause of it' \
  "the prose states why the hash alone is not the gate"

# --- 3. the marker rewrite, the single non-obvious fact in the design --------
# U1 measured it: Linear stores `- ` list markers as `* `, and ensemble-plan-hash
# anchors on `^- \*\*(Goal|Files|...)`. Without the normalization a read-back
# canonicalizes to seven EMPTY fields per unit, which still hashes. The tempting
# "fix" when verification fails on every plan is to weaken the comparison, so
# the normalization is asserted by name.
has "$PUB" 'normali[sz]' "the verify step normalizes the list markers before canonicalizing"
has "$PUB" '\* \*\*' "the prose names the rewritten marker Linear actually returns"
has "$FMT" 'normali[sz]' "the format doc owns the normalization rule both sides share"

# --- 4. sub-issue state is set, never inherited ------------------------------
# Measured: a sub-issue created under an Agent Ready parent lands in Backlog.
has "$PUB" '(state|status).*(explicit|set at creation)|explicitly at creation' \
  "each sub-issue's state is set explicitly at creation"
# Negation-blind before: bare `inherit` passed just as happily against the
# inverted claim ("a sub-issue DOES inherit its parent's state"), which is the
# opposite of what U1 measured.
has "$PUB" 'does not inherit|never inherits?' \
  "the prose records that state is not inherited"

# --- 5. the N+1 read-back is deliberate, not an oversight --------------------
has "$PUB" 'get_issue' "read-back fetches each unit with get_issue"
has "$PUB" 'truncat' "the prose records why: list_issues truncates descriptions"

# --- 6. tracked sources are never moved, for BOTH plan and design ------------
# The first draft assumed the plan is always untracked because /en-plan wrote
# it that run. False on --resume. Moving a tracked file into a gitignored
# directory leaves a tracked deletion, dirtying the tree a no-commit promotion
# promises not to touch. Asserted for both sources: a clause naming only the
# design would pass against exactly the bug the peer found.
has "$PUB" 'tracked' "the publish step checks tracked status"
has "$PUB" 'both sources|plan or design|plan and design' \
  "the tracked check covers both the plan and the design doc"
has "$PUB" 'before any Linear mutation|before the Linear write|before any linear write' \
  "tracked status is resolved before any Linear mutation, not after"
has_near "$PUB" 'tracked *\*?deletion' "the prose names the first failure the check prevents"
has "$PUB" 'tracked \*?modification' \
  "and the second, which the first fix introduced"

# A tracked source REFUSES. Two weaker rules shipped and were caught in review:
# moving a tracked file leaves a tracked deletion, and leaving it in place but
# stamping it leaves a tracked modification. Neither could satisfy the empty
# `git status --porcelain` the contract asserts, because by then the finalize
# loop and promotion have already written to the same tracked file.
has_near "$PUB" 'tracked (plan|source)[^#]{0,80}refuse|refuse[^#]{0,80}tracked' \
  "a tracked source refuses linear-mode promotion"
has "$PUB" 'git rm --cached' "and the refusal names the remedy"
has "$PUB" 'before the plan is written, before the finalize loop writes' \
  "the check runs before the plan is written, not just before the Linear call"
# And SKILL.md runs it there. The reference is otherwise read at the publish
# step, after the plan write, the finalize loop and promotion have all written.
write_step=$(awk '/^[0-9]+\. \*\*Write the plan/{f=1} f&&/^[0-9]+\. \*\*Outside Voice/{exit} f' "$SKILL")
assert_contains "$write_step" 'Tracked sources, under `plan_store: linear`' \
  "en-plan runs the tracked-source check inside the write-the-plan step"
has "$SKILL" 'the tracked-source refusal' "step 18 names the refusal, not the retired keep-in-place rule"
hasnt "$SKILL" 'keeps a tracked plan or design in place' \
  "and the retired keep-in-place wording is gone from SKILL.md"
has "$PUB" 'git status --porcelain' \
  "the clean-tree contract is stated as something someone can run"
has "$PUB" '\.ensemble/archive-plans' "untracked plans archive to .ensemble/archive-plans/"
has "$PUB" '\.ensemble/archive-designs' "untracked designs archive to .ensemble/archive-designs/"
has "$PUB" 'linear_issue:' "archived sources are stamped with linear_issue:"
has "$PUB" 'archived:' "archived sources are stamped with archived:"

# --- 7. the design doc's amendments are confirmed here, not in U7 ------------
# Once the design is archived or closed out, an un-amended one is the version
# that survives. U7 runs last, so it cannot be the gate.
has "$PUB" 'amend' "the design doc's amendments are confirmed before its fate is decided"

# --- 8. recovery: nothing moves, and cleanup cancels ------------------------
has "$PUB" 'mismatch|partial publish' "a mismatch or partial publish is handled"
has "$PUB" 'move nothing|archives nothing|nothing is moved' \
  "on failure nothing is archived and the plan stays in active/"
# U1 found no delete-issue tool on the MCP server. A prose rollback that says
# "delete" describes an operation that does not exist.
has "$PUB" 'Rollback cancels|cancels what it created' \
  "rollback cancels what it created"
# Anchored on the tool's absence, not on the word "delete": a looser pattern
# matched "Rollback cancels; it does not delete" and stayed green when the
# absence claim itself was flipped, which is the only fact this clause guards.
has "$PUB" 'no delete-issue tool|exposes no delete' \
  "the prose records that no delete-issue tool exists, which is why cleanup cancels"

# --- 9. idempotency: discovery precedes the create ---------------------------
# Write-after-create narrows the duplicate-parent window but cannot close it:
# a process killed between the API returning and the frontmatter write leaves
# an orphan the next run cannot see, and the run after that creates a second.
has "$PUB" 'discover' "retry discovers an existing parent before creating one"
has "$PUB" 'plan_id' "discovery keys on the plan's stable identity"
has "$PUB" 'crash window|killed between|cannot close it' \
  "the prose records why write-after-create alone is not enough"
has "$PUB" 'cancel(l)?ed parent|canceled state|cancelled state' \
  "discovery skips cancelled parents rather than resurrecting their sub-issues"
has "$PUB" 'two live parents|two parents' "two live parents for one plan_id refuse"
has "$PUB" 'same U-ID|duplicate U-ID|two sub-issues claim' \
  "duplicate U-IDs under one parent refuse rather than guess"

# The five steps are ordered, and the order is the contract. Counted rather
# than matched one by one: a protocol that lost step 2 would still satisfy a
# clause that only looked for a "5.".
steps=$(awk '/^## Idempotency protocol/{f=1; next} f&&/^## /{exit} f' "$PUB" | grep -cE '^[1-9]\. ')
assert_eq "5" "$steps" "the idempotency protocol keeps all five ordered steps"

# --- 10. the /en-flow boundary is enforced, not documented -------------------
has "$PUB" 'en-flow' "the /en-flow boundary is named"
# Scoped to the boundary's own section. A bare `refuse` matched the two
# unrelated refusals in the idempotency protocol, so this clause could not fail
# even with the /en-flow rule softened to a note.
flow=$(awk '/^## The `\/en-flow` boundary/{f=1; next} f&&/^## /{exit} f' "$PUB")
printf '%s' "$flow" | grep -qiE 'refuse' \
  && pass "and enforced by refusing before publishing" \
  || fail "and enforced by refusing before publishing" "the /en-flow section itself must say refuse"

# --- 11. .gitignore carries the two archive entries, precisely ---------------
has "$IGNORE" '^\.ensemble/archive-plans/' ".gitignore ignores .ensemble/archive-plans/"
has "$IGNORE" '^\.ensemble/archive-designs/' ".gitignore ignores .ensemble/archive-designs/"
# A bare `.ensemble/` would swallow the tracked example file, which is the
# reason the entries are written out individually.
hasnt "$IGNORE" '^\.ensemble/$' ".gitignore has no bare .ensemble/ line"
if git -C "$REPO_ROOT" check-ignore -q .ensemble/archive-plans/x.md \
   && git -C "$REPO_ROOT" check-ignore -q .ensemble/archive-designs/x.md; then
  pass "git check-ignore confirms both archive paths are ignored"
else
  fail "git check-ignore must ignore both archive paths"
fi
if git -C "$REPO_ROOT" check-ignore -q .ensemble/config.local.example.yaml; then
  fail "the tracked example config must NOT be ignored" \
       "a bare .ensemble/ entry would swallow it"
else
  pass "git check-ignore leaves .ensemble/config.local.example.yaml tracked"
fi

report
