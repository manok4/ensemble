# Template — `docs/learnings/<slug>-<date>.md`

Used by `/en-learn capture` after `references/capture-gate.md` says to write.

## Length

**A learning is one paragraph until it earns more.** The value is in recording
the thing that reading cannot recover, not in filling out sections. Most entries
that pass the gate are three to six sentences.

This replaced a nine-section template whose sections were mandatory. That shape
had one argument for it — a predictable layout to grep — and it does not survive
contact with the actual consumers, which are agents that read semantically. What
it reliably produced was padding: a one-sentence constraint inflated into
"Context", "What didn't work" and "Prevention" because the headings were there
and had to be fed. Structure that demands content manufactures content.

## Minimum entry

Frontmatter per `references/learning-frontmatter-schema.md`, a title, and the
paragraph. That is a complete, valid learning:

```markdown
---
title: Partner API rejects batches above 50 items
applies_when: Changing batch size or adding a new bulk endpoint call
date: 2026-08-27
tags: [partner-api, batching]
related: []
status: active
---

# Partner API rejects batches above 50 items

Their docs say 100 and their sandbox accepts 100, but production returns a 413
with an empty body above 50. Support confirmed the limit is 50 and the docs are
wrong; they have no plan to fix them. `PARTNER_BATCH_MAX` is set to 50 for this
reason and not as a conservative guess, so raising it will fail in production
only, after passing every test against sandbox.
```

Note what it does not contain: no description of how the batching code works, no
narrative of the debugging session, no "Prevention" heading restating the
paragraph. An agent reading `sync/partner-client` learns everything except the
one fact that matters, which is the whole entry.

## Optional sections

Add one **only** when it carries something the paragraph cannot. A section with
one line under it is a sign the paragraph should have absorbed it.

| Section | Add it when |
|---|---|
| `## What we tried` | Several approaches failed and the next agent would otherwise repeat them. List them with the reason each failed, not the chronology. |
| `## Why not <alternative>` | A reasonable reader will propose that alternative, and the rejection is non-obvious. Name it in the heading. |
| `## Evidence` | The claim is surprising enough that a reader will doubt it. Link the issue, the support thread, the failing run. |
| `## Scope` | The learning is narrower than its title suggests, and over-applying it would cause harm. |

No other headings. If content fits none of these, it belongs in the paragraph or
does not belong.

## Writing rules

- **Lead with the conclusion.** First sentence is the thing to remember, not the
  setup that produced it.
- **Name specifics.** File paths, constants, error strings, ticket numbers. "A
  timeout" is unusable; `PARTNER_BATCH_MAX` and "413 with an empty body" are what
  a future agent greps for.
- **Say why, not what.** The what is in the code. The why is the entry.
- **Write for someone about to make a change,** not someone studying the system.
- **No hedging.** If confidence is low, that is what the `confidence` field is
  for. "It may be that in some cases" wastes the reader's time in every case.

## Anti-examples

Two entries that pass a careless gate and should not exist.

> ## Root cause
> The `rotateToken` function did not await the Redis write, so the old token was
> still valid when the response returned.

The diff shows this, permanently and more precisely. Fails condition 1.

> ## TL;DR
> Concurrency bugs are hard to reproduce. Be careful when adding async code and
> always write tests for race conditions.

True and useless. No referent, no decision changes. Fails condition 2.

The version of that second one worth writing names the specific trap:

> Two requests rotating the same refresh token race, and the loser silently gets
> a valid-looking token that is already revoked. The failure surfaces one request
> later, in a different endpoint, which is why it reads as an auth bug rather
> than a rotation bug. `singleFlight` in `auth/rotate.ts` exists for this and
> removing it will not fail any current test.
