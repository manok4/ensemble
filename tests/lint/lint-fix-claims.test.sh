#!/usr/bin/env bash
# tests/lint/lint-fix-claims.test.sh
#
# `bin/ensemble-lint --fix` regenerates docs/generated/plan-index.md and nothing
# else, and the lint reads no configuration. The docs, the config examples and the
# lint's own summary used to promise more, so an agent ran --fix and expected its
# other findings to be gone.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="lint --fix claims"

LINT="$REPO_ROOT/skills/en-setup/references/templates/ensemble-lint"
DOC="$REPO_ROOT/skills/en-sweep/references/doc-lints.md"
section() { awk -v h="## $1" '$0==h{f=1; next} f&&/^## /{exit} f' "$DOC"; }

# --- the summary does not offer a fix the lint cannot make ---
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
mkdir -p "$WORK/docs/plans/active"
printf '# No frontmatter\n' > "$WORK/docs/plans/active/EN01-x.md"
out=$(cd "$WORK" && bash "$LINT" --scope docs/ 2>&1)
assert_contains "$out" "High (P1):** 1" "the fixture raises a P1 finding"
assert_not_contains "$out" "auto-apply mechanical fixes" \
  "the summary does not send a P1 the lint cannot fix to --fix"

# --- the catalog lists only the repair --fix makes ---
autofix=$(section 'Auto-fix behavior')
assert_contains "$autofix" "docs/generated/plan-index.md" "the catalog names the plan-index repair"
for claim in 'Repair broken cross-links' 'placeholder values' 'Sync `status:`' \
             'by prepending the line' 'Bump `updated:`'; do
  assert_not_contains "$autofix" "$claim" "the catalog does not claim --fix does: $claim"
done
assert_not_contains "$(cat "$DOC")" "auto-apply mechanical fixes" \
  "the sample summary matches the lint's"

# --- no config key the lint never reads ---
for f in "$DOC" "$REPO_ROOT/skills/en-setup/references/templates/config-local-example.yaml" \
         "$REPO_ROOT/.ensemble/config.local.example.yaml"; do
  for key in fix_skip_rules scope_default; do
    grep -qF "$key" "$f" && fail "${f#"$REPO_ROOT"/} does not document lint.$key" \
      || pass "${f#"$REPO_ROOT"/} does not document lint.$key"
  done
done

report
