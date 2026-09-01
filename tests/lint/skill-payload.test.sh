#!/usr/bin/env bash
# tests/lint/skill-payload.test.sh
#
# A skill must carry what it names, and name what it carries. Both directions,
# derived from the skill's own body — there is no manifest to consult.
#
# THE HISTORY MATTERS, because this is the second attempt.
#
# EN12 derived payload from mentions and got 422 files where 193 were needed:
# learn-lint.md names ensemble-lint in a sentence whose whole purpose is to say
# it is a DIFFERENT tool, and that one contrast dragged a 45KB script and 56KB
# of its references into en-learn. EN13 concluded that mentions are not
# dependencies and replaced the walk with a hand-written requires: manifest.
#
# The manifest was a second copy of the truth. It answered "did someone list
# this?", never "does the flow reach it?" or "does what it names exist?" — so it
# carried cli-wrappers.md, which called itself the source of truth for CLI flags
# while nothing read it, and it never noticed that en-setup named a
# scripts/check-health it did not carry.
#
# The walk is back, with the discriminator EN12 lacked: a path counts only when
# it is BACKTICKED, a markdown link, or inside a fence. Bare prose does not
# count — which is precisely the ensemble-lint contrast sentence, and is
# asserted below on a fixture so the EN12 failure cannot return.
#
# The rules live in tests/lib/skill-payload.py; each is commented with the real
# file that taught it. This test proves them, on the tree and on fixtures.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="skill payload matches what each skill names"
cd "$REPO_ROOT"

LIB=tests/lib/skill-payload.py

# --- 1. the real tree, both directions ---------------------------------------
out=$(python3 "$LIB" compare 2>&1)

unreached=$(printf '%s\n' "$out" | grep UNREACHED || true)
[ -z "$unreached" ] \
  && pass "every carried file is reached from its skill's own flow" \
  || fail "every carried file is reached from its skill's own flow" \
          "$(printf '%s' "$unreached" | tr '\n' ' ' | cut -c1-200)"

missing=$(printf '%s\n' "$out" | grep MISSING || true)
[ -z "$missing" ] \
  && pass "every path a skill names resolves inside it" \
  || fail "every path a skill names resolves inside it" \
          "$(printf '%s' "$missing" | tr '\n' ' ' | cut -c1-200)"

# --- 2. fixtures: the rules, on cases the tree does not currently hold --------
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

mk() {  # $1 skill  $2 SKILL.md body  $3.. files to create (empty)
  local s="$1" body="$2"; shift 2
  mkdir -p "$WORK/$s"
  printf -- '---\nname: %s\n---\n%s\n' "$s" "$body" > "$WORK/$s/SKILL.md"
  for f in "$@"; do mkdir -p "$WORK/$s/$(dirname "$f")"; : > "$WORK/$s/$f"; done
}
derived() { python3 "$REPO_ROOT/$LIB" compare "$WORK" 2>&1 | grep "^$1	" || true; }

mk clean 'read `references/a.md`' references/a.md
assert_eq "" "$(derived clean)" "a skill naming exactly what it carries is clean"

mk excess 'read `references/a.md`' references/a.md references/orphan.md
assert_eq "excess	UNREACHED	references/orphan.md" "$(derived excess)" \
  "a carried file no flow reaches is reported, by name"

mk dangling 'read `references/a.md` and `references/ghost.md`' references/a.md
assert_eq "dangling	MISSING	references/ghost.md	(named in SKILL.md)" "$(derived dangling)" \
  "a named path with no file behind it is reported"

# THE EN12 REGRESSION GUARD. The sentence that cost 101KB was unmarked prose
# naming a tool to contrast against it. Unbackticked, it must not create a
# dependency — in either direction: it neither reaches the carried file nor
# claims the absent one exists.
mk prose 'unlike references/other-tool.md, this skill uses `references/a.md`' \
   references/a.md references/other-tool.md
assert_eq "prose	UNREACHED	references/other-tool.md" "$(derived prose)" \
  "a bare prose mention creates no dependency, in either direction"

# Nested paths, agents by subagent_type, and scripts all parse.
mk shapes 'run `scripts/x`, read `references/templates/t.md`, dispatch subagent_type: "y"' \
   scripts/x references/templates/t.md agents/y.md
assert_eq "" "$(derived shapes)" "nested reference, script and agent paths all parse"

# A script names its helper relative to itself, with no asset-dir prefix to
# anchor on — check-guardrail.sh sources "$SCRIPT_DIR/guardrail_analyze.py".
mk sibling 'run `scripts/main.sh`' scripts/main.sh scripts/helper.py
printf 'python3 "$SCRIPT_DIR/helper.py"\n' > "$WORK/sibling/scripts/main.sh"
assert_eq "" "$(derived sibling)" "a helper a script calls relative to itself is reached"

# Reachability is transitive: the flow reaches A, A names B, B names C.
mk chain 'read `references/a.md`' references/a.md references/b.md references/c.md
printf 'see `references/b.md`\n' > "$WORK/chain/references/a.md"
printf 'see `references/c.md`\n' > "$WORK/chain/references/b.md"
assert_eq "" "$(derived chain)" "reachability follows the whole chain, not just the first hop"

# --- 3. the manifest is gone, and stays gone ---------------------------------
# Leaving one behind is worse than either design: a stale list that no longer
# gates anything still reads as authoritative to whoever edits the skill next.
left=$(grep -l '^requires:' skills/*/SKILL.md 2>/dev/null || true)
[ -z "$left" ] \
  && pass "no skill carries a requires: manifest" \
  || fail "no skill carries a requires: manifest" "$(echo $left)"

report
