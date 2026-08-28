#!/usr/bin/env bash
# tests/lint/grounding-validation.test.sh
#
# A written doc becomes trusted knowledge: future agents act on its claims without
# re-verifying them. This checks the claims against the tree before they compound.
#
# Unlike the specification tests elsewhere in EN14, these are behavioural — the
# script is deterministic, so the tests drive it against real fixtures and assert
# real output.
#
# Three exit codes, and the distinction is the point: 0 clean, 1 findings to
# adjudicate, 2 the validator could not run. Collapsing 1 and 2 would make "this
# doc has a dead link" indistinguishable from "nothing checked this doc".

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="grounding validation"

SCRIPT="$REPO_ROOT/skills/en-learn/scripts/ensemble-validate-claims"
REF="$REPO_ROOT/skills/en-learn/references/grounding-validation.md"
SKILL="$REPO_ROOT/skills/en-learn/SKILL.md"

assert_file_exists "$SCRIPT" "the grounding script exists"
assert_file_exists "$REF"    "the grounding reference exists"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/docs/learnings"

# Run the script from the repo root so repo-relative claims resolve.
run() { ( cd "$REPO_ROOT" && "$SCRIPT" "$1" 2>&1 ); }
code() { ( cd "$REPO_ROOT" && "$SCRIPT" "$1" >/dev/null 2>&1; echo $? ); }

doc() { printf '%s\n' "$2" > "$TMP/$1"; echo "$TMP/$1"; }

# --- clean doc ---------------------------------------------------------------
f=$(doc clean.md 'Cited `docs/foundation.md` exists.')
assert_eq "$(code "$f")" "0" "a doc citing only live paths exits 0"

# --- dead path ---------------------------------------------------------------
f=$(doc deadpath.md 'Cited `docs/does-not-exist-xyz.md` is gone.')
assert_eq "$(code "$f")" "1" "a dead path exits 1"
assert_contains "$(run "$f")" "does-not-exist-xyz" "the dead path is named in the finding"

# --- code fences are examples, not claims ------------------------------------
# A doc showing what a path looks like is not claiming that path exists.
# The fixture must contain something the extractor would OTHERWISE pick up.
# A bare path on a line is never extracted, so a fence around one proves nothing
# about masking — that fixture passed with masking disabled.
f=$(doc fenced.md '```
See [x](docs/example/not-real.md) and `docs/example/also-not-real.md`.
```
Body cites nothing.')
assert_eq "$(code "$f")" "0" "a link and a path inside a fence are not treated as claims"

# --- non-path backticks ------------------------------------------------------
# `true`, `P0`, `--json` are not paths. Flagging them would drown the real finding.
f=$(doc words.md 'Values `true`, `P0`, and `--json` are not paths.')
assert_eq "$(code "$f")" "0" "non-path backtick tokens are not flagged"

# --- links resolve from the DOCUMENT, not the repo root ----------------------
# Markdown semantics: a renderer resolves a relative link from the file it is in.
# Repo-root resolution accepts broken links and rejects valid ones, which is
# worse than not checking at all. Fixtures live in TMP so the repo is untouched.
mkdir -p "$TMP/docs/learnings"
: > "$TMP/docs/foundation.md"
printf '%s\n' 'See [foundation](../foundation.md).' > "$TMP/docs/learnings/nested.md"
assert_eq "$(code "$TMP/docs/learnings/nested.md")" "0" \
  "a relative link resolves from the document's own directory"

printf '%s\n' 'See [nope](../nope-xyz.md).' > "$TMP/docs/learnings/nested-bad.md"
assert_eq "$(code "$TMP/docs/learnings/nested-bad.md")" "1" \
  "a dead relative link from a nested document is flagged"

# The same target written from two depths must both resolve — this is the case a
# repo-root implementation gets wrong.
printf '%s\n' 'See [foundation](foundation.md).' > "$TMP/docs/shallow.md"
assert_eq "$(code "$TMP/docs/shallow.md")" "0" \
  "the same target from a shallower document also resolves"

# --- anchors -----------------------------------------------------------------
printf '%s\n' 'See [x](../foundation.md#section-11).' > "$TMP/docs/learnings/anchor.md"
assert_eq "$(code "$TMP/docs/learnings/anchor.md")" "0" \
  "an anchor on a live file is not a finding"

# --- external URLs are never fetched ----------------------------------------
# The network is not a correctness dependency.
f=$(doc ext.md 'See <https://example.invalid/nothing> and [y](https://example.invalid/z).')
assert_eq "$(code "$f")" "0" "external URLs are neither fetched nor flagged"

# --- SHAs --------------------------------------------------------------------
LIVE=$( cd "$REPO_ROOT" && git rev-parse --short HEAD )
f=$(doc sha_ok.md "Landed in \`$LIVE\`.")
assert_eq "$(code "$f")" "0" "a resolvable SHA is not flagged"

f=$(doc sha_bad.md 'Landed in `deadbee1`.')
assert_eq "$(code "$f")" "1" "an unresolvable hex token is reported"

# --- template leftovers ------------------------------------------------------
f=$(doc tmpl.md 'The slug is {{slug}}.')
assert_eq "$(code "$f")" "1" "an unrendered template placeholder is flagged"

# --- operational failure is NOT a finding ------------------------------------
# The case that would otherwise look identical to clean.
assert_eq "$(code "$TMP/no-such-file.md")" "2" "a missing input exits 2, not 0 or 1"
assert_contains "$( cd "$REPO_ROOT" && "$SCRIPT" 2>&1 || true )" "usage" \
  "invoked with no argument, it prints usage rather than a traceback"

# --- the reference states the adjudication contract --------------------------
flat() { tr '\n' ' ' < "$1" | sed 's/[*_`]//g; s/  */ /g'; }
# 'advisory' alone also matched prose elsewhere in the file, so deleting the
# rule left this green. Match the rule's substance: findings are adjudicated,
# never auto-applied.
flat "$REF" | grep -qi 'adjudicated, not auto-applied\|never a hard gate' \
  && pass "the reference says grounding is advisory, not a gate" \
  || fail "the reference says grounding is advisory, not a gate"
