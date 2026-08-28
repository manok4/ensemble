# Peer review brief — reviewing a foundation document

What the peer is asked when `/en-foundation` sends it a foundation draft, and
what this skill does with the answer. The wire format is
`references/peer-contract.md`; everything here is en-foundation's own.

**There were no dimensions before this.** en-foundation passed
`--artifact-type "markdown artifact"`, which hit the `else` branch and set the
dimensions to the empty string. It has been sending documents to a peer with no
guidance at all.

## What the peer is asked

A foundation document states what is being built, for whom, and on what. Review
it for whether the decisions it records are sound and whether it says enough for
someone to plan against. It is not code: do not review it for style.

### A. Does it answer what it claims to answer?

Each section should settle a question. Flag sections that describe a topic
without deciding anything — "we will consider caching" settles nothing a planner
can act on.

### B. Requirements that cannot be built against

Every R-ID should be specific enough that a unit could cover it and a test could
verify it. Flag requirements phrased as aspirations, and requirements that bundle
several separable things under one ID.

### C. Decisions recorded without their reason

A decision without a why cannot be revisited safely — the next reader either
cargo-cults it or reverses it blindly. Flag decisions stated as facts. Rejected
alternatives matter most here: an unrecorded rejection gets re-proposed.

### D. Constraints that exist but are not written

Compliance boundaries, contractual response times, upstream limits, data
residency. These bind the build and leave no trace in code, so a foundation that
omits them will be contradicted by reality later.

### E. Architecture intent versus architecture specification

Foundation records intent and boundaries, not a design. Flag sections that
over-specify — a module-by-module design here goes stale immediately and competes
with `docs/architecture.md`.

### F. Internal contradiction

Two sections that cannot both be true. These are the most expensive defects in a
foundation because every later plan inherits them.

### G. Scale and deployment claims stated without basis

"Handles 10k concurrent users" in a foundation with no load evidence is a wish.
Flag it, or flag that it needs qualifying.

Do not flag: prose style, heading order, section naming, or the absence of
sections the project does not need.

## Where a finding points

The section name. A foundation has no line-level structure worth citing.

## What en-foundation does with the findings

Contract first: `references/peer-contract.md`. Policy follows.

| Severity | Action |
|---|---|
| P0 | Surface. A foundation with a blocking defect should not be built against. |
| P1 | Apply to the document, or record why not. These are the ones that cost later. |
| P2 | Apply if the edit is local; otherwise record as `deferred`. |
| P3 | Record as `deferred`. |

Every fix is an edit to the document. There is nothing to re-verify, so no
re-verification step applies — the code-shaped one the shared severity file
prescribed never made sense here.

Findings D and F are worth applying even at low confidence: a missing constraint
or a contradiction is cheap to check and expensive to inherit.
