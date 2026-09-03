#!/usr/bin/env bash
# tests/lint/host-only-substitutions.test.sh
#
# A skill's instructions must not depend on a substitution only one host
# performs. These expand on Claude Code and to nothing on Codex, so the
# instruction does not fail, it silently means something else: a guarded call
# becomes an unguarded one, a request passed to a sub-skill becomes an empty
# request.
#
# Written 2026-09-03. The rule was already stated, in eight byte-identical
# copies of references/script-invocation.md, which call ${CLAUDE_SKILL_DIR}
# "not a portable alternative ... a Claude-Code-only content substitution that
# expands to empty on Codex, which turns a guarded call into a silent skip".
# Nothing enforced it. /en-flow used $ARGUMENTS to pass the user's request into
# /en-plan, the same class of substitution, in the one skill that does not
# carry that reference. An empty expansion there plans nothing.
#
# The prose that names a substitution in order to forbid it is exempt, by
# looking for a nearby negation on the same line. Three guards in this repo
# have already been written so strictly that they flagged their own
# explanation.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="host-only substitutions"

# Written as character classes so this file does not match itself if it is ever
# scanned by the same rule.
BANNED='[C]LAUDE_SKILL_DIR|[A]RGUMENTS'

# A line is allowed when it is teaching that the substitution is wrong.
NEGATED='not a portable|expands to empty|Claude-Code-only|until 2026|never use|do not use|must not|is not a skill'

offenders=""
for d in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$d")
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    printf '%s' "$hit" | grep -qE "$NEGATED" && continue
    offenders="$offenders $name:$(printf '%s' "$hit" | cut -d: -f2)"
  done <<EOF
$(grep -rnE "\\\$\{?($BANNED)\}?" "$d" 2>/dev/null | sed "s|^$d||")
EOF
done

if [ -z "$offenders" ]; then
  pass "no skill instruction depends on a host-only substitution"
else
  fail "these lines depend on a substitution that expands to empty off Claude Code" "$offenders"
fi

# The rule must stay written down where a skill author will meet it, not only
# enforced here. A guard with no prose behind it teaches nobody why.
carriers=0; stating=0
for f in "$REPO_ROOT"/skills/*/references/script-invocation.md; do
  [ -f "$f" ] || continue
  carriers=$((carriers+1))
  grep -qF 'is not a portable alternative' "$f" && stating=$((stating+1))
done
assert_eq "$stating" "$carriers" "all $carriers copies of script-invocation.md still state the rule"

report
