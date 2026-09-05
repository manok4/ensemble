#!/usr/bin/env bash
# tests/lint/bin-template-sync.test.sh
#
# bin/ensemble-lint is a COPY of a skill-bundled source, installed per project
# so .github/workflows can invoke them by relative path. en-setup documents the
# drift risk; nothing enforced it.
#
# It bit on 2026-08-29: bin/ensemble-lint was copied during the en-setup retrofit,
# the template gained the TD8 phase rule afterwards, and local runs against the
# stale bin/ reported clean while CI ran the template and failed. A test passing
# locally and failing in CI is the most expensive shape of disagreement.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="bin template sync"

check() {  # $1=bin name  $2=source path
  local b="$REPO_ROOT/bin/$1" src="$REPO_ROOT/$2"
  if [ ! -f "$b" ]; then pass "bin/$1 not installed here — nothing to drift"; return; fi
  if [ ! -f "$src" ]; then fail "bin/$1 has a source to compare against" "missing $2"; return; fi
  if cmp -s "$b" "$src"; then
    pass "bin/$1 matches its bundled source"
  else
    fail "bin/$1 matches its bundled source" "re-copy from $2"
  fi
  [ -x "$b" ] && pass "bin/$1 is executable" || fail "bin/$1 is executable"
}

check ensemble-lint                 skills/en-setup/references/templates/ensemble-lint
# D101: the three sweep scripts are no longer installed project-local; a copy
# left in a consuming repo's bin/ is stale by definition.
for gone in en-sweep-ci ensemble-sweep-activity-check ensemble-doc-only-check; do
  [ -e "$REPO_ROOT/bin/$gone" ] && fail "bin/$gone is retired (D101); remove it" || pass "bin/$gone is not installed here"
done

# No dangling calls: a function invoked but never defined prints to stderr and
# keeps going, so it fails quietly. U15 deleted check_bootstrap_unvalidated and
# left its call behind; it survived until CI surfaced it.
LINT="$REPO_ROOT/skills/en-setup/references/templates/ensemble-lint"
dangling=""
for fn in $(grep -oE '^check_[a-z_]+$' "$LINT" | sort -u); do
  grep -q "^${fn}() {" "$LINT" || dangling="$dangling $fn"
done
[ -z "$dangling" ] && pass "every check_* call has a definition" \
                   || fail "every check_* call has a definition" "undefined:$dangling"

report
