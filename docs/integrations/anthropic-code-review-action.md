# Anthropic Claude Code Review GitHub Action — Setup

How to install [anthropics/claude-code-action](https://github.com/anthropics/claude-code-action) so Claude posts inline review comments on your PRs automatically. Pairs with `/en-resolve-pr` (which handles the comments after they arrive).

## Authentication options

| | OAuth (Pro/Max subscription) | API key |
|---|---|---|
| Cost | Included in your Max/Pro plan | Per-token, separate billing |
| Rate limits | **Yes** — same caps as Claude Code itself; CI runs eat into your usage | None beyond plan defaults; pay for what you use |
| Predictability in CI | Can hit cap mid-PR if many runs land same day | No surprise stalls |
| Setup | One-time `claude setup-token` | One-time API console step |

**Recommendation for low/medium-volume repos:** start with OAuth. Switch to API key later if you hit rate caps. The workflow change is one line.

## Setup — OAuth (subscription)

### 1. Generate the OAuth token locally

```bash
claude setup-token
```

(Available to Pro and Max subscribers. Prints a token; copy it.)

### 2. Store as a GitHub Secret

In your repo: **Settings → Secrets and variables → Actions → New repository secret**

- **Name:** `CLAUDE_CODE_OAUTH_TOKEN`
- **Value:** the token from step 1

### 3. Add the workflow

Create `.github/workflows/claude-code-review.yml`:

```yaml
name: Claude Code Review

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    if: github.event.pull_request.draft == false
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write   # post review comments
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # full history for diff context
      - uses: anthropics/claude-code-action@v1
        with:
          # v1: OAuth uses the dedicated claude_code_oauth_token input.
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          # v1: mode is auto-detected; PR-review automation uses prompt input.
          prompt: |
            REPO: ${{ github.repository }}
            PR NUMBER: ${{ github.event.pull_request.number }}

            Review this pull request. Focus on correctness, security, test
            coverage, performance, and adherence to CLAUDE.md / AGENTS.md
            conventions. Aim for high-precision findings; post inline comments
            at file:line.
          track_progress: true
```

The `if: ... draft == false` guard skips review on draft PRs to reduce rate-limit burn.

### 4. (Alternative) Use the bundled installer

If you prefer a guided setup, run from the project root:

```bash
claude /install-github-app
```

Walks through the GitHub App install and writes the secrets for you.

## Setup — API key

Same workflow file, replace the OAuth input with the API-key input:

```yaml
# Replace this line:
#   claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
# with:
anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

Add `ANTHROPIC_API_KEY` to repo secrets (from <https://console.anthropic.com>). In v1, `anthropic_api_key` and `claude_code_oauth_token` are **separate inputs** — pick the one matching your auth method, not both.

## Trade-offs and operational notes

- **Draft-PR skip.** The `draft == false` guard above prevents Claude from reviewing every push to an in-progress PR. Mark a PR ready-for-review when you actually want feedback.
- **Re-runs on push.** `synchronize` fires on every push; if you push frequently, expect a review per push. Configure `paths_to_review` to scope it down if needed.
- **Required-status-check trap.** Don't make the review job a *required* status check unless you're certain you want a failed review to block merge. Reviews can fail for transient reasons (rate limit, network); merge gating gets brittle.
- **Cost containment for OAuth.** If you start hitting rate caps, switch the secret reference to an API key — no other workflow changes needed.

## Terms of service

In February 2026 Anthropic clarified that OAuth tokens from Claude Free/Pro/Max accounts shouldn't be used outside official tools (Claude.ai and Claude Code).

The official `anthropics/claude-code-action` is **in scope as an official tool** — the docs themselves walk you through OAuth setup, so this path is sanctioned.

What's not sanctioned: third-party wrappers, OAuth-token proxies, generic "use your Claude sub anywhere" tools. As long as you're using `anthropics/claude-code-action` directly (not a fork or a SaaS that wraps it), you're fine.

## Verifying the install

After committing the workflow file:

1. Open a PR (or push to an existing one).
2. Watch the **Actions** tab — the "Claude Code Review" job should run.
3. Review comments will appear inline on the PR diff once it completes.
4. Run `/en-resolve-pr` locally to triage and respond.

If the action runs but posts no comments, it found nothing actionable (this is a feature, not a bug — see the plugin's confidence-scoring docs).

If the action fails to start, check:

- Secret name matches (`CLAUDE_CODE_OAUTH_TOKEN` vs `ANTHROPIC_API_KEY`).
- `permissions:` block includes `pull-requests: write`.
- The PR isn't from a fork (forks have restricted secrets access by default).

## Where this fits in the Ensemble flow

```
/en-plan → /en-build → /en-review → /en-qa → /en-ship
                                                  │
                                                  ▼
                                            [PR opened]
                                                  │
                                                  ▼
                                ┌─────────────────────────────────┐
                                │ Claude Code Review Action fires │
                                │ (this integration)              │
                                │ → posts inline comments         │
                                └─────────────────┬───────────────┘
                                                  ▼
                                ┌─────────────────────────────────┐
                                │ /en-resolve-pr                     │
                                │ → triage, fix, reply, resolve   │
                                └─────────────────┬───────────────┘
                                                  ▼
                                              [merge]
```

## References

- [anthropics/claude-code-action — repo](https://github.com/anthropics/claude-code-action)
- [Setup docs](https://github.com/anthropics/claude-code-action/blob/main/docs/setup.md)
- [Claude Code Introduces Max Subscription Support for GitHub Actions](https://wain.blog/en/claude-code-github-actions-max-support-8NB583zS/)
- [Claude Code GitHub Actions Setup Guide (2026)](https://kissapi.ai/blog/claude-code-github-actions-setup-guide-2026.html)
