#!/usr/bin/env bash
# tests/parity/shared-parity.test.sh
#
# EN12 U1. Skills are self-contained: each carries its own copy of anything it
# reads. Copies come from shared/ via scripts/sync-shared, and this guard is
# what makes duplication safe — without it the copies drift and "self-contained"
# becomes "silently inconsistent".
#
# Contract:
#   - a generated copy is byte-identical to its source, mode bits included
#   - generated-ness is recorded ONLY in shared/manifest.json; nothing is
#     injected into the file (an injected header would break byte parity by
#     construction, and above a shebang it would stop a script executing)
#   - a script entry carries its sourcing closure
#   - every bare-relative path a skill names resolves inside that skill
#   - a manifest grant nobody reads is a defect, so the manifest cannot rot

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="shared-tree parity"

SYNC="$REPO_ROOT/scripts/sync-shared"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# A throwaway repo shaped like the real one, so tests never touch the tree.
scaffold() {
  R="$WORK/r$1"; rm -rf "$R"
  mkdir -p "$R/shared/references" "$R/shared/bin" "$R/skills/en-alpha" "$R/skills/en-beta"
  printf -- '# host detect\n\nCanonical text.\n' > "$R/shared/references/host-detect.md"
  cat > "$R/shared/bin/tool-main" <<'INNER'
#!/usr/bin/env bash
# GENERATED-SOURCE NOTE lives in the canonical file, so it travels in the bytes.
set -u
_d="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_d/tool-helper"
echo "main-ran:$(helper_says)"
INNER
  cat > "$R/shared/bin/tool-helper" <<'INNER'
#!/usr/bin/env bash
helper_says() { echo "helper-ok"; }
INNER
  chmod +x "$R/shared/bin/tool-main" "$R/shared/bin/tool-helper"
  printf -- '---\nname: en-alpha\n---\nReads `references/host-detect.md` and runs `scripts/tool-main`.\n' > "$R/skills/en-alpha/SKILL.md"
  printf -- '---\nname: en-beta\n---\nReads `references/host-detect.md`.\n' > "$R/skills/en-beta/SKILL.md"
  cat > "$R/shared/manifest.json" <<'INNER'
{ "version": 1, "entries": [
  { "source": "references/host-detect.md", "dest": "references/", "skills": ["en-alpha", "en-beta"] },
  { "source": "bin/tool-main", "dest": "scripts/", "closure": true, "skills": ["en-alpha"] }
] }
INNER
}
sync()  { bash "$SYNC" --root "$R" "$@" >"$WORK/out" 2>&1; }
check() { bash "$SYNC" --root "$R" --check >"$WORK/out" 2>&1; }

# --- write mode ---
scaffold 1; sync; rc=$?
assert_exit_code 0 "$rc" "sync writes without error"
assert_file_exists "$R/skills/en-alpha/references/host-detect.md" "reference lands in en-alpha"
assert_file_exists "$R/skills/en-beta/references/host-detect.md"  "reference lands in en-beta"
assert_file_exists "$R/skills/en-alpha/scripts/tool-main"         "script lands in en-alpha"
assert_file_exists "$R/skills/en-alpha/scripts/tool-helper"       "closure sibling travels with it"

cmp -s "$R/shared/references/host-detect.md" "$R/skills/en-alpha/references/host-detect.md" \
  && pass "copy is byte-identical to source" || fail "copy is byte-identical to source"
[ -x "$R/skills/en-alpha/scripts/tool-main" ] \
  && pass "generated script keeps its executable bit" || fail "generated script keeps its executable bit"

# Direct execution, not `bash script`: that form hides both a lost exec bit and
# a shebang pushed off line 1 by an injected header.
out=$("$R/skills/en-alpha/scripts/tool-main" 2>&1)
assert_contains "$out" "main-ran:helper-ok" "generated script runs directly and finds its sibling"

head -1 "$R/skills/en-alpha/scripts/tool-main" | grep -q '^#!' \
  && pass "shebang is still line 1 (nothing injected)" || fail "shebang is still line 1 (nothing injected)"

check; assert_exit_code 0 $? "--check is clean right after a sync"
sync; check; assert_exit_code 0 $? "a second sync is a no-op and stays clean"

# --- drift ---
scaffold 2; sync
echo "hand edit" >> "$R/skills/en-alpha/references/host-detect.md"
check; rc=$?
assert_ne 0 "$rc" "a hand-edited generated copy fails --check"
out=$(cat "$WORK/out")
assert_contains "$out" "host-detect.md" "the drift report names the file"
assert_contains "$out" "sync-shared" "the drift report routes the author to the source, not a bare mismatch"

# --- skill-owned files are not drift ---
scaffold 3; sync
printf -- '# owned by en-alpha alone\n' > "$R/skills/en-alpha/references/local-only.md"
printf -- 'Also reads `references/local-only.md`.\n' >> "$R/skills/en-alpha/SKILL.md"
check; assert_exit_code 0 $? "a skill-owned file alongside generated ones is not drift"

# --- manifest hygiene ---
scaffold 4
perl -0pi -e 's/"en-beta"/"en-ghost"/' "$R/shared/manifest.json"
sync; rc=$?
assert_ne 0 "$rc" "a grant naming a nonexistent skill fails"
assert_contains "$(cat "$WORK/out")" "en-ghost" "the error names the missing skill"

scaffold 5
perl -0pi -e 's/Reads `references\/host-detect\.md`\.//' "$R/skills/en-beta/SKILL.md"
sync; check; rc=$?
assert_ne 0 "$rc" "a grant no skill reads fails, so the manifest cannot rot"
assert_contains "$(cat "$WORK/out")" "en-beta" "the unused-grant report names the skill"

# --- dangling relative reference ---
scaffold 6; sync
printf -- 'Also reads `references/never-synced.md`.\n' >> "$R/skills/en-alpha/SKILL.md"
check; rc=$?
assert_ne 0 "$rc" "a bare-relative path with no file behind it fails"
assert_contains "$(cat "$WORK/out")" "never-synced.md" "the dangling report names the path"

# --- the real tree ---
if [ -f "$REPO_ROOT/shared/manifest.json" ]; then
  bash "$SYNC" --root "$REPO_ROOT" --check >/dev/null 2>&1
  assert_exit_code 0 $? "the repo's own shared tree is in sync"
else
  pass "no shared/manifest.json in the repo yet — nothing to verify (U2 creates it)"
fi

report
