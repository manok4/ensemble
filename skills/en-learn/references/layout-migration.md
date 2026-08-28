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

Detect collisions by target basename across all three retired directories before
the first move, not as an error partway through.

## 2. Classify — legacy decisions become ADRs

The retired directories map onto artifact types, not onto one flat store:

| From | To | Why |
|---|---|---|
| `bugs/`, `patterns/` | `docs/learnings/<slug>-<date>.md` | Solved problems; solution shape |
| `decisions/` | `docs/decisions/NNNN-<slug>.md` | Decisions; ADR shape |
| `sources/` | **untouched** | Ingested material, already correct |

**Legacy decisions become ADRs.** Flattening them into `docs/learnings/` would
preserve the files and destroy their artifact semantics, which is the entire
distinction this layout exists to draw. Converting one means giving it a number,
a title that states the claim, and an `## Invariants this creates` section —
read `adr-format.md`.

**A conversion that cannot be made confidently is surfaced rather than guessed.** An entry
whose type is genuinely ambiguous stays where it is and is reported for
classification. A wrong silent classification is the failure mode that loses
knowledge: the file survives, and it is filed as something it is not.

## 3. Move — one entry at a time, restartable

For each entry, in order: move it, rewrite it, record it. Then the next.

**Rewrite every `related:` path that carries a category segment.** These embed
the old directory, so a move without a rewrite leaves every cross-reference
dangling. `learn-lint`'s `broken-links` check confirms the result.

Strip `category:` from the frontmatter of every migrated solution. The remaining
six fields are unchanged.

**Restartable by construction.** Because each entry is fully handled before the
next begins, an interrupt leaves every entry readable at exactly one path —
either its old one or its new one, never neither. The next run picks up what
remains.

## 4. Safety

**Refuses to start on a dirty working tree.** With a clean tree, `git checkout`
is a complete rollback, so no bespoke undo is needed. This is why the procedure
does not implement one.

**Idempotent.** A second run finds no retired directories and reports nothing to
do. Running it twice is a no-op, not a double-migration.

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
