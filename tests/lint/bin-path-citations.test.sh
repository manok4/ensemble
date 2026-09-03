#!/usr/bin/env bash
# tests/lint/bin-path-citations.test.sh
#
# A skill may cite `bin/<name>` for exactly the scripts /en-setup copies into
# the consuming project's bin/. Anything else it runs lives in its own
# scripts/ directory and must be cited as $SKILL_DIR/scripts/<name>.
#
# Written 2026-09-03. Eight names were cited 85 times as bin/ paths and existed
# at none of them: not at this repo's root, not installed project-local, not
# carried by any skill under bin/. Every one was present as scripts/<name> in
# the citing skill, so this was a stale prefix rather than missing payload,
# which is exactly why it survived: the file was always there to find, one
# directory over, and an agent that guessed correctly saw nothing wrong.
#
# The worst of them was bin/ensemble-detect-host, cited 33 times including
# "skills invoke bin/ensemble-detect-host as before, and the script handles
# caching transparently". A skill that gave up on that path and sourced the
# inline snippet in host-detect.md instead lost the recursion-guard
# short-circuit and the session cache, neither of which is in the snippet. It
# still worked, only slower, which is the kind of defect that never gets
# reported.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="bin path citations"

# The project-local set: the scripts /en-setup copies into the consuming repo's
# bin/ so .github/workflows/en-sweep.yml can reach them by relative path.
# Derived from en-setup's own verification table rather than hardcoded here, so
# adding a fifth does not need this file edited. That table is the list the
# install step is checked against, which makes it the closest thing to a
# declaration this repo has.
INSTALLED=$(grep -oE '`\./bin/[a-z][a-z0-9-]+`' "$REPO_ROOT/skills/en-setup/SKILL.md" \
            | tr -d '`' | sed 's|^\./bin/||' | sort -u | tr '\n' ' ')

n_installed=$(printf '%s' "$INSTALLED" | wc -w | tr -d ' ')
if [ "$n_installed" -lt 2 ]; then
  fail "en-setup must list the scripts it installs project-local" "found $n_installed"
else
  pass "en-setup lists $n_installed project-local scripts"
fi

# Every bin/ citation in skills/ must be either one of those, or a file the
# citing skill actually carries under its own bin/. en-guardrail is the only
# skill using bin/ rather than scripts/ for its own helpers, and its citations
# are correct as written.
#
# Shebangs are skipped: `#!/usr/bin/env bash` contains the literal `bin/env`,
# and the first draft of this guard reported it as a dangling citation.
bad=""
for d in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$d")
  # references/templates/ is excluded: those files configure the CONSUMING
  # project, so a bin/ path in them names a script in the user's repo (e.g.
  # `check_command: bin/check-fitness`), not one of this skill's.
  #
  # `_` belongs in the class. Without it the scan cut
  # bin/guardrail_analyze.py down to `guardrail`, then reported the truncation
  # as missing while the real file sat right there.
  cites=$(grep -rhoE --exclude-dir=templates '(^|[^/a-z])bin/[a-z][a-z0-9._-]+' "$d" 2>/dev/null \
          | sed 's|.*bin/||' | sort -u)
  for c in $cites; do
    [ "$c" = "env" ] && continue
    case " $INSTALLED " in *" $c "*) continue ;; esac
    [ -e "$d/bin/$c" ] && continue
    bad="$bad $name:$c"
  done
done
[ -z "$bad" ] \
  && pass "every cited bin/ path is installed project-local or carried under the skill's own bin/" \
  || fail "these bin/ paths resolve nowhere; cite them as \$SKILL_DIR/scripts/<name>" "$bad"

# The other half of the same claim: a script carried under scripts/ must not be
# cited with a bin/ prefix by the skill carrying it. The installed four are
# exempt because a skill legitimately runs both its own copy and the project's.
wrong=""
for d in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$d")
  for sc in "$d"scripts/*; do
    [ -f "$sc" ] || continue
    base=$(basename "$sc")
    case " $INSTALLED " in *" $base "*) continue ;; esac
    grep -rqF "bin/$base" "$d" 2>/dev/null && wrong="$wrong $name:$base"
  done
done
[ -z "$wrong" ] \
  && pass "no skill cites a script it carries under a bin/ prefix" \
  || fail "these are carried at scripts/ but cited at bin/" "$wrong"

# Every skill carrying an executable needs the anchor convention, or it cannot
# express the correct path at all. en-loop carried a script with no anchor block
# until 2026-09-03, which is how its host-detection reference kept naming a
# bin/ path unchallenged for 33 citations.
missing=""
for d in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$d")
  ls "$d"scripts/* >/dev/null 2>&1 || ls "$d"bin/* >/dev/null 2>&1 || continue
  grep -qF 'SKILL_DIR' "$d/SKILL.md" || missing="$missing $name"
done
[ -z "$missing" ] \
  && pass "every skill carrying an executable anchors it on \$SKILL_DIR" \
  || fail "a skill carrying executables must anchor them on \$SKILL_DIR" "$missing"

report
