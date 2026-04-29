#!/usr/bin/env bash
# Frontmatter golden tests.
#
# For each artifact type, a `valid.md` fixture must lint clean (or only produce
# advisory P3 findings); each `invalid-*.md` fixture must produce at least one
# P1 finding mentioning the expected rule.
#
# The runner stages each fixture into a tempdir mimicking the real layout
# (docs/foundation.md, docs/architecture.md, docs/plans/active/FRXX-*.md, etc.)
# then runs `bin/ensemble-lint` against that tempdir.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="frontmatter goldens"

LINT="$REPO_ROOT/bin/ensemble-lint"

# Each entry: <fixture-relative-from-script-dir> <staged-path-in-tempdir> <expected-rule-or-empty>
# Empty expected-rule means "should lint clean".
fixtures=(
  "foundation/valid.md|docs/foundation.md|"
  "foundation/invalid-status.md|docs/foundation.md|frontmatter.invalid-enum"
  "foundation/invalid-depth.md|docs/foundation.md|frontmatter.invalid-enum"
  "foundation/invalid-date.md|docs/foundation.md|frontmatter.date-format"
  "architecture/valid.md|docs/architecture.md|"
  "architecture/invalid-status.md|docs/architecture.md|frontmatter.invalid-enum"
  "plan-active/valid.md|docs/plans/active/FR42-test.md|"
  "plan-active/invalid-missing-required.md|docs/plans/active/FR42-test.md|frontmatter.required-field-missing"
  "plan-active/invalid-status-mismatch.md|docs/plans/active/FR42-test.md|status.location-mismatch"
  "plan-completed/valid.md|docs/plans/completed/FR42-test.md|"
  "learning/valid.md|docs/learnings/patterns/test-2026-04-29.md|"
  "learning/invalid-category.md|docs/learnings/bugs/test-2026-04-29.md|frontmatter.invalid-enum"
  "learning/invalid-confidence.md|docs/learnings/bugs/test-2026-04-29.md|frontmatter.invalid-enum"
  "design/valid.md|docs/designs/2026-04-29-test-design.md|"
  "design/invalid-status.md|docs/designs/2026-04-29-test-design.md|frontmatter.invalid-enum"
  "agents-md/valid.md|AGENTS.md|"
  "claude-md/valid.md|CLAUDE.md|"
  "claude-md/invalid-no-cross-ref.md|CLAUDE.md|claude-md.no-cross-ref-line"
)

run_fixture() {
  local fixture_path="$1"
  local staged_path="$2"
  local expected_rule="$3"

  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  # Mock a docs/generated/ stub to satisfy index-coverage checks
  mkdir -p "$tmpdir/docs/generated"
  cat > "$tmpdir/docs/generated/plan-index.md" <<EOF
---
type: learning-index
generated: true
generator: en-learn
updated: 2026-04-29
total_entries: 0
---
EOF
  # When the fixture is a plan, also list it so index-coverage doesn't trip
  case "$staged_path" in
    docs/plans/*)
      printf -- '- [\x60%s\x60](../%s) — fixture\n' "$staged_path" "$staged_path" >> "$tmpdir/docs/generated/plan-index.md"
      ;;
    docs/learnings/*)
      cat > "$tmpdir/docs/generated/learning-index.md" <<EOF
---
type: learning-index
generated: true
generator: en-learn
updated: 2026-04-29
total_entries: 1
---
- [\x60$staged_path\x60](../$staged_path) — fixture
EOF
      ;;
  esac

  # Stage the fixture
  mkdir -p "$tmpdir/$(dirname "$staged_path")"
  cp "$SCRIPT_DIR/$fixture_path" "$tmpdir/$staged_path"

  # Run lint against the tempdir
  local output rc
  pushd "$tmpdir" >/dev/null
  output=$("$LINT" --scope docs/ 2>&1)
  rc=$?
  popd >/dev/null

  if [ -z "$expected_rule" ]; then
    # Should lint clean (no P1 findings); P2 freshness on architecture-30 is OK
    if [ "$rc" -eq 0 ]; then
      pass "$fixture_path lints clean"
    else
      # Check if the only output is a freshness P2 (acceptable for valid architecture fixtures)
      if echo "$output" | grep -qE 'P1' ; then
        fail "$fixture_path should lint clean" "got P1 finding(s): $(echo "$output" | grep 'P1' | head -1)"
      else
        pass "$fixture_path lints clean (only advisory findings)"
      fi
    fi
  else
    # Should fail with the expected rule
    if [ "$rc" -ne 0 ] && echo "$output" | grep -qF "$expected_rule"; then
      pass "$fixture_path triggers $expected_rule"
    else
      fail "$fixture_path should trigger $expected_rule" "rc=$rc, output: $(echo "$output" | head -3)"
    fi
  fi
}

for entry in "${fixtures[@]}"; do
  IFS='|' read -r fixture staged expected <<< "$entry"
  run_fixture "$fixture" "$staged" "$expected"
done

report
