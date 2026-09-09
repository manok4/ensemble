# The two-phase mutation protocol (EN08)

Read at the apply/surface step. `/en-review`'s SKILL.md carries the four rules that bind every mode; this file carries how each phase is actually performed, and the mechanics of the verification pass.

## Phase 1 — authorize, then baseline + freeze (before ANY edit)

Authorization comes FIRST, so the frozen set never changes after mutation begins.

0. **Any finding you do not understand stops the whole phase.** Before collecting authorizations, ask about every ambiguous candidate at once, what it means, what fix it implies, whether it holds for this codebase, and apply nothing until they are answered. Findings interact: a set frozen around a misreading is one the protocol below cannot unfreeze. In `headless` and `report-only` there is no one to ask, so an ambiguous finding is not authorized; it is surfaced unapplied with the ambiguity named.
1. **Collect ALL authorizations up front.** In `interactive` mode, surface every finding before touching anything: `gated_auto` announcements (user can decline) and `manual` picks are gathered NOW, not mid-run. In `headless` mode there is no user, so the authorized set is `safe_auto` findings ONLY. In `report-only` the authorized set is empty.
2. **Freeze one final authorized set**, the ONLY findings whose fixes may be applied this run, per the severity.md action matrix. A finding not in the frozen set is not applied this run, period; if the user wants more later, that is a NEW run with a new baseline.
3. **Capture the pre-review baseline** with a non-mutating snapshot that covers the **content of tracked AND untracked files**: a temporary-index tree (`GIT_INDEX_FILE=<tmp> git add -A && git write-tree` against a throwaway index) or a content-hash manifest over `git ls-files -co --exclude-standard`. `git status --porcelain` records that an untracked path exists, not its content, and `git stash create` does NOT preserve untracked content; without content coverage a review edit to a pre-existing untracked file cannot be told from the user's original work. Pre-existing dirty-tree changes belong to the user, never to the review.

## Phase 2 — apply within the frozen set

- In `interactive` mode: apply the frozen set (auto-tier `safe_auto`; `gated_auto` entries the user did not decline; `manual` entries the user explicitly picked in Phase 1). Re-verify after.
- In `headless` mode: apply `safe_auto` ONLY, silently; return the JSON envelope with all findings.
- In `report-only` mode: never apply anything; return JSON only.
- Stop before touching any finding or file outside the frozen set. Permitted auto-fixes per the severity.md matrix are in-contract; anything beyond them is *implementing*, which belongs to `/en-build` / `/en-resolve-pr`, not review.

**Record.** Derive `applied_fixes[]` from the ACTUAL before-vs-after tree delta (baseline vs post-review), excluding pre-existing changes, never from intent.

## The verification pass

**Previous-review context.** Write `<run-dir>/previous-review.md` from the envelope: each P0/P1 finding as `applied — verify the fix landed`, each P2/P3 as `deferred — do not re-flag`, with `finding_id`, severity, title and location. Pass it to `$SKILL_DIR/scripts/ensemble-build-peer-prompt` with `--iteration-context-file`; the peer reuses the original ids (`references/outside-voice.md`).

**Selecting the envelope under bare `--verify`.** Take the newest `/tmp/ensemble/en-review/*/envelope.json` whose `diff_base` matches the current target. None, or several candidates, is reported and the run stops rather than guessing which review is being verified.
