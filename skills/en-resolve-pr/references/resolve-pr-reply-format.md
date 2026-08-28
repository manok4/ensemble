# `/en-resolve-pr` reply formats

Verdict-specific reply templates. Every reply leads with a quoted excerpt of the original feedback for thread continuity — the next reader can follow what's being addressed without scrolling.

## Quote rule

Quote the **specific sentence or passage being addressed**, not the entire comment if it's long. Use markdown blockquote (`> `).

Good — focused excerpt:

```markdown
> The null check on line 42 is redundant; `getUserById` already returns `User | null`.

Addressed: removed the duplicate null check.
```

Bad — quoting the whole comment:

```markdown
> Looking at this PR, I had a few thoughts. First, on src/auth.ts, I noticed that
> there's a null check on line 42 that's redundant because the type signature already
> handles it. Second, on src/api/users.ts...

Addressed: removed the duplicate null check.
```

## Per-verdict templates

### `fixed`

```markdown
> [quoted relevant part of reviewer's comment]

Addressed: [brief description of the fix]
```

Example:

```markdown
> Consider parameterizing this query to prevent SQL injection.

Addressed: switched to parameterized query using prepared statement at line 67.
```

### `fixed-differently`

```markdown
> [quoted relevant part of reviewer's comment]

Addressed differently: [what was done instead and why]
```

Example:

```markdown
> Could we extract this into a helper function?

Addressed differently: kept inline because the helper would only have one call site;
extracting now would be premature abstraction. Open to revisit if a second use case shows up.
```

### `replied` (questions, explanations)

```markdown
> [quoted relevant part of reviewer's comment]

[Direct answer to the question or explanation of the design decision]
```

Example:

```markdown
> Why are we using Redis here instead of in-memory caching?

Persistence across restarts. The single-flight cache TTL exceeds typical container restart
windows, so an in-memory cache would lose state and cause duplicate token rotations during
deploys. See docs/learnings/redis-for-token-cache-2026-03-12.md for the full
rationale.
```

### `not-addressing` (reviewer is factually wrong)

```markdown
> [quoted relevant part of reviewer's comment]

Not addressing: [reason with evidence]
```

Example:

```markdown
> Missing null check on `user` before accessing `user.email`.

Not addressing: null check exists at line 85, before the access on line 92.
```

The "with evidence" part matters. Always cite a file:line or quote the existing code that disproves the reviewer's claim. Don't just say "this is wrong" — show why.

### `declined` (suggestion would harm the code)

```markdown
> [quoted relevant part of reviewer's comment]

Declined: [specific harm cited, with source]
```

Examples:

```markdown
> Add a try/catch around the entire function to handle any errors gracefully.

Declined: this would suppress errors that should propagate to the caller. The current
ValidationError must reach the API boundary so the client gets a 400. Wrapping it would
silently return a 200 with a malformed response. (Per CLAUDE.md: "Don't add error handling
for scenarios that can't happen / shouldn't be silently swallowed.")
```

```markdown
> Extract the validation logic into a `Validator` class for reusability.

Declined: this is the only call site for validation in this shape. Extracting now would be
premature abstraction. (Per docs/learnings/no-premature-abstraction-2026-02-08.md:
"Three similar lines is better than a premature abstraction.")
```

```markdown
> Consider adding a `force?: boolean` parameter for backwards compatibility.

Declined: there's no existing caller to be backwards-compatible with — this function was
added in this same PR. Adding the parameter would be solving a hypothetical problem. (Per
CLAUDE.md: "Don't design for hypothetical future requirements.")
```

The pattern: cite the **specific harm** + the **source of the rule** (file path + quote, or learning slug). Generic "violates project guidelines" is not acceptable — name the rule.

### `needs-human` (PR-thread reply)

The reply posted **on the PR thread** should sound like the PR author — natural, conversational, not AI boilerplate. The depth goes into the `decision_context` returned to the parent skill (which surfaces it in the user-facing summary).

```markdown
> [quoted relevant part of reviewer's comment]

[Natural acknowledgment, e.g., "Good question — this is a tradeoff between X and Y. Going
to think through this before making a call." or "Need to align with the team on this one —
[brief why]."]
```

**Avoid AI tells:**

- ❌ "Flagging for human review."
- ❌ "I'll defer this to the user."
- ❌ "This requires further analysis."
- ✅ "Going to think through this — quick question for the team about [specific point]."
- ✅ "Need to align on this one before changing the API contract."

The reviewer reads this on the PR; it should sound like a human at the keyboard.

### `needs-human` decision_context (for the user, not the PR)

This goes to the user via the step 14 summary, not on the PR. Format:

```markdown
## What the reviewer said
[Quoted feedback — the specific ask or concern]

## What I found
[What you investigated and discovered. Reference specific files, lines, and code.
Show the work.]

## Why this needs your decision
[The specific ambiguity. Not "this is complex" — what exactly are the competing
concerns? E.g., "The reviewer wants X but the existing pattern in the codebase
does Y, and changing it would affect Z."]

## Options
(a) [First option] — [tradeoff: gain / loss / risk]
(b) [Second option] — [tradeoff]
(c) [Third option if applicable] — [tradeoff]

## My lean
[If you have a recommendation, state it and why. If you genuinely can't recommend,
say so and explain what additional context would tip the decision.]
```

The user should be able to read this and decide in under 30 seconds.

## Tech-debt-routing addendum (Ensemble-specific)

When a `replied` verdict acknowledges something legitimate but out-of-PR-scope, the SKILL files a TD entry and references it in the reply:

```markdown
> Could we add tests for the failure modes here?

Good catch — out of scope for this PR (which is just adding the happy path), but real gap.
Filed as TD23 in docs/plans/tech-debt-tracker.md for follow-up.
```

This keeps the conversation honest (acknowledges the concern is valid) while keeping the PR focused.

## Capture-from-synthesis addendum (Ensemble-specific)

When a `declined` or `needs-human` verdict surfaces a recurring anti-pattern not yet in `docs/learnings/`, the SKILL soft-prompts after the run:

> *"Reviewer flagged a recurring concern in `<thread>`. Capture as a learning?"*

On user accept → `/en-learn capture --from-conversation`. The learning then becomes citable in future `declined` replies. The wiki compounds.
