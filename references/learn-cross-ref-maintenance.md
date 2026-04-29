# Cross-reference maintenance — the always-on behavior

Whenever `en-learn capture` or `en-learn ingest` writes a new entry to the wiki, it walks the `related: [...]` field and **adds reciprocal back-references** to every cited page. Forward references without back-references leave the graph one-directional and orphans accumulate.

This is what makes the learning store an actual interlinked wiki rather than a folder of frontmatter files.

## The procedure

After writing the new entry at `docs/learnings/<category>/<slug>-<date>.md`:

1. Read the new entry's `related: [...]` field.
2. For each path in `related`:
   - Open the related file.
   - If its `related:` field already contains the new entry's path, skip.
   - Otherwise, append the new entry's path to its `related:` array.
   - Bump the related file's `updated:` timestamp if present (some categories track it; others use only `date:`).
3. Save the related file.

When a related file would benefit from more than just a back-link — for example, the new entry contradicts an earlier claim, or strengthens it with a new example — surface a one-line note:

> "I've added a back-ref from `<related-path>` to the new entry. The new finding *contradicts* a claim in that page (line N: `<excerpt>`). Open that page and reconcile?"

The user decides whether to reconcile now or defer.

## Edge cases

| Case | Behavior |
|---|---|
| Related file doesn't exist | Log a warning; skip; flag for `--lint` (broken link) |
| Related file is in `archive/` | Add the back-ref anyway, but note in the new entry that the related is archived |
| Related file's frontmatter is malformed | Log a warning; skip the back-ref; flag for `--lint` |
| New entry's `related:` is empty | Skip walking; just write the entry |
| Circular back-ref (A relates to B, B already relates to A) | Idempotent; the check above prevents duplicates |

## Why "active" — not just "passive recording"

The wiki only stays interlinked if every write does the bookkeeping. Humans abandon wikis because the bookkeeping outpaces the value (Karpathy's observation). LLMs don't get bored — they touch 15 files in one pass — so the bookkeeping cost is near-zero and the wiki actually stays maintained.

The cost is real but bounded:

- Most entries `related:` 0–5 other pages.
- Each back-ref edit is one frontmatter mutation.
- Total: 0–5 file edits per `capture`/`ingest`. Cheap.

## Companion checks (`--lint`)

`en-learn --lint` validates the graph integrity:

- **Missing back-refs.** A.related contains B but B.related doesn't contain A. Auto-fix: add the missing back-ref. Always cheap.
- **Orphans.** Page with zero inbound references. Surface for human attention; might be intentional (a unique decision), might be a write-bug.
- **Broken links.** A.related points to a path that no longer exists. Auto-fix when the moved-to path is obvious; surface when not.
- **Index drift.** `index.md` and the underlying pages drift apart. Auto-fix: regenerate `index.md` from the pages.

See [`learn-lint.md`](./learn-lint.md) for the full check catalog.

## Failure protocol

If the cross-ref pass fails partway through (e.g., a related file is locked, a path is malformed):

1. The new entry **stays written** — don't roll back the primary write.
2. Surface the partial-failure to the user with the list of files that didn't update.
3. Add a `log.md` entry: `## [YYYY-MM-DD] capture-with-partial-back-ref-failure | <subject>`.
4. `--lint` will catch the missing back-refs on the next run and offer to fix.

The principle: **the primary write succeeds atomically; bookkeeping is best-effort and self-healing via `--lint`.**
