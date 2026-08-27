# `/en-resolve-pr` triage rules

How to classify each item from `scripts/get-pr-comments` as **new**, **pending**, or **silent-drop**.

## Review threads

Walk the comment chain in the thread:

| State | Action |
|---|---|
| Only the original reviewer comment(s); PR author hasn't responded | **New** — process in step 7 |
| PR author has replied substantively, acknowledging or deferring (e.g. *"need to align on this"*, *"thinking through this before making a call"*, presents options without resolving) | **Pending decision** — skip; surface in step 14 summary as "still pending from a previous run" |
| PR author has replied with a fix/answer that resolves the concern | **Already handled** — skip |

The distinction is about **content, not author**. A previous `/en-resolve-pr` run, a manual reply from the user, or a teammate's reply all count as PR-author replies for this purpose (the PR author owns the response).

## PR comments and review bodies

These have no GitHub-side resolve mechanism, so they reappear on every fetch. Apply two filters in order:

### Filter 1 — Actionability

Skip if the body contains no actionable feedback or question to answer. Examples that fail this filter:

- Review-bot wrappers: *"Here are some automated review suggestions..."*, *"Walkthrough"* / *"Changes"* boilerplate from CodeRabbit, *"On-demand: this PR was reviewed..."* from Codex, generic Gemini Code Assist headers, Copilot summaries.
- Approvals: *"Looks good!"*, *"LGTM"*, *"Approved"*.
- Status badges: *"Validated"*, *"Tests passing"*.
- CI summaries with no follow-up ask: coverage reports without action items, deploy preview links, build duration notes.

If there's nothing to fix, answer, or decide, drop from the count entirely.

**Silent drop rule.** Non-actionable items are dropped without narration. **Do not** announce, list, or count dropped items in the conversation, the task list, or the step 14 summary.

The actionability check is **content-aware, not author-aware**. Bot feedback that requests a specific code change is actionable; the same bot's boilerplate header is not. A human reviewer's "looks good" is also non-actionable. The check is: does this body contain something that would change the code or merit a reply?

CI/status bots (Codecov, etc.) are pre-filtered at the script level — their output is structurally non-actionable. AI review bots (CodeRabbit, Codex, Gemini, Copilot) are NOT pre-filtered, because they sometimes post actionable findings as top-level comments. The actionability check above handles wrapper text from those bots.

### Filter 2 — Already replied

For items that pass actionability, scan the `pr_author_replies` field returned by `scripts/get-pr-comments` for an existing reply that quotes and addresses this feedback. If found → skip. Otherwise → **new**.

Replies are matched by the `> [quoted excerpt]` pattern that step 10 of the SKILL mandates: a PR-author comment whose body starts with a markdown blockquote line counts as a reply if the quoted text overlaps with the original feedback's body. The triage step does this matching at the SKILL layer, not in the script — the script's job is to expose the raw `pr_author_replies` so the SKILL has the data.

If the user replied manually in a different format (no `> ` quote prefix) and `/en-resolve-pr` doesn't recognize it, that item will be re-processed; the user can use `--skip <comment-id>` (future enhancement) or just decline it again.

**Why `pr_author_replies` is a separate field.** Earlier versions of the script filtered author comments out of `pr_comments` entirely — this caused already-answered top-level comments to be treated as new on subsequent runs (Codex P2 finding, 2026-05). Keeping author replies in their own field preserves the actionable-items list cleanly while giving triage the data it needs.

## Outcome

After triage, each item is exactly one of:

- **new** — process in steps 7–10 (rubric → fix/reply → push → reply/resolve)
- **pending** — skip; report in summary
- **silent-drop** — discarded; never mentioned

If no items end up in the `new` bucket, the SKILL skips steps 7–9 (no validation, commit, or push) and goes straight to step 10 / 14.
