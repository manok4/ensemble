# Enforcement layers

Read when routing a correction: something an agent got wrong, a reviewer had to
point out, or a prose rule nothing checks. It decides where the fix for the
*next* occurrence belongs. Carried byte-identically by `/en-learn` and
`/en-sweep`; `tests/parity/enforcement-layers-parity.test.sh` pins both.

## The layers, strongest first

| Layer | Name | Test: the answer is yes |
|---|---|---|
| L1 | structure | Could a type, a module boundary or one paved path make the mistake impossible to write? |
| L2 | static | Could a lint rule, an invariant test, a compiler flag or a CI check reject it? |
| L3 | rules | Is it project knowledge an agent needs up front, in `AGENTS.md`, `CLAUDE.md` or `REVIEW.md`? |
| L4 | skill | Is it how a workflow step should run, in one skill's instructions? |
| L5 | prose | Only a reason, a history or a judgment that nothing above can hold. |

**The strongest layer that can express the correction wins.** Ask L1 first and
stop at the first yes. A rule written in `AGENTS.md` that a lint could check is
not enforced; it sits at L3 and routes to L2. Prose is the last answer, never the
default.

## A concrete check

L1 and L2 answers must name the check: `<path>: <rule or assertion>`, where
`<path>` is the file the check lives in and the text after the colon says what it
rejects. `tests/guard.sh:` alone, or "add a lint", is not a check.
`bin/ensemble-lint` rule `td.enforce-layer` rejects a tracker entry that lacks
one.

## Outcomes

- **L1 to L4:** file one TD entry proposing the change, through
  `scripts/ensemble-td-append`. Fields: `Enforce at:`, `Proposed check:` (L1 and
  L2), `Rule key:`. Read `ensemble-td-append --list-keys` first and reuse the key
  of an open entry that describes the same correction.
- **L5:** not a TD entry. It goes to `/en-learn`'s term, decision or solution
  routing, or to nothing when the capture gate says so.

**Routing proposes; it never applies.** No routing step edits a map file, a lint
config, a skill or a test. Building the check is ordinary work: the caller's
current branch when capture offers it, otherwise a plan citing the TD-ID.

## Rule keys

A kebab-case slug naming the correction, not its wording or location:
`no-orm-return-from-routes`, not `agents-md-line-39`. Two occurrences of the same
mistake share a key, so the appender files the second as a duplicate.

## Worked examples

- *"Never branch on `source_system == \"...\"`"* in Emble's `AGENTS.md`, checked
  by nothing. An AST scan can reject the comparison: **L2**,
  `backend/tests/test_architecture_invariants.py: forbid source_system equality
  comparisons outside integrations.resolve_integration`, key
  `no-source-system-branching`.
- *"A SKILL.md must stay under its byte budget"*, already rejected by
  `tests/lint/skill-size.test.sh`. Enforced at L2 already: **no entry**.
- *"Why TD-IDs are append-only"*: a reason, not a rule anything can check.
  **L5**, a decision learning.
