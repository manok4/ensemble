#!/usr/bin/env bash
# tests/lint/test-runner-isolation.test.sh
#
# The suite drives stub peer CLIs on purpose: they are how it proves the
# invoker retries once, classifies auth, timeout and unknown failures, and keeps
# its isolation flags, none of which a real paid CLI can be made to do on
# demand. What must not happen is the stubs' calls being recorded as real ones.
# ensemble-run-metrics writes to $ENSEMBLE_RUN_LEDGER, else to the newest open
# run in the current repository, and when the suite ran inside /en-build every
# stub landed in the build's ledger (90 fake peer events in the EN21 run).
# tests/run.sh now gives every test a scratch ledger. This asserts that under
# the runner's environment a stub peer call made inside an open run records
# nothing in that run.
#
# It checks the environment tests/run.sh provides, so run directly it re-runs
# itself through the runner.
#
# Negative control at authoring: removing the ENSEMBLE_RUN_LEDGER export from
# tests/run.sh let the stub's peer event into the open run, and this went red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
if [ -z "${ENSEMBLE_TEST_RUNNER:-}" ]; then
  exec "$REPO_ROOT/tests/run.sh" -k "tests/lint/test-runner-isolation.test.sh"
fi
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="test runner isolates the metrics ledger"

RM="$REPO_ROOT/skills/en-review/scripts/ensemble-run-metrics"
INVOKE="$REPO_ROOT/skills/en-review/scripts/ensemble-peer-invoke"

case "${ENSEMBLE_RUN_LEDGER:-}" in
  "") fail "tests/run.sh must export ENSEMBLE_RUN_LEDGER" ;;
  "$REPO_ROOT"/*) fail "the scratch ledger must live outside the repository" "$ENSEMBLE_RUN_LEDGER" ;;
  *) pass "every test gets a scratch ledger outside the repository" ;;
esac

# An open run in a throwaway repo stands in for a live /en-build run.
W=$(mktemp -d)
export ENSEMBLE_ANALYTICS_DIR="$W/analytics"   # the rollup from finish stays in the scratch dir
(
  cd "$W" || exit 1
  git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
) >/dev/null
open_ledger=$(cd "$W" && bash "$RM" start --skill en-build 2>/dev/null)
[ -f "$open_ledger" ] && pass "a run is open in the throwaway repo" || fail "could not open a run" "$open_ledger"

printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null; echo "{}"' > "$W/stubpeer"
chmod +x "$W/stubpeer"
printf 'prompt\n' > "$W/prompt"
(
  cd "$W" || exit 1
  bash --noprofile --norc -c '
    . "$1"
    ensemble_peer_invoke --peer-cmd "$2" --peer-format "--json" --prompt-file "$3" \
      --out-file /dev/null --peer-mode cross-agent >/dev/null 2>&1 || true
  ' _ "$INVOKE" "$W/stubpeer" "$W/prompt"
)
if [ -f "$open_ledger" ] && ! grep -q '"kind":"peer"' "$open_ledger"; then
  pass "a stub peer call inside an open run records nothing in that run"
else
  fail "the stub peer call leaked into the open run's ledger" "$(grep '"kind":"peer"' "$open_ledger" 2>&1 | head -2)"
fi

(cd "$W" && bash "$RM" finish >/dev/null 2>&1)
rm -rf "$W"
report
