#!/usr/bin/env bash
# tests/lint/skill-payload.test.sh
#
# EN13 U1. A skill should carry what it names and nothing else.
#
# EN12 seeded shared/manifest.json with a one-time script that granted a skill
# anything its files *mentioned*. Mentions are not dependencies: learn-lint.md
# names ensemble-lint in a sentence whose purpose is to say it is a DIFFERENT
# tool, and that one contrast pulled a 45KB script plus 56KB of its references
# into en-learn. Across the suite that inference left 422 payload files where
# 193 are named.
#
# ADVISORY UNTIL U2. This test reports the excess without failing, because U2
# requires the suite green after every per-skill batch and a test that is red by
# design cannot coexist with that. U2's final step flips ENFORCING to true. Same
# migration-aware shape EN12 used for the anchor guard: the guard works
# throughout the migration rather than being switched off for it.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="skill payload matches what each skill names"

# U2 flips this to true as its final step. Do not flip it early: the suite goes
# red for the whole migration and stops being a signal.
ENFORCING=false

# Files a skill needs = everything REACHABLE FROM SKILL.md, following read
# instructions transitively. Not "mentioned by anything the skill carries" —
# that is circular, and lets a file that should not be there justify another:
# architecture-fitness.md reads as needed because ensemble-lint names it, while
# ensemble-lint is itself unreachable. Rooting the walk at SKILL.md breaks the
# cycle, and it keeps the legitimate edges: recursion-guard reaches skills that
# never name it, via host-detect, which they do.
refs_in() {
  { grep -ohE '`(references|templates|agents|scripts)/[A-Za-z0-9._/-]+`' "$1" 2>/dev/null | tr -d '`'
    grep -ohE '\$SKILL_DIR/scripts/[A-Za-z0-9._-]+' "$1" 2>/dev/null | sed 's|.*/|scripts/|'
    grep -ohE '`[a-z-]+-(research|reviewer|simplifier)`' "$1" 2>/dev/null | tr -d '`' | sed 's|^|agents/|;s|$|.md|'
  } | grep -v '^references/X$' | sort -u
}

names_of() {
  local d="${1%/}" seen="" frontier
  frontier="$(refs_in "$d/SKILL.md")"
  while [ -n "$frontier" ]; do
    local next=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "
$seen" in *"
$f"*) continue ;; esac
      seen="$seen
$f"
      [ -f "$d/$f" ] || continue
      next="$next
$(refs_in "$d/$f")"
    done <<< "$frontier"
    frontier="$(printf '%s\n' "$next" | grep -v '^$' | sort -u || true)"
  done
  printf '%s\n' "$seen" | grep -v '^$' | sort -u
}

# Files a skill CARRIES, excluding its own entry points.
carries_of() {
  find "$1" -type f ! -name 'SKILL.md' ! -name 'CONTRACT.md' 2>/dev/null \
    | sed "s|^$1/||" | sort
}

total_excess=0
report=""
for d in "$REPO_ROOT"/skills/*/; do
  skill="$(basename "$d")"
  named="$(names_of "$d")"
  carried="$(carries_of "${d%/}")"
  # en-guardrail keeps its executables in bin/ rather than scripts/; those are
  # skill-owned, not granted, so they must not read as excess.
  excess="$(comm -23 <(printf '%s\n' "$carried" | grep -v '^$') <(printf '%s\n' "$named" | grep -v '^$'))"
  # `cmd && grep || cat` runs cat when grep merely matches nothing, so the
  # carve-out has to be a real branch.
  if [ "$skill" = "en-guardrail" ]; then
    excess="$(printf '%s\n' "$excess" | grep -v '^bin/' || true)"
  fi
  n=$(printf '%s\n' "$excess" | grep -c . || true)
  total_excess=$((total_excess + n))
  [ "$n" -eq 0 ] || report="$report  $skill: $n unnamed ($(printf '%s\n' "$excess" | head -2 | tr '\n' ' '))\n"
done

if [ "$ENFORCING" = "true" ]; then
  assert_eq "0" "$total_excess" "every skill carries only what it names"
  [ "$total_excess" -eq 0 ] || printf "%b" "$report" >&2
else
  pass "advisory mode — $total_excess unnamed file(s) across $(ls -d "$REPO_ROOT"/skills/*/ | wc -l | tr -d ' ') skills (U2 flips ENFORCING)"
  [ "$total_excess" -eq 0 ] || printf "%b" "$report" >&2
fi

# --- the scenarios the unit specified, on scaffolds rather than the live tree ---
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT INT TERM HUP
mk() { mkdir -p "$WORK/$1/references"; printf -- '---\nname: %s\n---\n%s\n' "$1" "$2" > "$WORK/$1/SKILL.md"; }

mk s1 'Reads `references/a.md`.'; : > "$WORK/s1/references/a.md"
assert_eq "" "$(comm -23 <(carries_of "$WORK/s1") <(names_of "$WORK/s1"))" "a skill naming exactly what it carries reports no excess"

mk s2 'Reads `references/a.md`.'; : > "$WORK/s2/references/a.md"; : > "$WORK/s2/references/stray.md"
assert_eq "references/stray.md" "$(comm -23 <(carries_of "$WORK/s2") <(names_of "$WORK/s2"))" "an unnamed file is reported, by name"

# A reference naming another reference is a real dependency edge.
mk s3 'Reads `references/a.md`.'; printf 'then read `references/b.md`\n' > "$WORK/s3/references/a.md"; : > "$WORK/s3/references/b.md"
assert_eq "" "$(comm -23 <(carries_of "$WORK/s3") <(names_of "$WORK/s3"))" "a file named only by another reference counts as named"

# The preamble placeholder is not a path.
mk s4 'All `references/X` paths resolve relative to $ENSEMBLE_ROOT.'
assert_eq "" "$(names_of "$WORK/s4")" "the references/X placeholder is not counted as a name"

report
