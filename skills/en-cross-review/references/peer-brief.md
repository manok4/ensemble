# Peer review brief — ad-hoc cross review

What the peer is asked when `/en-cross-review` sends it an arbitrary target. The
wire format is `references/peer-contract.md`; everything here is this skill's own.

**This skill does not have one set of dimensions, and should not pretend to.**
Its target is whatever the user pointed at: a diff, a file, a branch, a document,
uncommitted work. Fixing one dimension set would make it wrong for most targets,
which is the same mistake as the single generic prompt this plan removed.

## Selecting dimensions by target shape

Classify the target first, then ask the matching questions. State which shape you
picked in the report, so a reader can tell whether it was the right call.

| Target | Ask |
|---|---|
| A code diff or source files | Correctness, tests, maintainability, standards; plus security, performance or migrations when the change touches them |
| A plan | Whether it achieves its goal, unit decomposition, test scenarios, risk and gating correctness, stated assumptions |
| A design or foundation document | Whether decisions are recorded with reasons, requirements are buildable, constraints are written down, and nothing contradicts |
| Prose documentation | Whether claims match the code, paths resolve, and instructions are followable |
| Mixed, or unclear | Say so, pick the dominant shape, and name what you did not review |

**When the shape is unclear, do not guess silently.** A review that quietly
picked the wrong dimensions reads exactly like a clean one. Name the shape you
chose and what that leaves uncovered.

## `--focus`

When the caller passes `--focus security|performance|tests`, that dimension is
mandatory and the others become optional. Without it, use the table.

## Where a finding points

`<file>:<line>` for code, the section name for prose, the unit id for a plan,
`global` when it is about the target as a whole.

## What en-cross-review does with the findings

Contract first: `references/peer-contract.md`. Policy follows, and it is the
narrowest in the toolkit.

**This skill reports. It does not apply.** Findings are grouped by severity and
returned. Nothing is edited, nothing is committed, regardless of severity or
autofix class — a user asking for a second opinion is asking to be told, not to
have their tree changed underneath them.

That makes the autofix class advisory here: it travels in the finding so the
caller can route it, and this skill acts on none of it.

| Severity | Reported as |
|---|---|
| P0 | Listed first, called out as blocking |
| P1 | Listed, grouped |
| P2, P3 | Listed, grouped, no emphasis |

## Effort

The target's shape drives it, not a diff-size ladder: a security-focused review
or a large architectural target asks for `high`; a small file asks for the
default.
