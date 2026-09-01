#!/usr/bin/env bash
# tests/lint/en-build-payload-shape.test.sh
#
# After D52, en-build dispatches no peer and no agent. It invokes /en-simplify
# and /en-review and lets them own their own machinery. But it was still
# carrying the whole peer-dispatch stack — the invoker, the prompt builder, the
# Outside Voice template, the peer brief, the model policy, the CLI wrappers and
# their flag helpers, the single-agent fallback — plus a code-simplifier agent
# it never dispatched and an agents/ directory it no longer had.
#
# The reachability guard called all of it clean, because it was: reachable
# through chains that were themselves vestigial. Reachable is not the same as
# needed, and after a design change the difference is where the dead weight is.
#
# What en-build keeps, and why each one survives a "does it still do this?" test:
#   host-detect + detect-host   $QUESTION_TOOL, for the 9a confirmations
#   severity + peer-contract    it consumes P0-P3 graded findings from /en-review
#   finding-schema              the envelope shape it parses
#   stable-ids                  U-ID rules
#   recursion-guard             step 2
#   plan-hash                   step 4a and the phase boundaries
#   verify-peer-evidence        the step 10.5 audit
#   script-invocation           it calls two scripts

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build payload shape"
D="$REPO_ROOT/skills/en-build"

# --- 1. no peer-dispatch machinery came back ---
# en-build asks /en-review for a review; it never builds a prompt or invokes a
# subprocess itself. Any of these reappearing means that boundary moved.
back=""
for f in references/outside-voice.md references/peer-brief.md references/peer-model-policy.md \
         references/single-agent-fallback.md references/cli-wrappers.md \
         references/diff-signal-detection.md scripts/ensemble-peer-invoke \
         scripts/ensemble-build-peer-prompt scripts/ensemble-peer-flags \
         scripts/ensemble-cli-smoke scripts/ensemble-config-get scripts/ensemble-extract-json \
         scripts/en-sweep-ci; do
  [ -e "$D/$f" ] && back="$back $(basename "$f")"
done
[ -z "$back" ] \
  && pass "en-build carries no peer-dispatch machinery" \
  || fail "peer-dispatch machinery is back in en-build" "$back — it dispatches no peer (D52)"

# --- 2. no simplifier machinery: /en-simplify owns it ---
sback=""
[ -e "$D/agents/code-simplifier.md" ] && sback="$sback code-simplifier"
[ -e "$D/references/code-simplifier-dispatch.md" ] && sback="$sback code-simplifier-dispatch"
[ -d "$D/agents" ] && sback="$sback agents/"
[ -z "$sback" ] \
  && pass "en-build carries no simplifier or agent machinery" \
  || fail "simplifier or agent machinery is back" "$sback — en-build invokes /en-simplify and dispatches no agent"

# --- 3. what it consumes, it still carries ---
# The inverse failure: cutting so far that it cannot read what /en-review returns.
missing=""
for f in references/severity.md references/finding-schema.md references/peer-contract.md \
         references/host-detect.md scripts/ensemble-verify-peer-evidence scripts/ensemble-plan-hash; do
  [ -e "$D/$f" ] || missing="$missing $(basename "$f")"
done
[ -z "$missing" ] \
  && pass "en-build keeps what it consumes: graded findings, the envelope, the audit" \
  || fail "en-build lost something it consumes" "$missing"

# --- 4. host detection is kept for the one thing it still needs ---
# Keeping it "because skills detect hosts" would be cargo cult; it is here for
# the blocking prompts at 9a and nothing else.
if grep -qF 'QUESTION_TOOL' "$D/SKILL.md" && grep -qiE 'resolves no peer variables' "$D/SKILL.md"; then
  pass "host detection is scoped to \$QUESTION_TOOL, not peer resolution"
else
  fail "host detection must be scoped to what en-build still uses" \
       "it resolves no peer variables since D52"
fi

report
