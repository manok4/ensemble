#!/usr/bin/env bash
# Drift guard for en-setup's State-2 retrofit install list.
#
# Field-observed bug: PolicyAsync project ran /en-setup but didn't get:
#   - bin/{en-sweep-ci, ensemble-sweep-activity-check, ensemble-doc-only-check, ensemble-lint}
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
WORKFLOW_TPL="$REPO_ROOT/references/templates/github-workflow-en-sweep.yml"

# --- Sanity: skill file present ---
if [ -f "$SKILL" ]; then
  pass "skills/en-setup/SKILL.md present"
else
  fail "skills/en-setup/SKILL.md missing"
  report
fi

# --- Each project-local bin script exists in the plugin source (so en-setup
#     has something to copy from). The bug was that en-setup didn't copy them;
#     this also catches the case where someone deletes them from the plugin. ---
for script in en-sweep-ci ensemble-sweep-activity-check ensemble-doc-only-check ensemble-lint; do
  if [ -f "$REPO_ROOT/bin/$script" ]; then
    pass "plugin source has bin/$script"
  else
    fail "plugin source missing bin/$script — en-setup has nothing to copy"
  fi
done

# --- The en-sweep workflow template references the bin scripts that
#     en-setup MUST install (regression: if the workflow template stops
#     referencing them, en-setup may stop installing them, but if it still
#     references them and en-setup skips the install, CI will fail). ---
for script in en-sweep-ci ensemble-sweep-activity-check; do
  if grep -qF "bin/$script" "$WORKFLOW_TPL"; then
    pass "en-sweep workflow template references bin/$script"
  else
    fail "en-sweep workflow template no longer references bin/$script (or template moved)"
  fi
done

# --- SKILL.md has a step that installs the project-local bin scripts. ---
# Look for a heading or paragraph that mentions "Install project-local bin"
# or similar phrasing AND lists at least the four required scripts.
if grep -qE "Install (project-local|local) ?\`?bin" "$SKILL"; then
  pass "SKILL.md has a 'Install project-local bin' step"
else
  fail "SKILL.md missing the 'Install project-local bin' step (the bug fix)"
fi

for script in en-sweep-ci ensemble-sweep-activity-check ensemble-doc-only-check ensemble-lint; do
  if grep -qF "bin/$script" "$SKILL"; then
    pass "SKILL.md mentions bin/$script in the install list"
  else
    fail "SKILL.md does not mention bin/$script (must be in the install list)"
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
for required in \
  "docs/plans/{active,completed}/" \
  "docs/learnings/{bugs,patterns,decisions,sources}/" \
  "docs/learnings/{index.md,log.md}" \
  "docs/generated/{plan-index.md,learning-index.md}" \
  "AGENTS.md" \
  "CLAUDE.md" \
  ".github/workflows/en-sweep.yml" \
  "bin/en-sweep-ci" \
  "bin/ensemble-sweep-activity-check" \
  "bin/ensemble-doc-only-check" \
  "bin/ensemble-lint" \
  ".ensemble/config.local.example.yaml"; do
  if grep -qF "$required" "$SKILL"; then
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
for script in en-sweep-ci ensemble-sweep-activity-check ensemble-doc-only-check ensemble-lint; do
  # The output example block lists files with a leading "  - bin/...". Match that.
  if grep -qE "  - bin/$script" "$SKILL"; then
    pass "output example lists bin/$script in 'Created' section"
  else
    fail "output example should list bin/$script in 'Created' section"
  fi
done

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
