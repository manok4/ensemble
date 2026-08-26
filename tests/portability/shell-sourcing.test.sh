#!/usr/bin/env bash
# tests/portability/shell-sourcing.test.sh
#
# The bin/ helpers that export functions must be sourceable from zsh as well as
# bash. macOS defaults to zsh, and several skills source these directly, e.g.
# skills/en-cross-review/SKILL.md's `. "$ENSEMBLE_ROOT/bin/ensemble-peer-invoke"`.
#
# The bug this guards: BASH_SOURCE is bash-only, so under zsh + `set -u` the
# sibling loads in ensemble-peer-invoke aborted, ensemble_smoke_classify was
# never defined, and ensemble_peer_invoke still returned a well-formed
# {"peer":"off","reason":"peer-failed:retry-exhausted"}. A broken helper was
# indistinguishable from a genuine peer failure, so peer review silently
# stopped running with no error a user would notice.
#
# The rest of the suite runs every file through `bash`, so nothing else
# exercises the zsh path.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="helper sourcing under bash and zsh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# Helpers that export functions, with a function each must define once sourced.
# ensemble-peer-invoke pulls in the other two, so it also proves the closure.
# Space-separated so the loop below stays in THIS shell. Piping into
# `while read` would fork a subshell, and assert.sh's counters live in shell
# variables -- every pass and, worse, every FAIL inside the subshell would be
# discarded and `report` would exit 0 on a broken helper.
HELPERS="ensemble-peer-invoke:ensemble_peer_invoke \
ensemble-peer-invoke:ensemble_smoke_classify \
ensemble-peer-invoke:ensemble_extract_json \
ensemble-cli-smoke:ensemble_smoke_classify \
ensemble-extract-json:ensemble_extract_json"

# Source $1 under shell $2 with `set -u`, then require function $3 to exist.
# Stderr is asserted empty: the original failure printed diagnostics while
# still exiting 0 through the caller, so an exit code alone would not catch it.
check_source() {
  local helper="$1" shell="$2" fn="$3"
  local script="$WORK/src-$shell-$helper-$fn.sh"
  cat > "$script" <<INNER
set -u
. "$REPO_ROOT/bin/$helper"
if command -v $fn >/dev/null 2>&1 || typeset -f $fn >/dev/null 2>&1; then
  echo DEFINED
fi
INNER
  local out err rc
  err="$WORK/err.txt"
  out=$("$shell" "$script" 2>"$err"); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "[$shell] $helper defines $fn" "exit $rc; stderr: $(head -2 "$err")"
  elif [ "$out" != "DEFINED" ]; then
    fail "[$shell] $helper defines $fn" "function not defined after sourcing"
  elif [ -s "$err" ]; then
    fail "[$shell] $helper sources cleanly" "stderr not empty: $(head -2 "$err")"
  else
    pass "[$shell] $helper defines $fn"
  fi
}

for shell in bash zsh; do
  if ! command -v "$shell" >/dev/null 2>&1; then
    pass "[$shell] not installed — skipped"
    continue
  fi
  for entry in $HELPERS; do
    check_source "${entry%%:*}" "$shell" "${entry##*:}"
  done
done

# Sourcing must not trigger ensemble-extract-json's direct-execution filter.
# Under zsh the bash test ($0 vs BASH_SOURCE) collapses, and a naive fallback
# runs the filter on every source, consuming the caller's stdin.
for shell in bash zsh; do
  command -v "$shell" >/dev/null 2>&1 || continue
  cat > "$WORK/nofilter-$shell.sh" <<INNER
set -u
. "$REPO_ROOT/bin/ensemble-extract-json"
echo SOURCED_ONLY
INNER
  out=$(printf 'stdin must not be consumed\n' | "$shell" "$WORK/nofilter-$shell.sh" 2>/dev/null)
  assert_eq "SOURCED_ONLY" "$out" "[$shell] sourcing ensemble-extract-json does not run the filter"
done

# ...but direct execution still must.
for shell in bash zsh; do
  command -v "$shell" >/dev/null 2>&1 || continue
  out=$(printf 'prefix {"a":1} suffix\n' | "$shell" "$REPO_ROOT/bin/ensemble-extract-json" 2>/dev/null)
  assert_contains "$out" '"a"' "[$shell] executing ensemble-extract-json still filters"
done

report
