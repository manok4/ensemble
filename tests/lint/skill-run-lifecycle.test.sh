#!/usr/bin/env bash
# tests/lint/skill-run-lifecycle.test.sh
#
# A skill whose helpers emit but which never calls `start` records nothing:
# `emit` resolves no ledger and is a silent no-op, which is the correct default
# and the reason the gap is invisible. EN17's first plan had exactly that shape
# — four emitter units and no lifecycle — so /en-ship would have looked
# instrumented and produced no data for any skill but en-build.
#
# Guarded here, for every skill that CARRIES the helper, so a sixth carrier is
# covered without editing this file:
#
#   A RUN IS OPENED        `start --skill <name>` is present and reachable.
#   UNDER ITS OWN NAME     the name matches the directory, so a copied line
#                          cannot record en-build from inside en-ship.
#   A RUN IS CLOSED        exactly one `finish` call site, not zero and not
#                          several, since each one is a terminal path.
#   TERMINAL PATHS SAY SO  "finish on every terminal path" is unverifiable as
#                          prose, so the skill states the contract in a fixed
#                          phrase and the lint requires it. That does not prove
#                          the model obeys; it does stop the contract being
#                          dropped silently, which is what a bypass looks like.
#
# Negative controls at authoring: deleting en-ship's finish line turned the
# close assertion red naming en-ship; changing one `start --skill` to another
# skill's name turned the matching assertion red; deleting the terminal-path
# sentence turned the contract assertion red. The fixtures below re-run all
# three mechanically.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="skill run lifecycle"

MARK='\*\*Every terminal path closes the run'

# One pass over a SKILL.md. Prints nothing; sets LC_* for the caller.
# The skill's own flow is its SKILL.md AND the reference it cites for this,
# because that is what the model reads at the moment it decides to stop. The
# contract sentence lives in the shared reference rather than six SKILL.md
# bodies: two of the six sit within 210 bytes of the size budget, and one
# sentence in one file cannot drift across copies the way six can.
lifecycle_check() {  # <skill-dir>
  local dir="$1" name f
  name=$(basename "$dir"); f="$dir/SKILL.md"
  # The CALLS are counted in the skill body only. The shared reference carries
  # worked examples of both, so counting across it turns every carrier into
  # three finish sites and a start under somebody else's name.
  local ref="$dir/references/run-metrics.md"
  LC_START=$(grep -cE 'ensemble-run-metrics" +start' "$f" || true)
  LC_NAMED=$(grep -hcE "ensemble-run-metrics\" +start --skill $name( |\`|\)|$)" "$f" || true)
  LC_WRONG=$(grep -oE 'ensemble-run-metrics" +start --skill [a-z0-9-]+' "$f" \
             | awk '{print $NF}' | grep -vc "^$name$" || true)
  LC_FINISH=$(grep -cE 'ensemble-run-metrics" +finish' "$f" || true)
  LC_MARK=$(cat "$f" $([ -f "$ref" ] && printf %s "$ref") | grep -cE "$MARK" || true)
}

# The carrier set IS the subject list. Nothing is hardcoded, so a skill that
# gains the helper gains the guard in the same commit.
carriers=$(ls -d "$REPO_ROOT"/skills/*/ | while read -r d; do
  [ -f "$d/scripts/ensemble-run-metrics" ] && printf '%s\n' "${d%/}"; done)
n=$(printf '%s\n' "$carriers" | grep -c . || true)
[ "$n" -ge 5 ] \
  && pass "found the skills that carry the run-metrics helper ($n)" \
  || fail "expected at least 5 carriers of ensemble-run-metrics, found $n"

for d in $carriers; do
  name=$(basename "$d")
  lifecycle_check "$d"
  [ "$LC_START" -ge 1 ] \
    && pass "$name opens a run" \
    || fail "$name carries ensemble-run-metrics but never calls start" \
            "its helpers will emit into no ledger and record nothing"
  [ "$LC_WRONG" -eq 0 ] && [ "$LC_NAMED" -ge 1 ] \
    && pass "$name records under its own name" \
    || fail "$name starts a run under the wrong skill name" \
            "--skill must be '$name'; a copied line records somebody else's run"
  [ "$LC_FINISH" -eq 1 ] \
    && pass "$name closes its run at exactly one place" \
    || fail "$name has $LC_FINISH finish call sites, expected 1" \
            "zero leaves a stale active entry that parents the next run; several are several terminal paths"
  [ "$LC_MARK" -ge 1 ] \
    && pass "$name states that every terminal path closes the run" \
    || fail "$name does not state the terminal-path contract" \
            "add the 'Every terminal path closes the run' sentence beside the finish call"
done

# --- the guard bites: three fixtures, one per assertion ----------------------
# A guard that cannot fail is decorative. Each fixture is a real skill body with
# one property broken; the check must reject it.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
fixture() {  # <name> <body>
  local d="$WORK/skills/$1"
  mkdir -p "$d/scripts"; : > "$d/scripts/ensemble-run-metrics"
  printf '%s\n' "$2" > "$d/SKILL.md"
  printf '%s\n' "$d"
}

good='2a. Start: `bash "$SKILL_DIR/scripts/ensemble-run-metrics" start --skill en-good`.
9. Close: `bash "$SKILL_DIR/scripts/ensemble-run-metrics" finish "$METRICS"`. **Every terminal path closes the run.**'
lifecycle_check "$(fixture en-good "$good")"
[ "$LC_START" -ge 1 ] && [ "$LC_FINISH" -eq 1 ] && [ "$LC_MARK" -ge 1 ] && [ "$LC_WRONG" -eq 0 ] \
  && pass "the reference fixture passes every check" \
  || fail "the reference fixture should pass" "start=$LC_START finish=$LC_FINISH mark=$LC_MARK wrong=$LC_WRONG"

# A terminal path that exits before the close: the bypass this exists to catch.
bypass='2a. Start: `bash "$SKILL_DIR/scripts/ensemble-run-metrics" start --skill en-bypass`.
5. On a failed check, stop and surface. Do not continue.
9. Close: report as usual. **Every terminal path closes the run.**'
lifecycle_check "$(fixture en-bypass "$bypass")"
[ "$LC_FINISH" -eq 0 ] \
  && pass "a skill that never calls finish is rejected" \
  || fail "a skill with no finish call should be rejected" "finish=$LC_FINISH"

# The contract sentence deleted, the calls intact.
noclaim='2a. `bash "$SKILL_DIR/scripts/ensemble-run-metrics" start --skill en-noclaim`.
9. `bash "$SKILL_DIR/scripts/ensemble-run-metrics" finish "$METRICS"`.'
lifecycle_check "$(fixture en-noclaim "$noclaim")"
[ "$LC_MARK" -eq 0 ] \
  && pass "a skill that drops the terminal-path contract is rejected" \
  || fail "a missing terminal-path sentence should be rejected" "mark=$LC_MARK"

# A copied start line recording somebody else's run.
copied='2a. `bash "$SKILL_DIR/scripts/ensemble-run-metrics" start --skill en-build`.
9. `bash "$SKILL_DIR/scripts/ensemble-run-metrics" finish "$METRICS"`. **Every terminal path closes the run.**'
lifecycle_check "$(fixture en-copied "$copied")"
[ "$LC_WRONG" -ge 1 ] \
  && pass "a start line naming another skill is rejected" \
  || fail "a mismatched --skill name should be rejected" "wrong=$LC_WRONG"

report
