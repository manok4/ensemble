#!/usr/bin/env bash
# Drift guard for en-setup's State-2 retrofit install list.
#
# Field-observed bug: PolicyAsync project ran /en-setup but didn't get:
#   - bin/ensemble-lint (three sweep scripts were installed too until D101 retired the GitHub sweep)
#   - .gitignore entry for .ensemble/config.local.yaml
# Cause: the SKILL.md had no step that copied the project-local bin scripts
# from the plugin into the target repo, AND the .gitignore step was easy to
# drop in a long mechanical sequence with no end-of-run verification.
#
# These assertions make sure the spec stays comprehensive going forward.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-setup retrofit install list"

SKILL="$REPO_ROOT/skills/en-setup/SKILL.md"

# --- Sanity: skill file present ---
if [ -f "$SKILL" ]; then
  pass "skills/en-setup/SKILL.md present"
else
  fail "skills/en-setup/SKILL.md missing"
  report
fi

# --- The project-local bin script exists in the plugin source (so en-setup
#     has something to copy from). ensemble-lint is a template rather than a
#     bundled script: EN13 U8 made it a project deliverable. Until D101 three
#     sweep scripts were carried and installed too, for a GitHub workflow that
#     ran them by relative path; the sweep now runs from the skill directory on a
#     dedicated machine, and en-setup must NOT carry them any more. ---
if [ -f "$REPO_ROOT/skills/en-setup/references/templates/ensemble-lint" ]; then
  pass "en-setup carries ensemble-lint to install"
else
  fail "en-setup carries references/templates/ensemble-lint — nothing to copy"
fi
for gone in en-sweep-ci ensemble-sweep-activity-check ensemble-doc-only-check; do
  if [ -e "$REPO_ROOT/skills/en-setup/scripts/$gone" ]; then
    fail "en-setup no longer carries $gone (D101)"
  else
    pass "en-setup no longer carries $gone (D101)"
  fi
done
if [ -e "$REPO_ROOT/skills/en-setup/references/templates/github-workflow-en-sweep.yml" ]; then
  fail "the GitHub sweep workflow template is retired (D101)"
else
  pass "the GitHub sweep workflow template is retired (D101)"
fi

# --- SKILL.md has a step that installs the project-local bin scripts. ---
# Look for a heading or paragraph that mentions "Install project-local bin"
# or similar phrasing AND lists at least the four required scripts.
if grep -qE "Install (project-local|local) ?\`?bin" "$SKILL"; then
  pass "SKILL.md has a 'Install project-local bin' step"
else
  fail "SKILL.md missing the 'Install project-local bin' step (the bug fix)"
fi

if grep -qF "bin/ensemble-lint" "$SKILL"; then
  pass "SKILL.md mentions bin/ensemble-lint in the install list"
else
  fail "SKILL.md does not mention bin/ensemble-lint (must be in the install list)"
fi
for gone in en-sweep-ci ensemble-sweep-activity-check ensemble-doc-only-check; do
  if grep -qF "\`./bin/$gone\`" "$SKILL"; then
    fail "SKILL.md no longer installs ./bin/$gone (D101)"
  else
    pass "SKILL.md no longer installs ./bin/$gone (D101)"
  fi
done

# --- chmod +x is documented (scripts must be executable to be invoked). ---
if grep -qE "chmod \+x" "$SKILL"; then
  pass "SKILL.md documents chmod +x for installed bin scripts"
else
  fail "SKILL.md should mention chmod +x for the installed bin scripts"
fi

# --- .gitignore entry for .ensemble/config.local.yaml is mandatory and
#     verified after writing (not assumed). ---
if grep -qF ".ensemble/config.local.yaml" "$SKILL"; then
  pass "SKILL.md mentions .ensemble/config.local.yaml in .gitignore step"
else
  fail "SKILL.md missing .ensemble/config.local.yaml gitignore entry"
