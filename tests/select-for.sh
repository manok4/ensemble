#!/usr/bin/env bash
# tests/select-for.sh — run the tests that could plausibly break from these files.
#
# WHY THIS EXISTS.  The full suite is ~286s. Across four consecutive branches the
# expensive pattern was the same: make a small edit, run the whole suite to check
# nothing broke, repeat. Ten rounds of that is forty minutes of waiting for a
# question the relevant four test files answer in six seconds. Ensemble ships
# `ensemble-test-select` to solve exactly this for other projects and this repo
# declared nothing it could use, so every selection came back `empty`.
#
# WHAT IT IS NOT.  It is not authoritative and it must not be treated as one.
# Many tests here anchor on file CONTENT — they grep for a clause inside a
# SKILL.md they are not named after — and no path-based rule can find those from
# the path that changed. So:
#
#     iterate against this; run ./tests/run.sh in full before you commit.
#
# That split is the whole design. A fast approximate check while editing, and one
# authoritative run before the change leaves your machine.
#
# Usage:  tests/select-for.sh <changed path>...
#         tests/select-for.sh --print <changed path>...   # patterns only, run nothing
#
# --print RUNS NOTHING, including on the escalation path, where it prints
# FULL-SUITE. The first version exec'd the runner there and recursed through its
# own test file until it was killed.
#
# Declared in AGENTS.md as `test_changed_command`, so /en-build's unit gate and
# /en-ship's preflight resolve the `graph` tier through it rather than falling to
# `empty`.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$ROOT"

PRINT_ONLY=false
ESCALATE=false
[ "${1:-}" = "--print" ] && { PRINT_ONLY=true; shift; }
[ $# -gt 0 ] || { echo "usage: tests/select-for.sh [--print] <changed path>..." >&2; exit 2; }

pats=""
add() { case " $pats " in *" $1 "*) : ;; *) pats="$pats $1" ;; esac; }

skills_touched=false
for f in "$@"; do
  case "$f" in
    # A test file always selects itself.
    tests/*.test.sh|tests/*/*.test.sh)
        add "$(basename "$f" .test.sh)" ;;
    tests/lib/*|tests/run.sh|tests/select-for.sh)
        # The harness itself, and this file: nothing is safe to approximate when
        # the thing that runs or selects tests is what changed. --print must
        # still print rather than run, or this recurses through its own test.
        ESCALATE=true ;;

    # A skill's own tests are named after it, and every skill change can move
    # the payload, the size budget or a parity hash.
    skills/*/SKILL.md|skills/*/CONTRACT.md)
        s=${f#skills/}; add "${s%%/*}"; skills_touched=true ;;
    skills/*/scripts/*)
        add "$(basename "$f")"; s=${f#skills/}; add "${s%%/*}"; skills_touched=true ;;
    skills/*/references/*|skills/*/agents/*)
        b=$(basename "$f"); add "${b%.md}"; s=${f#skills/}; add "${s%%/*}"; skills_touched=true ;;

    bin/*)   add "lint-rules"; add "bin-template-sync"; add "$(basename "$f")" ;;
    docs/foundation.md) add "decision-log-order" ;;
    docs/plans/*)       add "decision-log-order"; add "lint-rules" ;;
    AGENTS.md|CLAUDE.md|docs/*) add "lint-rules" ;;
    *) ;;
  esac
done

if [ "$ESCALATE" = true ]; then
  if [ "$PRINT_ONLY" = true ]; then
    printf 'FULL-SUITE\n'
    exit 0
  fi
  exec ./tests/run.sh
fi

if [ "$skills_touched" = true ]; then
  add "parity"; add "skill-size"; add "skill-payload"; add "frontmatter"
fi

[ -n "$pats" ] || { echo "select-for: no test pattern matches those paths; run the full suite" >&2; exit 0; }

# One alternation, so shared tests run once rather than once per pattern.
pattern=$(printf '%s' "${pats# }" | tr ' ' '\n' | sed 's/[.[\*^$]/\\&/g' | paste -sd'|' - | sed 's/|/\\|/g')

if [ "$PRINT_ONLY" = true ]; then
  printf '%s\n' "$pattern"
  exit 0
fi
echo "select-for: approximate set — run ./tests/run.sh in full before committing" >&2
exec ./tests/run.sh -k "$pattern"
