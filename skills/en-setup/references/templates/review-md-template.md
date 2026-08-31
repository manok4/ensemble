# Template — `REVIEW.md`

Used by `/en-setup`'s `REVIEW.md` offer to seed a project-root `REVIEW.md` that tunes how PR review behaves on your repo.

## Where this file is consumed

| Consumer | How it reads `REVIEW.md` |
|---|---|
| **Anthropic's managed Code Review service** (Team/Enterprise plans) | Reads `REVIEW.md` from your repo root automatically; injects content into every review-pipeline agent as the highest-priority instruction block. Per [code.claude.com/docs/en/code-review](https://code.claude.com/docs/en/code-review). |
| **`anthropics/claude-code-action@v1`** (Pro/Max self-hosted action) | Does **not** read `REVIEW.md` automatically. To use it, the workflow's `prompt:` step has to include the file content. See "Wiring `REVIEW.md` into the self-hosted action" below. |
| **OpenAI Codex review** (managed Cloud or `openai/codex-action@v1`) | Does not read `REVIEW.md`. Use `AGENTS.md` `## Review guidelines` section instead (per Codex docs). |

So: if you're on Pro/Max with the self-hosted action, `REVIEW.md` is useful as a single source of truth, but you must inject it into the workflow's prompt to actually take effect.

## Substitution variables

| Variable | Source |
|---|---|
| `{{PROJECT_NAME}}` | From `docs/foundation.md` `project:` |
| `{{PROJECT_TYPE}}` | One of: `backend service`, `frontend app`, `library`, `cli tool`, `docs site`, `mobile app`, `infrastructure`, `mixed` |
| `{{PLAN_ID_PREFIX}}` | From `docs/foundation.md` `plan_id_prefix:` (e.g. `EN`) |

## Template body

```markdown
# Review instructions for {{PROJECT_NAME}}

These are review-only instructions, distinct from `CLAUDE.md` (which guides
all Claude Code work, not just reviews). Anything here overrides default
review behavior.

## What "Important" means in this repo

Reserve 🔴 **Important** for findings that would:

- Break behavior visible to users or break a rollback path.
- Leak data: PII in logs, broken auth/authorization, exposed secrets, broken
  multi-tenancy boundaries, SQL/XSS/SSRF.
- Lose data: migrations without backfill, deletes without `WHERE`, broken
  cache-invalidation that produces stale reads in production.
- Violate a rule documented in `CLAUDE.md`, `AGENTS.md`, or
  `docs/learnings/`. (Treat documented violations as Important —
  the project explicitly opted into the rule.)

Style, naming, refactoring suggestions, and missing test coverage on
non-critical paths are 🟡 **Nit** at most.

## Cap the nits

Report **at most 5 Nits per review**. If you found more, say "plus N similar
items" in the summary instead of posting them inline. If everything you
found is a Nit, lead the summary with "No blocking issues."

## Skip these paths

Do not post findings on:

- `docs/generated/**` — machine-authored.
- `**/*.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `Cargo.lock`,
  `poetry.lock` — managed by tooling.
- `node_modules/`, `vendor/`, `dist/`, `build/`, `.next/`, `coverage/` —
  generated or vendored.
