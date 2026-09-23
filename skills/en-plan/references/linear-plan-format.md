# The Linear plan format

How a plan is published to Linear and read back, so `/en-plan` and `/en-build`
cannot drift. **The unit-level rules were derived from a live round-trip**, not from
Linear's documentation: the capture is `tests/fixtures/linear/EN18-readback.json`
and the source it came from is `tests/fixtures/linear/EN18-sample-plan.md`.

**The parent description is specified, not measured.** The capture carries two of
the source's four units and no parent description, so the encoding under *What must
round-trip* (frontmatter, `depth`, `data_scale`, the two hashes, the repo identity) has
never been read back from a live workspace. It fails closed rather than silently: the
publish-side read-back verifies every field of it before anything is archived, so the
first live publish is the measurement, and a mismatch stops there.

The contract is invertible or it is nothing. `/en-build` materializes a plan
file from Linear and re-hashes it with `ensemble-plan-hash`; if the round trip
loses a byte the hash moves and the build refuses a plan nobody edited.

## Shape

| Plan concept | Linear object |
|---|---|
| the plan | one parent issue, created in state **Agent Ready** |
| a unit | one sub-issue of that parent, `parentId` set at creation |
| the U-ID | the title suffix `(U<N>)`, e.g. `Verifier (U1)` |
| unit order | **the U-ID, always.** Never Linear's ordering. See below. |

## What Linear changes, and what it leaves alone

Measured, not assumed.

**It rewrites `- ` list markers to `* `.** This is the one transformation that
matters and it breaks everything downstream if unhandled. `ensemble-plan-hash`
anchors its field parser on `^- \*\*(Goal|Files|…):\*\*`, so a description read
back from Linear parses as **seven empty fields**:

```
materialized as returned:     Goal:0:    Files:0:    Approach:0:    Risk:0:
after normalizing the marker: Goal:204:Teach the verifier the new trailer …
                              Files:107:…   Risk:3:low
```

(Field values elided above. The real capture is in the fixtures; quoting repo
paths here would make this document name files the skill does not carry.)

**Materialization MUST normalize `* **` back to `- **` before the canonicalizer
sees the text.** Do it at the Linear boundary, never by teaching
`ensemble-plan-hash` to accept both: that helper is the one implementation both
producer and consumer share, and widening its grammar to paper over a transport
detail is how the two ends drift apart again.

**Everything inside a field survives byte-for-byte.** Backticks and code spans,
`=>`, `+`, `--flag` names, `{missing,failed}`, parenthesised asides, nested
inline formatting. The values were not the problem; the markers were.

**Titles survive exactly**, `(U<N>)` suffix included, which is what makes the
U-ID recoverable.

## Four behaviours the protocol has to account for

**State is not inherited.** A sub-issue created under a parent in Agent Ready
lands in **Backlog**, whatever the parent's state. Set each unit's state
explicitly at creation if it should be anything else. (Team, priority and
project *are* inherited; state and labels are not.)

**`list_issues` truncates descriptions.** It returns a prefix and the literal
note `(truncated, use get_issue for full description)`. Materialization must
therefore be one `list_issues` for the sub-issue set plus one **`get_issue` per
unit**. An N-unit plan costs N+1 calls; against 2,500 requests/hour that is not
a budget concern, but it is not a single call either.

**Ordering is `updatedAt` descending by default, not plan order.** The capture
returned U2 before U1. Sort by the integer in the `(U<N>)` suffix and ignore the
order Linear gives you. Two sub-issues carrying the same U-ID is a refusal, not
a tie to break.

**There is no delete-issue tool on the MCP server.** `save_issue` can move an
issue to `Canceled`; removing it entirely is a manual action in the Linear UI.
Any cleanup path that says "delete" means "cancel, then delete by hand".

## What must round-trip, beyond the seven fields

`ensemble-plan-hash` covers the seven unit fields **plus plan-level `depth` and
`data_scale`**, so those two must survive or the hash cannot match.

`/en-build`'s pre-flight reads more than the hash does. Each sub-issue carries the
fields step 4 validates but the hash excludes: Test scenarios, Verification,
Requirements covered, Reversibility, Ship scope, Execution note and Interfaces. A
plan missing them materializes into a file the pre-flight refuses.

**The parent's description ends with a `## Verification Contract` heading** followed
by one fenced `yaml` block: the plan's frontmatter verbatim (`plan_id`, `title`,
`status`, `depth`, `data_scale`, `related_design`, `peer_review_verdict`,
`peer_review_resolutions`, `peer_review_plan_hash` and the rest), plus two keys the
publish step adds:

- `plan_full_hash`: `ensemble-plan-hash --full` over the plan as published. The
  default hash covers seven fields, so an edit in Linear to Test scenarios or
  Verification would pass it; `--full` covers every labelled field of every unit.
- `repo`: this repository's identity, the `origin` remote URL with scheme, userinfo
  and a trailing `.git` stripped, lowercased (`github.com/owner/name`). Plan IDs are
  repo-local and several repos can publish to one team, so discovery matches on
  `plan_id` **and** `repo`. A repo with no `origin` remote refuses `linear` mode: it
  has no identity another repo cannot also claim.

Materialization rebuilds the frontmatter from that block, so nothing in it is
inferred from the local tree.

## Materialization, in order

1. `get_issue` the parent. Recover the frontmatter, `plan_full_hash` and `repo`
   from the Verification Contract block. Refuse when `repo` is not this repo.
2. `list_issues --parentId` for the sub-issue set. Descriptions here are
   truncated; you want the ids.
3. `get_issue` each sub-issue for its full description.
4. Parse `(U<N>)` from each title. Refuse on a missing or duplicate U-ID.
5. Sort by that integer.
6. **Normalize `* **` to `- **`** in every description.
7. Emit the plan file, then compare **both** digests before anything else reads it:
   `ensemble-plan-hash` against `peer_review_plan_hash`, and
   `ensemble-plan-hash --full` against `plan_full_hash`. Either mismatch refuses: the
   plan in Linear is no longer the plan that was reviewed.
