#!/usr/bin/env bash
# tests/lint/root-doc-links.test.sh
#
# Relative links in the repo's front-door docs must resolve.
#
# ensemble-lint covers docs/, and the parity check covers paths inside skills,
# but nothing checked README.md — so when EN12 moved references/ and bin/ under
# shared/, the README kept pointing at the old locations and nobody found out
# until someone read it. A contributor's first stop is the worst place for a
# path that no longer exists.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="root doc links"
cd "$REPO_ROOT"

for doc in README.md CONTRIBUTING.md CHANGELOG.md shared/README.md; do
  [ -f "$doc" ] || continue
  broken=""
  # Markdown links to a repo-relative path: ](./x) and ](x/y). Skip URLs,
  # anchors, and mailto.
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    case "$target" in
      http*|mailto:*|'#'*) continue ;;
    esac
    path="${target%%#*}"
    [ -n "$path" ] || continue
    path="${path#./}"
    [ -e "$path" ] || broken="$broken $target"
  done < <(grep -oE '\]\([^)]+\)' "$doc" | sed 's/^](//;s/)$//')
  assert_eq "" "$(echo $broken)" "[$doc] every relative link resolves"
done

# The README must not describe the pre-EN12 layout: those directories are gone,
# and pointing an editor at them is how the single-edit-point scheme gets
# bypassed.
for stale in '](./references' '](./bin' '](./agents/'; do
  if grep -qF "$stale" README.md; then
    fail "README links to a path that moved under shared/: $stale"
  else
    pass "README does not link to the pre-EN12 location $stale"
  fi
done

# And it must say where shared material is edited.
grep -q 'scripts/sync-shared' README.md \
  && pass "README tells contributors how to propagate a shared edit" \
  || fail "README must document scripts/sync-shared"

report
