#!/usr/bin/env bash
# tests/lint/metrics-vocabulary.test.sh
#
# The event vocabulary lives in three places that must agree: the `_ALLOW` table
# in ensemble-run-metrics, the kind tables in references/run-metrics.md, and
# each emitter's payload. script-parity and reference-parity guard the copies of
# each against each other; nothing guarded them against EACH OTHER.
#
# That gap is not hypothetical. EN17's own doc rewrite deleted every model call
# point while leaving a sentence saying they were unchanged, left four `outcome`
# keys in the allowlist that no emitter ever sent, and left three `peer` keys
# documented nowhere. Three drifts, in the same diff that built the vocabulary,
# and nothing went red.
#
# Guarded here:
#
#   EVERY KIND IS DOCUMENTED    a kind in _ALLOW with no row is a kind nobody
#                               can learn the meaning of.
#   EVERY ROW IS ALLOWED        a documented kind the allowlist does not carry
#                               is a call point whose events are all rejected.
#   THE KEYS MATCH, BOTH WAYS   a key in one and not the other is either
#                               silently dropped at the write, or a column that
#                               can only ever be absent.
#   EVERY KIND HAS AN EMITTER   the third column names who sends it. A kind
#                               nobody sends is a column of nulls.
#
# Negative controls at authoring: adding a key to _ALLOW alone, removing a row
# from the doc, and emptying a row's third column each turn an assertion red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="metrics event vocabulary"

RM="$REPO_ROOT/skills/en-build/scripts/ensemble-run-metrics"
DOC="$REPO_ROOT/skills/en-build/references/run-metrics.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# --- the allowlist, straight out of the script -------------------------------
sed -n "/^_ALLOW='/,/^}'\$/p" "$RM" | sed "1s/^_ALLOW='//; \$s/'\$//" > "$WORK/allow.json"
jq -e . "$WORK/allow.json" >/dev/null 2>&1 \
  && pass "the allowlist parses as JSON" \
  || fail "could not extract _ALLOW from $RM"
jq -r 'keys[]' "$WORK/allow.json" | sort > "$WORK/allow.kinds"
n_allow=$(wc -l < "$WORK/allow.kinds" | tr -d ' ')
[ "$n_allow" -ge 10 ] \
  && pass "the allowlist carries $n_allow kinds" \
  || fail "only $n_allow kinds parsed out of _ALLOW; the extraction is wrong"

# --- the doc's kind tables ---------------------------------------------------
# Rows look like: | `kind` | `key`, `key` | who sends it |
awk -F'|' '/^\| `[a-z]+` \|/ { gsub(/[` ]/, "", $2); print $2 }' "$DOC" | sort > "$WORK/doc.kinds"
n_doc=$(wc -l < "$WORK/doc.kinds" | tr -d ' ')
[ "$n_doc" -ge 10 ] \
  && pass "the reference documents $n_doc kinds" \
  || fail "only $n_doc kinds parsed out of $DOC; the extraction is wrong"

undocumented=$(comm -23 "$WORK/allow.kinds" "$WORK/doc.kinds" | tr '\n' ' ')
[ -z "$undocumented" ] \
  && pass "every allowlisted kind is documented" \
  || fail "a kind can be recorded that nothing documents" "undocumented: $undocumented"

unallowed=$(comm -13 "$WORK/allow.kinds" "$WORK/doc.kinds" | tr '\n' ' ')
[ -z "$unallowed" ] \
  && pass "every documented kind is allowed" \
  || fail "a documented kind would be rejected at the write" "not in _ALLOW: $unallowed"

# --- per kind, the keys agree in both directions ----------------------------
bad=""
while IFS= read -r kind; do
  jq -r --arg k "$kind" '.[$k][]' "$WORK/allow.json" | sort > "$WORK/a.keys"
  awk -F'|' -v k="$kind" '
    { line = $2; gsub(/[` ]/, "", line) }
    line == k { gsub(/[` ]/, "", $3); n = split($3, parts, ","); for (i = 1; i <= n; i++) print parts[i] }
  ' "$DOC" | grep -v '^$' | sort > "$WORK/d.keys"
  miss=$(comm -23 "$WORK/a.keys" "$WORK/d.keys" | tr '\n' ' ')
  extra=$(comm -13 "$WORK/a.keys" "$WORK/d.keys" | tr '\n' ' ')
  [ -z "$miss" ]  || bad="$bad [$kind undocumented: $miss]"
  [ -z "$extra" ] || bad="$bad [$kind documented but dropped at the write: $extra]"
done < "$WORK/allow.kinds"
[ -z "$bad" ] \
  && pass "every kind's keys match between the allowlist and the reference" \
  || fail "the allowlist and the reference disagree about keys" "$bad"

# --- every kind names who sends it ------------------------------------------
# A kind with no emitter is a column of nulls nobody will ever explain.
noemitter=$(awk -F'|' '/^\| `[a-z]+` \|/ { k = $2; gsub(/[` ]/, "", k); e = $4; gsub(/^[ \t]+|[ \t]+$/, "", e); if (e == "") print k }' "$DOC" | tr '\n' ' ')
[ -z "$noemitter" ] \
  && pass "every documented kind names its emitter" \
  || fail "a documented kind names no emitter" "$noemitter"

# --- the one model-emitted call point agrees with the allowlist both ways ----
# en-review-outcome-event checks skill-not-in-allowlist; this is the reverse,
# which is the direction that produces a column that can only ever be absent.
SK="$REPO_ROOT/skills/en-review/SKILL.md"
grep -o -- '--kind outcome --json .*' "$SK" | grep -oE '"[a-z_]+":' | tr -d '":' | sort -u > "$WORK/skill.keys"
jq -r '.outcome[]' "$WORK/allow.json" | sort > "$WORK/outcome.keys"
never=$(comm -13 "$WORK/skill.keys" "$WORK/outcome.keys" | tr '\n' ' ')
[ -z "$never" ] \
  && pass "every allowlisted outcome key has a call point that sends it" \
  || fail "an outcome key is allowed but never emitted" \
          "it can only ever be absent from the rollup: $never"

report
