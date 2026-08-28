# `/en-resolve-pr` evaluation rubric

The 4-question rubric that drives the 6 verdicts. Apply in order; the first question that produces a verdict wins.

## Before applying the rubric

**Read the code at the referenced file:line.** For `review_threads`, location is provided directly. For `pr_comments` and `review_bodies` (no file/line context), identify relevant files from the comment text and the PR diff.

**If `isOutdated == true`** on a review thread, follow the outdated-thread handling in `SKILL.md` § "Outdated threads" before applying the rubric.

## The four questions

### 1. Is this a question or discussion?

The reviewer is asking *"why X?"* or *"have you considered Y?"* rather than requesting a change.

- Can you answer confidently from the code and surrounding context? → **`replied`**
- Does the answer depend on product/business decisions you can't determine? → **`needs-human`**

### 2. Is the concern actually valid?

Does the issue the reviewer describes actually exist in the code as-is?

- **No** (e.g., reviewer claims a null check is missing but it's at line 85) → **`not-addressing`** with evidence
- **Yes** → continue to question 3

### 3. Is the concern still relevant?

Has the code at this location changed since the review was posted?

- **No, the code referenced no longer exists in any meaningful form** → **`not-addressing`** with evidence (`searched <file> for <anchor>, not present`)
- **Yes**, or the concern still applies somewhere in the file → continue to question 4

### 4. Would fixing improve the code?

- **Yes**, applying the suggested fix improves the code → **`fixed`**
- **Yes**, but a better approach exists than what the reviewer suggested → **`fixed-differently`** (explain in the reply)
- **No, the suggested fix would actively make the code worse** → **`declined`** (must cite specific harm)
- **Uncertain** → default to fixing. Agent time is cheap; tech debt is expensive.

### When `declined` applies

The bar for declining is **specific harm**, not "low priority" or "not in style." Concrete harms that justify `declined`:

- Adds a defensive check the type system already guarantees.
- Suppresses errors that should propagate to the caller.
- Premature abstraction (one call site, no second use case in sight).
- Restates code in comments (the code already says it).
- Violates a project rule in `CLAUDE.md` / `AGENTS.md` / `docs/learnings/`.
- Introduces a backwards-compat shim where there's no existing usage to support.

When declining, **cite the specific source**: file path + brief quote, or learning slug. Generic "violates project guidelines" is not enough — name the rule.

### When `needs-human` applies

Rare. Use it for:

- Architectural changes that affect multiple subsystems beyond the PR's scope.
- Security-sensitive decisions where getting it wrong has real consequences.
- Ambiguous business logic where the right answer depends on product intent.
- Conflicting reviewer feedback where two reviewers disagree.
- The reviewer's suggestion implies the code was extracted to another location, but you can't determine where (per outdated-thread handling).

Most feedback has a clear right answer. `needs-human` should be a small minority of verdicts. **Do the investigation before escalating** — if the user can read your `decision_context` and decide in under 30 seconds, that's the bar. Punting with "this is complex" is not enough.

## Default-to-fix philosophy

> Agent time is cheap. Tech debt is expensive.

When in doubt, fix it — including nits. The cost is borne by the agent, not the human reviewer. The only legitimate reasons to skip are:

- The reviewer is **factually wrong** about the code (`not-addressing` with evidence).
- The suggested fix would **actively harm** the code (`declined` with cited harm).

"This is low priority" or "this isn't important enough" are **not** valid reasons. If the reviewer left it, you're already paying the attention cost; fixing it is cheap.

## After the rubric

Each item produces:

```
{
  "verdict": "fixed | fixed-differently | replied | not-addressing | declined | needs-human",
  "feedback_id": "<thread-id or comment-id>",
  "feedback_type": "review_thread | pr_comment | review_body",
  "reply_text": "<markdown reply, with quoted excerpt, per resolve-pr-reply-format.md>",
  "files_changed": ["<repo-relative paths, empty if no code change>"],
  "reason": "<one-line explanation>",
  "decision_context": "<only for needs-human — the structured brief>"
}
```

The SKILL aggregates these and runs combined validation in step 8.
