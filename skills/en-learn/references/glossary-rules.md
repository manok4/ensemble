# Glossary rules — `docs/CONTEXT.md`

`docs/CONTEXT.md` defines the words that mean something specific in this
codebase. It is substrate: solutions, decisions, and `AGENTS.md` can use these
terms without redefining them.

It earns its place because it holds what the code cannot. A reader can recover
*what the code does* by reading it. They cannot recover which of three synonyms
the team settled on, what the losing words were, or which ambiguity was resolved
— the rejected options are not in the tree. That is the same test the capture
gate applies, and vocabulary passes it cleanly.

## How terms enter: accretion and seeding

Two paths, covering different gaps.

**Accretion** — a capture surfaces a term whose meaning was not obvious, so it
gets defined. This reliably catches *peripheral* terms, because friction is what
surfaces them.

**Seeding** — a run proactively defines the **core domain nouns** of the area it
is working in. This catches the *stable-central* terms accretion never reaches:
the nouns a system is built around rarely break, so they rarely appear in a
learning, yet they are exactly what a reader needs to orient.

Without seeding the file fills with peripheral mechanics and never names what the
project is about. Without accretion it goes stale the moment the domain moves.

**What bounds a seed** is the **source** — the declared domain model of the area
in scope (schema, core types, primary models, top-level domain docs) — and the
**bar** below. Never a target count. A small domain yields a few terms; a large
one, more. Do not add a term to reach a number, and do not reach outside the area
in scope to inflate one.

A **scoped run** (a capture, or a refresh narrowed to an area) seeds only that
area's nouns. A **repo-wide bootstrap** — an explicit request to create the file
— seeds the whole project's declared domain model. Only the bootstrap can produce
a coherent "what is this project" glossary; a scoped run should not pretend to.

## Be opinionated

When the team uses several words for one concept, **pick the best one and retire
the rest**. Record the retired words as an `_Avoid:_` line directly under the
definition:

```
### Carrier
A skill that holds a byte-identical copy of a reference another skill also holds.
_Avoid:_ owner, host, copy-holder
```

The glossary is not a record of every word anyone has used. It is the team's
agreed vocabulary, and a file that declines to choose leaves the reader exactly
where they started.

## The file stands on its own

Each entry teaches its concept to a reader with no access to anything else: no
codebase, no PR history, no meetings, no chat. That rules out:

- **File paths, class names, function signatures, table names** — implementation,
  not meaning, and it moves.
- **Dates and owners** on entries.
- **Version-specific claims** ("currently uses X, migrating to Y").
- **Links to PRs, issues, or milestones.**
- **Current-config values** — specific thresholds, counts, enum values. **State
  the behavior, not the number:** "each skill sets its own threshold", never
  "surfaces at 50".

Cross-references *between entries* are fine; they resolve inside the file. But if
an entry leans on another **project-specific** term to make sense, that term
belongs here too — an undefined project-specific sibling is itself a candidate.

## What earns a slot

A term qualifies when its meaning here is precise enough that **a new engineer
would need it defined** to follow conversations, tickets, or code.

**General programming vocabulary does not belong**, however heavily it is used.
Caches, queues, jobs, and sessions need no redefinition, and neither does
everyday domain English.

## Per entry

The definition is **one sentence**: what the term means in this domain, and what
distinguishes it from its neighbours. A term with non-obvious behavioural rules
(lifecycle, ownership, cancellation semantics) earns a second paragraph for those
rules — never for elaborating the definition itself.

## Relationships (optional)

When relationships between entries carry load-bearing meaning — ownership,
cardinality, lifecycle dependencies spanning entries — capture them in a
`## Relationships` section. Skip it when entries stand alone. This is a lift for
domains where structure is part of what makes the terms meaningful, not a routine
section.

## Organization

Cluster by domain relationship — entities with their states, processes with their
stages — so a reader sees structure without effort. A flat list is fine while the
file is small. Reshape as it grows.

## Flagged ambiguities (tail of the file)

When two terms were used interchangeably and the team settled on a distinction,
record the resolution as a one-line note:

> "'account' had been used for both Customer and User — these are distinct."

This section is the **audit trail for opinions the team has formed**. It is the
part of the file that is most impossible to reconstruct from anything else, and
the first thing a newcomer needs when they find two words for one idea.

## What is verified

Writing an entry is model behaviour. The tests over this file assert that these
rules are present and that the template carries the ambiguities tail. They do not
show that a written entry is correct, that a duplicate is caught, or that an
amendment preserves unrelated entries. **TD7** tracks that gap.