- Anything CI already enforces: lint, formatting, type errors. (CI is
  authoritative; your job is what CI can't catch.)

## Always check (this project's rules)

- New API routes have an integration test covering the happy path and at
  least one error path.
- Log lines do not include email addresses, request bodies, or secrets.
  (Use `user_id` — a stable hash or numeric ID — not email.)
- Database queries are scoped to the caller's tenant.
- Changes to `docs/plans/active/{{PLAN_ID_PREFIX}}*.md` units (`U-IDs`) are
  consistent with the plan's stated approach. Renumbering U-IDs is a P1
  violation per `references/stable-ids.md`.

(Adjust the list above per `{{PROJECT_TYPE}}`. Backend services often add:
no synchronous external calls in request paths without a circuit breaker.
Frontend apps often add: no `console.log` in committed code; prefer the
project's structured logger. Libraries often add: no breaking changes to
public exports without a `BREAKING CHANGE:` commit footer.)

## Verification bar

Before posting any 🔴 Important finding, confirm with evidence:

- For behavior claims: cite a `file:line` in the source. Inferences from
  symbol names alone are insufficient.
- For security claims: cite the specific code path that would be exploited
  and a concrete attacker capability. "This *might* be vulnerable" is
  insufficient.
- For race conditions: cite the two execution paths that interleave and
  the resulting bad state. Speculation without an interleaving is a Nit
  at most.

If the evidence isn't strong enough for Important, demote to Nit or skip.

## Convergence — second-round behavior

After the first review on a PR, suppress new 🟡 Nit findings; post 🔴
Important findings only. The author has the first round's nits in hand
already; piling more on round two costs them attention without
proportional value.

If a fix introduces a *new* Important issue, surface it. If a fix
addresses one Nit but exposes a different Nit, suppress the new one.

## When declining a reviewer suggestion

If you would not apply a finding (the suggestion would actually make the
code worse), state the specific harm. Generic "doesn't fit project
conventions" is not enough — name the convention.

Concrete patterns to cite:

- `CLAUDE.md` rule (file path + brief quote).
- `AGENTS.md` rule (file path + brief quote).
- A specific learning under `docs/learnings/<slug>-<date>.md`.

Example: *"Declined: this would add a defensive null check the type system
already guarantees. See `docs/learnings/no-defensive-null-checks-2026-02-15.md`."*

## Summary shape

Open the review body with a one-line tally:

> *"Found N important, M nits. P pre-existing."*

If everything is clean: open with *"No blocking issues."*

Lead with the shape of the work; the author wants to know whether to read
in detail before reading in detail.

## Pre-existing issues

If a 🟣 **Pre-existing** bug is in scope of the diff (touches the same
file or function), surface it once with the marker. If it's not in scope,
do not surface it. The PR is not the place to relitigate the codebase.

## Repo-specific checks (add yours below)

<!-- Add project-specific rules here. Examples:
  - "All new public exports in `src/api/` must have JSDoc."
  - "Migrations must be backwards-compatible for one release."
  - "Frontend components must accept a `data-testid` prop."
-->
```

## Wiring `REVIEW.md` into the self-hosted action

If you're on Pro/Max (using `claude-code-action@v1`), the action does **not** auto-read `REVIEW.md`. Inject its content into the workflow's `prompt:` step:

```yaml
- name: Read REVIEW.md (if present)
  id: review_md
  run: |
    if [ -f REVIEW.md ]; then
      {
        echo 'content<<EOF'
        cat REVIEW.md
        echo 'EOF'
      } >> "$GITHUB_OUTPUT"
    fi

- uses: anthropics/claude-code-action@v1
  with:
    claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    prompt: |
      REPO: ${{ github.repository }}
      PR NUMBER: ${{ github.event.pull_request.number }}

      ${{ steps.review_md.outputs.content }}

      Review this pull request per the instructions above.
```

The `${{ steps.review_md.outputs.content }}` substitution becomes empty when `REVIEW.md` doesn't exist, so the workflow stays correct in either case.

## Don't bloat it

Keep `REVIEW.md` focused on rules that change review behavior. Anything that's general project guidance (architecture, naming conventions, file layout) belongs in `CLAUDE.md` instead. A long `REVIEW.md` dilutes the rules that matter most — Anthropic's docs explicitly call this out.

## Lifecycle

`REVIEW.md` is human-maintained. `/en-setup` writes the initial version from this template; thereafter you edit it directly. `/en-sweep` won't touch it. `/en-learn capture` won't touch it. It's yours to tune.

If a `REVIEW.md` rule turns out to be wrong (false positives accumulating, or the rule is too strict), edit the file. The next review picks up the change.
