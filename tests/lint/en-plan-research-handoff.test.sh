#!/usr/bin/env bash
# tests/lint/en-plan-research-handoff.test.sh
#
# EN16 U9. A user ran three research agents before invoking /en-plan, and the
# skill then dispatched repo-research and web-research over the same ground
# (about $67 on one run, 2026-09-06). `--research <path>` hands the prior
# findings in. Three properties must hold and each is anchored on its own line:
# both named agents are skipped, the read is bounded, and an unreadable path
# stops the run before any dispatch rather than falling through to paid work.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan research hand-off"

S="$REPO_ROOT/skills/en-plan/SKILL.md"
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "missing: $2"; }

# SKILL.md is size-pinned (tests/lint/skill-size.test.sh), so it carries the
# flag, the skip and the report line; the rule's detail lives in the
# research-dispatch reference every research-dispatching skill carries.
has "$S" '`--research <path>`' "the Flags table lists --research"
has "$S" 'and neither is dispatched' "both research agents are skipped under --research"
has "$S" '`learnings-research` keeps its own rule' "learnings-research is not skipped"
has "$S" 'research: user-supplied (<path>)' "the run report names the source"
has "$S" 'before any dispatch' "SKILL.md states the unreadable-path stop"

distinct=$(for f in "$REPO_ROOT"/skills/*/references/research-dispatch.md; do hash_file "$f"; done | sort -u | wc -l | tr -d " ")
assert_eq "1" "$distinct" "every research-dispatch.md carrier is byte-identical"
RD="$REPO_ROOT/skills/en-plan/references/research-dispatch.md"
has "$RD" 'User-supplied research.' "the dispatch matrix footnotes the hand-off"
has "$RD" 'bounded to its first 200 lines' "the read is bounded"
has "$RD" 'nothing past line 200 enters context' "the bound is a hard cut, not a summary"
has "$RD" 'stop with a one-line error naming it, before any agent and before round 1' "an unreadable path stops before any dispatch"
has "$RD" 'treat it as the `repo-research` and `web-research` result, and dispatch neither' "the reference says both agents are skipped"
has "$RD" 'stating the findings were not re-verified' "the plan records the hand-off as an assumption"

report
