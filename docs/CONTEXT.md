# Domain vocabulary

Words that mean something specific in Ensemble. Each entry teaches its concept to
a reader with no access to the codebase, so nothing here names a file, a function,
or a current configuration value.

Seeded 2026-08-28 by `/en-setup` from the declared domain model. Terms accrete
from `/en-learn capture` as work surfaces them.

## Work items

### Plan
A peer-reviewed description of a change, broken into units, that `/en-build`
executes. Carries a stable `<PREFIX><NN>` id assigned at creation and never
reused. A plan is the unit of authorization: approving it authorizes every unit
inside it, which is why the build does not stop to ask between units.
_Avoid:_ ticket, story, spec

### Unit
One logical change inside a plan — reviewable and committable on its own,
identified by a **U-ID** (`U1`, `U2`, …). U-IDs are assigned once and never
renumbered, so a unit added after the fact takes the next free number rather than
slotting into position. A unit carries its own risk class and test scenarios.

### Requirement
A numbered capability the product must have, identified by an **R-ID** and
declared in the foundation. Units cite the R-IDs they cover, which is how a
finished plan is checked against what was actually asked for.

### Tech debt item
A known defect or gap recorded rather than fixed, identified by a **TD** number.
Filing one is a decision to defer with the reasoning attached — distinct from
leaving a problem unrecorded, which is how it gets rediscovered.

## Review

### Outside Voice
Review of an artifact by a **different model architecture** from the one that
produced it, so the reviewer never saw the reasoning that made the work look
right. The property being bought is independence, not a second opinion: a
same-model reviewer tends to share the blind spot that created the defect.
_Avoid:_ second pass, AI review

### Peer
The agent performing an Outside Voice review. Cross-agent when a different CLI is
installed; a fresh subprocess of the host's own CLI when not, which preserves
fresh context but not architectural independence, and is recorded as a fallback
rather than treated as equivalent.

### Peer brief
The per-skill instructions telling a peer what to look for in one artifact kind —
plan review differs from code review. Distinct from the peer **contract**, which
defines the wire format every review returns regardless of what it reviewed.

### Persona
A review dimension: correctness, testing, maintainability, standards, security,
performance, migrations. A persona describes what to examine, not who examines it.

### Finding
One defect a review reports, graded **P0**–**P3** and carrying a confidence. A
finding is resolved by being applied, deferred, disagreed with, or superseded —
and a disagreement must record its reasoning, so declining is a decision rather
than an omission.

### Gate
A check that stops work when it fails. A gate that cannot fail is decorative, so
each one is proven by breaking what it protects and confirming it goes red.

## Captured knowledge

### Artifact type
Which of three forms a captured learning takes: a **term**, a **decision**, or a
**solution**. The three differ in shape, lifecycle, and where they are written —
that difference is what makes the split worth having. A candidate matching two
types is written as the more durable one and cites the other.

### Capture gate
The test a candidate learning must pass before anything is written: not
recoverable from the code, changes a future action, outlives the occasion. The
default is to write nothing. Its premise is that agents read code well, so a
store restating what the code already says makes the next reader do more work for
less.

### Term
A word that means something specific in this codebase, defined once in the shared
glossary. Terms accrete during capture and are seeded during setup, because the
nouns a system is built around rarely break and so rarely surface on their own.

### Decision
A choice, its reasoning, and the rules that now hold because of it. Append-only:
amended in place with a dated update, and superseded only when the decision
itself is reversed — the original is never rewritten, because a decision with no
trace of its reasoning is how the same argument gets had twice.

### Solution
A solved problem whose lesson outlives the fix. The shortest-lived of the three:
it describes code, and code moves.

### Grounding
Checking a written artifact's cited paths, links, and commits against the tree
before it is indexed. Advisory rather than blocking, because a solution
legitimately cites something the fix deleted.

## Structure

### Skill
A self-contained directory holding everything one command needs — instructions,
references, agents, scripts. Self-contained means no file outside the directory
is read, so a skill behaves the same wherever it is installed.

### Carrier
A skill holding a byte-identical copy of a reference another skill also holds.
Duplication is deliberate: it buys self-containment at the cost of drift, so
carriers are checked for byte-identity, and carriership is derived from what a
skill declares rather than from which files happen to be present.
_Avoid:_ owner, host, copy-holder

### Declaration
A skill's explicit list of the files it needs. Declarations are **closed**: a
declared file naming an undeclared one is a hole, not an omission. Declaring
replaced inferring the list by walking references, which produced false edges
that only appeared when something was deleted.

### Drift
Documentation that no longer describes the system, without anything having
failed. The characteristic damage is silent: a catalog listing agents that were
deleted reads as current, so the reader trusts it.

### Sweep
The scheduled pass that detects drift and opens a correcting pull request.

## Relationships

- A **plan** contains many **units**; a unit cites the **requirements** it covers.
- A **review** produces **findings**; each finding is resolved before the work ships.
- A **capture gate** admits a candidate; an **artifact type** decides where it is written.
- A **skill** declares what it needs; a **carrier** holds a shared copy of it.

## Flagged ambiguities

- "Agent" was used for both a spawned subprocess and a persona applied inline.
  These are distinct: a **persona** is a review dimension, and whether one runs as
  a separate agent is an implementation choice that has changed.
- "Review" meant both the Outside Voice pass and a human reading a pull request.
  Ensemble's usage is the former unless a person is named.
- "Spec" was used for both a design document and the contract a skill executes.
  Retired: the skill file is the contract; design documents are development
  history and are not shipped.
