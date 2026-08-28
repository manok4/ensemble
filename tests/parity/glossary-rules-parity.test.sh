#!/usr/bin/env bash
# tests/parity/glossary-rules-parity.test.sh
#
# glossary-rules.md is carried by more than one skill: en-learn accretes terms
# during capture, en-setup seeds them during scaffolding. Post-EN13 each skill
# owns its files outright, so the copies can drift silently.
#
# Carriership is derived from BEHAVIOUR — a skill that declares the file in its
# requires: block — not from the file being present on disk. EN13 shipped a
# parity guard that found its subjects by looking for the file, so deleting the
# file and its declaration together left the guard with nothing to check and
# nothing to say. This one counts declarations first.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="glossary rules parity"

REF_REL="references/glossary-rules.md"

# Who CLAIMS to carry it (declaration), and who actually HAS it (file)?
declared=""; present=""
for skill in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$skill")
  grep -q "$REF_REL" "$skill/SKILL.md" 2>/dev/null && declared="$declared $name"
  [ -f "$skill/$REF_REL" ] && present="$present $name"
done
dn=$(echo $declared | wc -w | tr -d ' ')
pn=$(echo $present  | wc -w | tr -d ' ')

# Two skills need it and for different reasons: accretion and seeding.
[ "$dn" -ge 2 ] \
  && pass "at least two skills declare the glossary rules ($dn:$declared )" \
  || fail "at least two skills declare the glossary rules" "found $dn:$declared"

assert_eq "$dn" "$pn" "every skill that declares the rules also carries the file"

for skill in $declared; do
  [ -f "$REPO_ROOT/skills/$skill/$REF_REL" ] \
    && pass "$skill declares and carries the rules" \
    || fail "$skill declares the rules but the file is missing"
done

# Byte-identity across carriers.
ref=""; skew=0
for skill in $present; do
  sum=$(shasum "$REPO_ROOT/skills/$skill/$REF_REL" | cut -d' ' -f1)
  [ -z "$ref" ] && ref="$sum"
  [ "$sum" = "$ref" ] || { skew=$((skew+1)); }
done
assert_eq "$skew" "0" "every carried copy of the glossary rules is byte-identical"

# The two population paths must survive in the shared copy: without seeding the
# file fills with peripheral mechanics; without accretion it goes stale.
for skill in $present; do
  f="$REPO_ROOT/skills/$skill/$REF_REL"
  for concept in Accretion Seeding 'Flagged ambiguities' 'stands on its own'; do
    grep -qi "$concept" "$f" \
      && pass "$skill's copy retains: $concept" \
      || fail "$skill's copy retains: $concept"
  done
done

report