fi
if grep -qE "grep -qF '\.ensemble/config\.local\.yaml' \.gitignore" "$SKILL"; then
  pass "SKILL.md verifies .gitignore entry was actually written (post-write check)"
else
  fail "SKILL.md should verify the .gitignore entry exists after writing"
fi

# --- A final verification phase exists that walks every required artifact
#     and fails loudly if any are missing. This is the safety net for the
#     long mechanical sequence. ---
if grep -qE "[Ff]inal verification|[Vv]erification phase" "$SKILL"; then
  pass "SKILL.md has a final verification phase"
else
  fail "SKILL.md missing final verification phase (drops steps under context pressure)"
fi

# --- The verification table mentions each required artifact ---
# Scoped to the table. This grepped the whole SKILL.md, so every entry also
# matched the install steps that create the artifact — meaning none of these
# assertions could tell a present table row from an absent one. Removing a row
# left them all green.
TABLE=$(sed -n '/Required artifacts/,/Optional artifacts/p' "$SKILL")
# Fail loudly if the extraction found nothing: an empty TABLE would make every
# assertion below vacuously fail rather than silently pass, but a near-empty one
# is the dangerous case. Assert it actually captured rows.
table_rows=$(printf '%s' "$TABLE" | grep -c '^ *| ')
[ "$table_rows" -ge 10 ] \
  && pass "the verification table was extracted ($table_rows rows)" \
  || fail "the verification table was extracted" "found $table_rows rows"
# en-sweep.yml is no longer here: it moved from required to a recorded opt-in, so
# declining it reports as declined rather than as a missing required artifact.
# tests/lint/en-setup-scaffold.test.sh owns that classification.
for required in \
  "docs/plans/{active,completed}/" \
  "docs/learnings/" \
  "docs/decisions/" \
  "docs/CONTEXT.md" \
  "docs/learnings/{index.md,log.md}" \
  "docs/generated/{plan-index.md,learning-index.md}" \
  "AGENTS.md" \
  "CLAUDE.md" \
  "bin/ensemble-lint" \
  ".ensemble/config.local.example.yaml"; do
  if printf '%s' "$TABLE" | grep -qF "$required"; then
    pass "verification list includes: $required"
  else
    fail "verification list missing: $required"
  fi
done

# --- "Fail loudly" guidance present (don't silently mark missing artifacts as
#     skipped — surface to the user). ---
if grep -qE "[Ff]ail loudly|verification failed|Missing required artifacts" "$SKILL"; then
  pass "SKILL.md documents loud failure on missing required artifacts"
else
  fail "SKILL.md should document loud failure when verification finds missing artifacts"
fi

# --- Idempotency expectation is explicit ---
if grep -qE "[Ii]dempoten" "$SKILL"; then
  pass "SKILL.md documents idempotency expectation"
else
  fail "SKILL.md should explicitly state idempotency expectation"
fi

# --- The output-format example reflects the bin scripts (so report stays
#     accurate) ---
# The output example block lists target-repo files with a leading "  - ./bin/...". Match that.
if grep -qE "  - \./bin/ensemble-lint" "$SKILL"; then
  pass "output example lists ./bin/ensemble-lint in 'Created' section"
else
  fail "output example should list ./bin/ensemble-lint in 'Created' section"
fi

if grep -qE "[Ff]inal verification: [0-9]+ / [0-9]+ required" "$SKILL"; then
  pass "output example includes a 'Final verification: N / N' line"
else
  fail "output example should include a 'Final verification: N / N required artifacts present' line"
fi

# --- State-3 diagnostic mode reuses the verification list ---
if grep -qE "[Rr]equired-artifact verification|same table as State 2 step 17|State 2 step 17" "$SKILL"; then
  pass "State-3 diagnostic reuses the verification list (catches old retrofits)"
else
  fail "State-3 diagnostic should re-check the required-artifact list (so projects retrofitted before this fix can repair)"
fi

report
