# What a good test is

Read this before writing a unit's tests. The plan decides **where** to test
(`/en-plan` picks the seams, and its three rules govern that choice); this file
decides **what** the test at that seam is worth.

A good test verifies behaviour through the public interface, not the
implementation behind it. The implementation can change entirely and the test
should not. It reads like a specification: "user can check out with a valid
cart" names a capability, and it survives a refactor because it never looked
inside.

One logical assertion per test. The name says WHAT, not HOW.

## Anti-patterns, each with its tell

- **Implementation-coupled.** Mocks an internal collaborator, tests a private
  method, or verifies through a side channel: querying the database directly
  instead of calling the interface that reads it back. *The tell: a refactor
  that changes no behaviour turns the test red.*

- **Tautological.** The expected value is computed the way the code computes it,
  so the test passes by construction and can never disagree with the code.
  Expected values come from an independent source: a known-good literal, a
  worked example, the spec. *The tell: you could delete the expected value and
  re-derive it from the function under test.*

- **Horizontal slicing.** All the tests first, then all the implementation. Bulk
  tests verify imagined behaviour, commit to a test structure before the
  implementation has taught you anything, and go insensitive to real change.
  Work in vertical slices: one test, one implementation, repeat. *The tell: a
  test file is complete before any of its subject exists.*

- **Reads source instead of running it.** The only evidence is that the test
  opened, grepped, parsed or snapshotted implementation source and found
  particular strings, tokens or function names. Matched text can be dead or
  commented out, and a behaviour-preserving refactor breaks the test while the
  behaviour holds. *The tell: the assertion would still pass if the matched code
  were commented out.* **Two carve-outs:** a file that is itself generated
  output, a serialized protocol, persisted state or a deliberate snapshot is a
  real contract and may be read, so name the contract; and a declarative
  artifact a machine consumes (workflow YAML, JSON policy, generated config) may
  be parsed into a typed model and asserted on meaning, though a raw substring
  match over it is still the anti-pattern.

- **Mocked past the boundary.** Mock at system boundaries only: external APIs,
  clocks, randomness, sometimes the database. Never your own modules, and never
  an internal collaborator. *The tell: the mock has to change when you rename an
  internal function.*

## Two worked pairs

Expected values come from outside the implementation:

```ts
// BAD: recomputes the implementation, so it cannot disagree with it
const expected = items.reduce((sum, i) => sum + i.price, 0);
expect(calculateTotal(items)).toBe(expected);

// GOOD: an independent literal
expect(calculateTotal([{ price: 10 }, { price: 5 }])).toBe(15);
```

Verification goes through the interface, not around it:

```bash
# BAD: greps the source for the behaviour it hopes exists
grep -q 'set -euo pipefail' ./deploy.sh

# GOOD: runs it and asserts what happened
out=$(./deploy.sh --dry-run 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'refusing: dirty tree'
```

## Where this is also stated, and why

`/en-review`'s peer brief carries the same anti-patterns as rubric rows. That duplication is deliberate: the peer runs as a subprocess and
is given the brief's text as its prompt, so a pointer to this file would be a
pointer it cannot follow. The two are kept in step by
`tests/lint/good-tests-reference.test.sh`, which fails when one names an
anti-pattern the other does not.

Prior art: the implementation-coupled, tautological and horizontal-slicing
framing, and the "tell" device, are adapted from Matt Pocock's `tdd` skill
(MIT). The source-reading anti-pattern and its carve-outs are Ensemble's own.