flat "$REF" | grep -qi 'merge-state\|remote' \
  && pass "the reference splits code-behaviour from merge-state claims" \
  || fail "the reference splits code-behaviour from merge-state claims"
flat "$REF" | grep -qE 'exit(ed)? 2|exit code 2' \
  && pass "the reference documents exit 2 as could-not-run" \
  || fail "the reference documents exit 2 as could-not-run"

grep -q 'scripts/ensemble-validate-claims' "$SKILL" \
  && pass "the script is declared in en-learn's requires:" \
  || fail "the script is declared in en-learn's requires:"
grep -q 'references/grounding-validation.md' "$SKILL" \
  && pass "the reference is declared in en-learn's requires:" \
  || fail "the reference is declared in en-learn's requires:"

# --- only CONCRETE FILE claims are checked -----------------------------------
# Dogfooding against this repo's own references showed the first cut flagged
# slash commands, placeholder paths, globs, and bare directories. A check that
# cries wolf gets ignored, so everything illustrative is excluded by shape.

f=$(doc slashcmd.md 'Run `/en-learn` then `/en-setup`.')
assert_eq "$(code "$f")" "0" "slash commands are not path claims"

f=$(doc placeholder.md 'Written to `docs/learnings/<slug>-<date>.md`.')
assert_eq "$(code "$f")" "0" "a path containing a placeholder is not a claim"

f=$(doc glob.md 'Carried by `skills/*/agents/*.md`.')
assert_eq "$(code "$f")" "0" "a glob is not a claim about one file"

f=$(doc bared.md 'Lives under `archive/` next to `lib/`.')
assert_eq "$(code "$f")" "0" "a bare directory is not a file claim"

f=$(doc noext.md 'See `docs/some/thing` for detail.')
assert_eq "$(code "$f")" "0" "a path with no extension is not a file claim"

# ...but a concrete dead file still is. The exclusions must not swallow the signal.
f=$(doc realdead.md 'See `docs/plans/active/EN99-nope.md`.')
assert_eq "$(code "$f")" "1" "a concrete dead file path is still reported"

# --- a template is allowed to contain placeholders ---------------------------
mkdir -p "$TMP/templates"
printf '%s\n' 'Slug is {{slug}}.' > "$TMP/templates/thing-template.md"
assert_eq "$(code "$TMP/templates/thing-template.md")" "0" \
  "a template file may contain unrendered placeholders"

# --- document-relative subpaths resolve --------------------------------------
# The live case for the document-relative fallback: a subpath that exists next to
# the document but not at the repo root. A bare filename never reaches it — the
# no-slash rule skips those first.
mkdir -p "$TMP/docs/templates"
: > "$TMP/docs/templates/thing.md"
printf '%s\n' 'See `templates/thing.md` for the shape.' > "$TMP/docs/has-subpath.md"
assert_eq "$(code "$TMP/docs/has-subpath.md")" "0" \
  "a document-relative subpath resolves from the document's directory"

f=$(doc barename.md 'See `capture-gate.md` for detail.')
assert_eq "$(code "$f")" "0" "a bare filename is not treated as a path claim"

report
