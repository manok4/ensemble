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

# Flipped to true by U2, which is where the tree first satisfies it. From here
# any unit that adds an undeclared file, or declares a deleted one, fails the
# suite at its own verification gate — that is what keeps the declarations
# maintained through U3 to U11 without relying on anyone remembering.
ENFORCING=true

# Files a skill needs = what it DECLARES in its `requires:` frontmatter.
#
# This replaced a reachability walk, and the walk is gone rather than kept as a
# cross-check: it was wrong in five distinct ways, each found only by deleting
# something. Full repo paths, the pre-EN12 `bin/X` alias, shell sourcing
# closures, cross-skill paths credited to the wrong skill, and — decisively —
# script COMMENTS naming references, which made en-ship read as clean while
# carrying 15 files it never names. Measured excess moved 98 -> 54 -> 14 as each
# was fixed. No regex reliably separates a dependency from a mention, so the
# skill states its own.
names_of() {
  local d="${1%/}"
  [ -f "$d/SKILL.md" ] || return 0
  awk '
    /^requires:/                        { inblock = 1; next }
    inblock && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); print; next }
    inblock && /^---[[:space:]]*$/       { exit }
    inblock && /^[A-Za-z_-]+:/          { exit }
  ' "$d/SKILL.md" | sort -u
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
  # No en-guardrail carve-out: it declares its own bin/ scripts like any other
  # skill declares its assets. The walker needed a special case; a declaration
  # does not.
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

# --- scenarios, on scaffolds rather than the live tree ---
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT INT TERM HUP
mk() {  # $1 skill, $2 declared paths (space-sep), $3.. files to create
  local s="$1" decl="$2"; shift 2
  mkdir -p "$WORK/$s/references"
  { printf -- '---\nname: %s\nrequires:\n' "$s"
    for r in $decl; do printf -- '  - %s\n' "$r"; done
    printf -- '---\nbody\n'
  } > "$WORK/$s/SKILL.md"
  for f in "$@"; do mkdir -p "$WORK/$s/$(dirname "$f")"; : > "$WORK/$s/$f"; done
}

mk s1 'references/a.md' references/a.md
assert_eq "" "$(comm -23 <(carries_of "$WORK/s1") <(names_of "$WORK/s1"))" "a skill carrying exactly what it declares reports no excess"

mk s2 'references/a.md' references/a.md references/stray.md
assert_eq "references/stray.md" "$(comm -23 <(carries_of "$WORK/s2") <(names_of "$WORK/s2"))" "an undeclared file is reported, by name"

# The point of declaring: a path mentioned in prose but not declared is still
# excess. Under the old walk this file counted as needed, which is how junk
# justified junk.
mk s3 'references/a.md' references/a.md references/mentioned.md
printf 'see `references/mentioned.md` for detail\n' >> "$WORK/s3/SKILL.md"
assert_eq "references/mentioned.md" "$(comm -23 <(carries_of "$WORK/s3") <(names_of "$WORK/s3"))" "a path mentioned in prose but not declared is still excess"

# A declaration naming a file that is not there is a typo, and must surface.
mk s4 'references/a.md references/ghost.md' references/a.md
assert_eq "references/ghost.md" "$(comm -13 <(carries_of "$WORK/s4") <(names_of "$WORK/s4"))" "a declared path with no file behind it is reported"

# Multi-line and nested paths parse.
mk s5 'references/a.md references/templates/t.md scripts/x agents/y.md' references/a.md references/templates/t.md scripts/x agents/y.md
assert_eq "" "$(comm -3 <(carries_of "$WORK/s5") <(names_of "$WORK/s5"))" "nested reference, script and agent paths all parse"

# The inference is gone, asserted structurally so it cannot creep back.
# Match code constructs, not the words — an earlier version grepped for its own
# pattern string and failed on itself.
# The character classes keep this pattern from containing the literals it
# searches for; two earlier versions matched themselves and failed on their own
# assertion line.
walker=$(grep -cE 'fronti[e]r=|re[f]s_in\(\)|reachabl[e]\(\)' "$SELF_DIR/skill-payload.test.sh" || true)
assert_eq "0" "$walker" "no path-walking code remains in this test"

# --- the declaration must be CLOSED ---
# A declared file naming an undeclared one is a hole: U2 deletes the target and
# the skill is left pointing at nothing. Found the hard way — en-debug declared
# agents/repo-research.md, which names references/research-dispatch.md, which
# was not declared. Closure is a consistency requirement on an explicit list,
# not a return to inference: it never decides what a skill needs, only that the
# list it wrote does not contradict itself.
open_gaps=""
for d in "$REPO_ROOT"/skills/*/; do
  skill="$(basename "$d")"
  declared="$(names_of "$d")"
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "${d%/}/$f" ] || continue
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      [ "$ref" = "references/X" ] && continue
      [ -f "${d%/}/$ref" ] || continue
      printf '%s\n' "$declared" | grep -qxF "$ref" || open_gaps="$open_gaps $skill:$f->$ref"
    done < <(grep -ohE '`(references|templates|agents|scripts)/[A-Za-z0-9._/-]+`' "${d%/}/$f" 2>/dev/null | tr -d '`' | sort -u)
  done <<< "$declared"
done
assert_eq "" "$(echo $open_gaps | cut -c1-160)" "every declaration is closed: no declared file names an undeclared one"

report
