# Artifact types

`en-learn` writes three kinds of artifact. They are not three flavours of one
thing: they differ in **shape**, **lifecycle**, and **write path**, and that is
the whole reason the split is worth having.

The taxonomy this replaced — `bugs` / `patterns` / `decisions` / `sources` — had
no such property. All four produced the same file in a different directory, and
the boundary between a "pattern" and a "decision" was not one a writer could
apply twice the same way.

| Type | Path | Shape | Lifecycle |
|---|---|---|---|
| **Term** | `docs/CONTEXT.md` | An entry in one shared file: definition, retired synonyms | Amended in place; the file accretes |
| **Decision** | `docs/decisions/NNNN-<slug>.md` | Title states the claim; no frontmatter; invariants section | Append-only; amended by dated `## Update` sections |
| **Solution** | `docs/learnings/<slug>-<date>.md` | Six-field frontmatter; one paragraph until it earns more | Goes stale against the code; refreshed |
| *(ingested)* | `docs/learnings/sources/<slug>-<date>.md` | Solution shape plus `source_type` / `source_uri` / `fetched` | Written by `ingest`, not by capture |

## The gate runs first

The **capture gate** (`capture-gate.md`) decides *whether* anything is written.
This reference decides *which artifact*. That order matters: a router that ran
first would spend effort classifying candidates that should never have been
written at all, and the gate's default is to write nothing.

Only a candidate that has already passed the gate reaches the routing question.

## Routing

Ask what the candidate **is**, not what it is about.

- It says **what a word means in this codebase** → a **term**.
- It records **a choice between alternatives, and the rules that now hold** → a
  **decision**.
- It records **a solved problem whose lesson outlives the fix** → a **solution**.

### The tie-break: term > decision > solution

A candidate can honestly match two types. When it does, write the more durable
one:

```
term > decision > solution
```

The durable form outlives the occasion and can cite the other, so nothing is
lost by choosing it. The reverse is not true: a solution that quietly contained a
definition leaves the definition undiscoverable to anyone who was not reading
that solution.

Write **one** artifact, not both. Writing both and cross-linking reintroduces
exactly the duplication the gate's generalization step exists to prevent.

## Worked examples

Drawn from real captures in this repository.

### Routes to a term

> "A *carrier* is a skill that holds a byte-identical copy of a reference another
> skill also holds."

This is what a word means here. Nothing about it is a choice or a fix. It goes to
`docs/CONTEXT.md` with any retired synonyms on an `_Avoid:_` line.

### Routes to a decision

> "We chose explicit `requires:` declarations over inferring a skill's file set
> by walking references. Walkers produced five distinct classes of false edge,
> each found only by deleting something and seeing what broke."

A choice between alternatives, with a rule that now holds: every file a skill
reads is declared. It goes to `docs/decisions/` as a numbered ADR whose title
states the claim and whose invariants section names the rule.

Note the tie-break in action: this candidate also *defines* "declaration
closure". Term beats decision, so if the definition were the point, it would be a
term instead — and the decision would cite it.

### Routes to a solution

> "Peer review returned a well-formed `{"peer":"off"}` because `BASH_SOURCE` is
> unset under zsh, so a broken helper was indistinguishable from an unreachable
> peer."

A solved problem whose lesson — a helper that answers plausibly when broken is
worse than one that fails — outlives the fix. It goes to `docs/learnings/` as a
flat entry with `applies_when` carrying the retrieval weight.

## What is verified, and what is not

The routing rule above is executed by a model. The tests covering this file
assert that the **specification** is present and self-consistent: that each type
names its path, that the tie-break is an ordering rather than invertible prose,
and that the worked examples exist.

They do **not** show that a given candidate routes correctly. That is behaviour,
and no shell assertion reaches it. **TD7** tracks the eval suite that would; the
worked examples above are the corpus it will use.

Do not read a green test on this file as evidence that routing works.
