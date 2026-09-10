#!/usr/bin/env bash
# tests/lint/ensemble-scaffold.test.sh
#
# Six State-2 steps were ~2 KB of prose telling a model to run twenty commands
# whose arguments never vary. The skill's own final verification phase existed
# because of it: "long mechanical sequences drop steps under context pressure".
#
# What matters here is not that the scaffold creates things. It is that it
# NEVER TAKES ANYTHING THAT WAS NOT OFFERED:
#
#   AN EXISTING FILE IS NEVER OVERWRITTEN   a project's index.md, CONTEXT, or
#                                           .gitignore is the project's.
#   .gitignore IS APPENDED, NEVER REWRITTEN a scaffold that reformats it has
#                                           edited a file it was asked to add
#                                           one line to.
#   IDEMPOTENT BY CONSTRUCTION              a second run reports `exists` for
#                                           everything, which is what the prose
#                                           asked for six separate times.
#   FAILURE IS LOUD                         a missing template is a named
#                                           FAILED line and exit 1, not a gap
#                                           the verification phase finds later.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-scaffold"

S="$REPO_ROOT/skills/en-setup/scripts/ensemble-scaffold"
SK="$REPO_ROOT/skills/en-setup"
assert_file_exists "$S" "the scaffold exists"
[ -x "$S" ] && pass "the scaffold is executable" || fail "the scaffold is executable"

WORK=$(mktemp -d); trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
fresh() { d=$(mktemp -d "$WORK/rXXXXXX"); ( cd "$d" && git init -q . ) >/dev/null 2>&1; printf '%s' "$d"; }
run() { d="$1"; shift; OUT=$(bash "$S" --repo-root "$d" --skill-dir "$SK" "$@" 2>&1); RC=$?; }

# --- a fresh repo gets every artifact -----------------------------------------
D=$(fresh); run "$D"
assert_eq "0" "$RC" "a fresh repo scaffolds cleanly"
missing=""
for a in docs/decisions docs/plans/active docs/plans/completed docs/learnings \
         docs/generated docs/designs docs/learnings/index.md docs/learnings/log.md \
         docs/generated/plan-index.md docs/generated/learning-index.md \
         bin/ensemble-lint .ensemble/config.local.example.yaml .gitignore; do
  [ -e "$D/$a" ] || missing="$missing $a"
done
[ -z "$missing" ] && pass "every artifact the install promises is created" \
  || fail "an artifact was not created" "missing:$missing"
[ -x "$D/bin/ensemble-lint" ] && pass "bin/ensemble-lint is executable" \
  || fail "bin/ensemble-lint must be executable"
grep -qF '.ensemble/config.local.yaml' "$D/.gitignore" \
  && pass "the required gitignore entry is present and verified after writing" \
  || fail "the gitignore entry must be present"

# --- idempotent by construction ------------------------------------------------
run "$D"
assert_eq "0" "$RC" "a second run succeeds"
notexists=$(printf '%s\n' "$OUT" | grep -c 'created' || true)
assert_eq "0" "$notexists" "a second run creates nothing and reports exists for all"

# --- an existing file is never overwritten -------------------------------------
# The one that would lose a user's work. A project that already has learnings
# keeps them.
D=$(fresh); mkdir -p "$D/docs/learnings"
printf 'MY OWN NOTES\n' > "$D/docs/learnings/index.md"
run "$D"
assert_eq "MY OWN NOTES" "$(cat "$D/docs/learnings/index.md")" \
  "an existing seed file is preserved verbatim"
printf '%s\n' "$OUT" | grep -qE 'docs/learnings/index\.md +exists' \
  && pass "the preserved file is reported as exists, not silently skipped" \
  || fail "a preserved file must be reported"

# --- .gitignore is appended, never rewritten -----------------------------------
D=$(fresh); printf 'node_modules\ndist\n' > "$D/.gitignore"
run "$D"
head -2 "$D/.gitignore" > "$WORK/head"
assert_eq "node_modules
dist" "$(cat "$WORK/head")" "existing .gitignore lines are untouched and in order"
grep -qF '.ensemble/config.local.yaml' "$D/.gitignore" \
  && pass "the new entry is appended" || fail "the entry must be appended"

# A file with no trailing newline must not have its last line joined.
D=$(fresh); printf 'node_modules' > "$D/.gitignore"
run "$D"
grep -qxF 'node_modules' "$D/.gitignore" \
  && pass "a .gitignore with no trailing newline is not corrupted" \
  || fail "appending must not join onto an unterminated last line" "$(cat "$D/.gitignore")"

# --- the archive entry is opt-in ------------------------------------------------
D=$(fresh); run "$D"
grep -qF 'docs/learnings/archive/' "$D/.gitignore" \
  && fail "the archive entry must not be written without the flag" \
  || pass "the optional archive entry is not written by default"
D=$(fresh); run "$D" --ignore-learnings-archive
grep -qF 'docs/learnings/archive/' "$D/.gitignore" \
  && pass "--ignore-learnings-archive writes the optional entry" \
  || fail "the flag must write the optional entry"

# --- a drifted bin/ensemble-lint is re-synced, not reported as fine ------------
# It is a copy, so a plugin update leaves it stale; `exists` must mean identical.
D=$(fresh); run "$D"
printf 'stale\n' > "$D/bin/ensemble-lint"
run "$D"
cmp -s "$SK/references/templates/ensemble-lint" "$D/bin/ensemble-lint" \
  && pass "a drifted lint copy is refreshed on the next run" \
  || fail "a stale bin/ensemble-lint must be re-synced"

# --- failure is loud ------------------------------------------------------------
D=$(fresh); OUT=$(bash "$S" --repo-root "$D" --skill-dir "$WORK" 2>&1); RC=$?
assert_eq "1" "$RC" "a missing template exits non-zero"
printf '%s' "$OUT" | grep -qF 'FAILED' \
  && pass "the missing artifact is named as FAILED" \
  || fail "a failure must be reported per artifact"

# --- usage ----------------------------------------------------------------------
bash "$S" >/dev/null 2>&1; assert_eq "2" "$?" "missing arguments is a usage error"
bash "$S" --repo-root "$WORK" --skill-dir "$SK" --nonsense >/dev/null 2>&1
assert_eq "2" "$?" "an unknown argument is a usage error"

# --- the seeds match the formats that document them -----------------------------
# The script embeds the bodies; references/learn-*-format.md documents them. Two
# copies of a file format drift, so the frontmatter keys are checked against the
# reference rather than trusted.
D=$(fresh); run "$D"
for pair in "docs/learnings/index.md:learn-index-format.md:total_entries" \
            "docs/learnings/log.md:learn-log-format.md:type: learning-log"; do
  f=${pair%%:*}; rest=${pair#*:}; ref=${rest%%:*}; key=${rest#*:}
  if grep -qF "$key" "$D/$f" && grep -qF "$key" "$SK/references/$ref"; then
    pass "$f matches the format reference on: $key"
  else
    fail "$f drifted from references/$ref" "missing '$key' in one of them"
  fi
done

report
