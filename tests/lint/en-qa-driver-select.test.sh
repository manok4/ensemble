#!/usr/bin/env bash
# tests/lint/en-qa-driver-select.test.sh
#
# D149. /en-qa can be told which browser to drive, and Playwright evidence is
# full size. A T3 Code preview pane drawn small produced blurry screenshots and
# video (2026-11-16), and the skill always preferred the host pane, so there
# was no way out of it. The flag and the qa_driver key are prose a model
# follows, pinned here; the key's resolution runs through en-qa's bundled
# ensemble-config-get with the arguments SKILL.md gives it, tested for real.
#
# Each path is overridable so a negative control can point the test at a
# scratch copy with a clause deleted and watch it go red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-qa driver select"

QA_SKILL="${QA_SKILL:-$REPO_ROOT/skills/en-qa/SKILL.md}"
QA_DRIVER="${QA_DRIVER:-$REPO_ROOT/skills/en-qa/references/browser-driver.md}"
QA_CONTRACT="${QA_CONTRACT:-$REPO_ROOT/skills/en-qa/CONTRACT.md}"
CONFIG_GET="${CONFIG_GET:-$REPO_ROOT/skills/en-qa/scripts/ensemble-config-get}"
FOUNDATION="${FOUNDATION:-$REPO_ROOT/docs/foundation.md}"
EXAMPLES="${EXAMPLES:-$REPO_ROOT/.ensemble/config.local.example.yaml $REPO_ROOT/skills/en-setup/references/templates/config-local-example.yaml}"

has() {  # $1=file  $2=fixed string  $3=label
  grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "'$2' not found in ${1#"$REPO_ROOT"/}"
}

# --- the choice: a flag beats the key, and a forced driver never falls back --
READ='ensemble-config-get" qa_driver --allowed auto,host,playwright --default auto --strict'
has "$QA_SKILL" "$READ" "step 5 reads qa_driver strictly, with auto as the default"
has "$QA_SKILL" '| `--driver <auto\|host\|playwright>` |' "the flags table lists --driver"
has "$QA_SKILL" "The flag beats the key" "the flag outranks the config key"
has "$QA_SKILL" "never falls back to another driver" "a forced driver that is missing does not fall back"
has "$QA_CONTRACT" '[--driver <auto\|host\|playwright>]' "the contract accepts --driver"
for ex in $EXAMPLES; do
  has "$ex" "# qa_driver: auto" "${ex#"$REPO_ROOT"/} documents qa_driver"
done

# --- Playwright evidence is full size ----------------------------------------
has "$QA_DRIVER" 'browser_resize({ width: 1280, height: 800 })' "Playwright sets a 1280x800 viewport before the first flow"
has "$QA_DRIVER" 'size: page.viewportSize()' "the screencast records at the viewport's size"
has "$QA_DRIVER" "800x800" "the reason for size is recorded"

# --- the key resolves through the bundled reader as step 5 calls it ----------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/.ensemble" "$TMP/home"
resolve() {  # prints the value; the exit code is the reader's
  bash "$CONFIG_GET" qa_driver --allowed auto,host,playwright --default auto --strict \
    --repo-root "$TMP/repo" --home "$TMP/home"
}
[ "$(resolve)" = auto ] && pass "an unset qa_driver resolves to auto" \
  || fail "an unset qa_driver resolves to auto" "got '$(resolve)'"
printf 'qa_driver: playwright\n' > "$TMP/repo/.ensemble/config.local.yaml"
[ "$(resolve)" = playwright ] && pass "a repo's qa_driver: playwright resolves" \
  || fail "a repo's qa_driver: playwright resolves" "got '$(resolve)'"
printf 'qa_driver: firefox\n' > "$TMP/repo/.ensemble/config.local.yaml"
if resolve >/dev/null 2>&1; then
  fail "an unknown qa_driver exits non-zero instead of reading as auto"
else
  pass "an unknown qa_driver exits non-zero instead of reading as auto"
fi

has "$FOUNDATION" '- **D149.' "the decision is recorded"

report
