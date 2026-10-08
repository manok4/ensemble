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

**`$SKILL_DIR/scripts/ensemble-linear-plan` is the one implementation of this format**: `render`
turns a plan into the publish payload, `materialize` turns saved `get_issue` results back into a
plan, and `verify` compares a read-back with its source. The rules below are its spec; do not
apply them by hand.

The contract is invertible or it is nothing. `/en-build` materializes a plan
file from Linear and re-hashes it with `ensemble-plan-hash`; if the round trip
loses a byte the hash moves and the build refuses a plan nobody edited.

## Shape

| Plan concept | Linear object |
|---|---|
| the plan | one parent issue, created in state **Agent Ready** |
| a unit | one sub-issue of that parent, `parentId` set at creation |
| the U-ID | the title prefix `U<N> - `, e.g. `U1 - Verifier`, so a list filtered or sorted by title groups by unit |
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

**Titles survive exactly**, which is what makes the U-ID recoverable. The capture's
titles carried the U-ID as a `(U<N>)` suffix, the format before 2026-10-07;
`materialize` still reads it, so a plan published then still builds.

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
returned U2 before U1. Sort by the integer in the `U<N> - ` prefix and ignore the
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

**The parent's description is the whole plan except its H1 and unit blocks**: every
plan-level section (Context, Out of scope, Approach, Technical design, Decisions, the iteration
log and the rest) and the `## Implementation units` heading with any preamble, verbatim and in
order. A build therefore sees the same Out of scope and Technical design the reviewer did, and
the plan no longer survives only in an archive on the publishing machine. The H1 is left out
because the parent's title already names the plan, and Linear would show it twice; it travels in
the contract instead.

**It ends with a `## Verification Contract` heading** followed by one fenced `yaml` block: the
plan's frontmatter verbatim (`plan_id`, `title`, `status`, `depth`, `data_scale`,
`related_design`, `peer_review_verdict`, `peer_review_resolutions`, `peer_review_plan_hash` and
the rest), plus the keys `render` adds:

- `plan_full_hash`: `ensemble-plan-hash --full` over the plan as published. The
  default hash covers seven fields, so an edit in Linear to Test scenarios or
  Verification would pass it; `--full` covers every labelled field of every unit, the title
  and preamble, and every plan-level section, the iteration log included.
- `repo`: this repository's identity, the `origin` remote URL with scheme, userinfo
  and a trailing `.git` stripped, lowercased (`github.com/owner/name`). Plan IDs are
  repo-local and several repos can publish to one team, so discovery matches on
  `plan_id` **and** `repo`. A repo with no `origin` remote refuses `linear` mode: it
  has no identity another repo cannot also claim.
- `plan_heading`: the plan's H1 without its `# `, as a double-quoted string, when the plan's
  body opens with one. `materialize` puts it back as the plan's first line and drops the key,
  so the round trip still reproduces the plan the hashes cover.

Materialization rebuilds the frontmatter from that block, so nothing in it is
inferred from the local tree.

## Materialization, in order

Steps 1 to 3 are MCP calls the skill makes; steps 4 to 7 are what `ensemble-linear-plan
materialize` does with their saved results, and `intake` adds step 8.

1. `get_issue` the parent.
2. `list_issues --parentId` for the sub-issue set. Descriptions here are
   truncated; you want the ids.
3. `get_issue` each sub-issue for its full description.
4. Recover the frontmatter, `plan_full_hash`, `repo` and `plan_heading` from the Verification Contract
   block, refusing a `plan_id` that is not `<PREFIX><NN>` or a `plan_type` outside the
   template's enum: the amend path builds a file name from them. Skip canceled sub-issues
   before reading their titles: a canceled unit is not a unit.
5. Parse the `U<N> - ` prefix from each live title, or a legacy `(U<N>)` suffix. Refuse on
   a title with neither, or two live sub-issues with the same U-ID. Sort by that integer.
6. **Normalize `* ` to `- `** at the start of every list line, outside code fences and
   inside blockquotes; refuse any description still carrying the truncation marker.
7. Emit the plan file: `plan_heading` as its H1, then the parent's skeleton with the units
   placed under `## Implementation units`.

8. **`intake` only:** refuse unless the contract carries `plan_full_hash` and `repo`, `repo` is
   this repository's identity, `ensemble-plan-hash --full` of the rebuilt plan equals
   `plan_full_hash`, and `ensemble-plan-hash` equals `peer_review_plan_hash`. Only then write
   the file. A mismatch means the plan in Linear drifted from the plan that was published.

**The trust boundary.** Both digests live in the parent they protect, and `ensemble-plan-hash`
is public, so anyone with write access to the team can change a unit and recompute them. The
checks catch accidental drift, not a colleague. Write access to the Linear team is authority to
instruct the build (D119).
