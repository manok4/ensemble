# Migrating a legacy learning store

A repo that already holds entries under `docs/learnings/{bugs,patterns,decisions}/`
needs those entries moved before the new layout can be trusted. Until then the
store is split: the validator and `learnings-research` look at the new paths, and
whatever sits under the old ones is **invisible without being deleted** — the
worst failure a knowledge base has, because nothing announces it.

Run this when a retired directory is present. Everything below is one procedure;
the ordering is what makes it safe.

## 1. Preflight — inventory before anything moves

Build the full list of entries and their target paths **first**. Do not move
anything during this step.

Flattening three directories onto one collapses the namespace, so
`bugs/x-2026-01-01.md` and `patterns/x-2026-01-01.md` both target
`learnings/x-2026-01-01.md`. **An overwrite is never permitted.** When two
entries collide, keep both: give the second a disambiguating suffix and report
which entries were renamed and why. A migration that loses an entry has failed
even if it reports success.

Detect collisions by target basename across **all four** retired directories —
`bugs/`, `patterns/`, `decisions/`, and `sources/` — before the first move, not
as an error partway through. Three is the count of directories that become
*solutions*; `sources/` flattens to the same namespace and collides with them.

**Every legacy entry must have a unique resolved target before anything moves.**
At move time, refuse if the destination already exists — belt and braces, because
a preflight that missed a case must not become a silent overwrite.

## 2. Classify — legacy decisions become ADRs

The retired directories map onto artifact types, not onto one flat store:

| From | To | Why |
|---|---|---|
| `bugs/`, `patterns/` | `docs/learnings/<slug>-<date>.md` | Solved problems; solution shape |
| `decisions/` | `docs/decisions/NNNN-<slug>.md` | Decisions; ADR shape |
| `sources/` | `docs/learnings/<slug>-<date>.md` | Ingest was removed; nothing produces these any more |

**Legacy decisions become ADRs.** Flattening them into `docs/learnings/` would
preserve the files and destroy their artifact semantics, which is the entire
distinction this layout exists to draw. Converting one means giving it a number,
a title that states the claim, and an `## Invariants this creates` section —
read `adr-format.md`.

**A conversion that cannot be made confidently is surfaced rather than guessed.** An entry
whose type is genuinely ambiguous stays where it is and is reported for
classification. A wrong silent classification is the failure mode that loses
knowledge: the file survives, and it is filed as something it is not.

**`sources/` flattens too.** It held summaries of external material, and the
`ingest` mode that produced them was removed: a summary of something lookupable
is a second copy that goes stale and competes with the source it summarises.
Existing entries are not discarded — they move to the flat store as solutions,
with their `source_uri` kept in the body as a citation, so the **provenance
survives** even though the field does not. After migration there is one store,
not two.

## 3. Move — one entry at a time, restartable

For each entry, in order: move it, rewrite it, record it. Then the next.

**Rewrite every `related:` path that carries a category segment.** These embed
the old directory, so a move without a rewrite leaves every cross-reference
dangling. `learn-lint`'s `broken-links` check confirms the result.

**Transform the frontmatter per source directory.** "Strip `category`" is not
enough — legacy entries carry fields the schema retired at different times:

| Field | Action |
|---|---|
| `category` | remove (the directory it selected is gone) |
| `problem_type`, `component`, `confidence` | remove (retired from the schema) |
| `source_type`, `fetched` | remove |
| `source_uri` | move into the body as a citation line, then remove the field |
| `title`, `applies_when`, `date`, `tags`, `related`, `status` | keep |

An entry missing `applies_when` after transformation is **surfaced**, not
defaulted: it is the field retrieval depends on, and inventing one is worse than
reporting that a legacy entry never had it.

Validate every output against its target contract before the run reports success.

**Restartable by construction.** Because each entry is fully handled before the
next begins, an interrupt leaves every entry readable at exactly one path —
either its old one or its new one, never neither. The next run picks up what
remains.

## 4. Safety

**Refuses to start on a dirty working tree**, so the pre-migration state is a
commit you can return to.

`git checkout` alone is **not** a complete rollback: new ADRs and moved solutions
are untracked files, and checkout does not remove them. Recovery is
`git checkout -- . && git clean -fd docs/` — the clean is the half that matters,
and saying "git checkout is a complete rollback" would have sent someone into a
half-reverted tree believing it was clean.

Record each completed entry in a run manifest as it lands. A rerun reads the
manifest rather than inferring progress from which directories still exist, since
an entry can be moved but not yet rewritten.

**Idempotent.** A second run finds no retired directories and reports nothing to
do. Running it twice is a no-op, not a double-migration.

Remove a retired directory only **after** every entry under it is verified at its
new path. Their presence is what capture's legacy check keys on, so removing them
early makes an incomplete migration look finished.

**Interactive by default.** Ambiguous entries need a human. A non-interactive
invocation **refuses** unless explicitly flagged, because the alternative is
guessing at exactly the entries where guessing is most costly.

## 5. Until it completes, legacy paths stay validated

`ensemble-lint` keeps validating the retired paths while a retired directory
still exists: entries under them are **still validated until migration completes**. The switch-off is conditional on that repo's migration having
completed, not on this change having shipped.

Dropping the legacy rules on ship would make every un-migrated entry invisible to
lint and research in the window between upgrade and migration — which is the
failure this whole procedure exists to prevent, reintroduced by the fix.
