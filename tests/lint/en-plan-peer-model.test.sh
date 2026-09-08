#!/usr/bin/env bash
# tests/lint/en-plan-peer-model.test.sh
#
# EN16 U2. /en-plan and /en-foundation invoked the peer with no model and no
# effort, so an operator's peer_codex_model never reached a plan review (the
# 2026-09-06 run used the config.toml default). Both now resolve through
# ensemble-peer-flags like /en-review; the ladder stays /en-review's, and a
# document review passes `inherit` when no override is set.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan peer model and effort"

FLAGS="$REPO_ROOT/skills/en-plan/scripts/ensemble-peer-flags"
PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"
FOUND="$REPO_ROOT/skills/en-foundation/SKILL.md"
BRIEF="$REPO_ROOT/skills/en-plan/references/peer-brief.md"
POLICY="$REPO_ROOT/skills/en-review/references/peer-model-policy.md"
has()   { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "missing: $2"; }
hasnt() { grep -qF -- "$2" "$1" && fail "$3" "still present: $2" || pass "$3"; }

# --- the translator: inherit ---
assert_eq "PEER_MODEL='-m gpt-x' PEER_EFFORT='' " \
  "$("$FLAGS" --effort inherit --peer-cmd 'codex exec' --codex-model gpt-x 2>/dev/null | tr '\n' ' ')" \
  "codex peer, inherit: model fragment kept, effort fragment empty"
assert_eq "PEER_MODEL='' PEER_EFFORT='-c model_reasoning_effort=\"high\"' " \
  "$("$FLAGS" --effort high --peer-cmd 'codex exec' 2>/dev/null | tr '\n' ' ')" \
  "codex peer, high, no model: unchanged behaviour"
assert_eq "PEER_MODEL='--model sonnet' PEER_EFFORT='' " \
  "$("$FLAGS" --effort inherit --peer-cmd 'claude -p' 2>/dev/null | tr '\n' ' ')" \
  "claude peer, inherit, no alias: default alias still applies, effort empty"
assert_eq "PEER_MODEL='--model opus' PEER_EFFORT='' " \
  "$("$FLAGS" --effort inherit --peer-cmd 'claude -p' --model-alias opus 2>/dev/null | tr '\n' ' ')" \
  "claude peer, inherit, alias: alias kept, effort empty"
out=$("$FLAGS" --effort max --peer-cmd 'claude -p' 2>/dev/null); rc=$?
assert_exit_code 2 "$rc" "max is still rejected"
assert_eq "" "$out" "a rejected tier emits nothing"

# --- the call sites ---
for f in "$PLAN" "$FOUND"; do
  n=$(basename "$(dirname "$f")")
  has "$f" 'scripts/ensemble-peer-flags --effort "${override:-inherit}"' "$n: translates with inherit as the floor"
  has "$f" 'peer_effort_<peer>'   "$n: reads the peer host's effort key (D104)"
  has "$f" 'peer_model_<peer>'    "$n: reads the peer host's model key (D104)"
  has "$f" '`--legacy` the old names' "$n: the retired spellings are read for the pair (D104)"
  has "$f" '$PEER_MODEL`, `$PEER_EFFORT`' "$n: passes both fragments to the invoke"
  has "$f" 'scripts/ensemble-config-get' "$n: reads through the shared config reader"
done
hasnt "$FOUND" "this skill passes no effort flag" "en-foundation no longer disclaims the effort flag"
hasnt "$BRIEF" "does not apply here" "the brief no longer says the override does not apply"
has   "$BRIEF" "--effort inherit" "the brief documents inherit as the unset behaviour"
hasnt "$POLICY" "is the only resolver" "the policy no longer names /en-review the only resolver"
has   "$POLICY" 'only `/en-review` runs the ladder' "the policy keeps the ladder with /en-review"

report
