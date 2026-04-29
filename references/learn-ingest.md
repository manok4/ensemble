# `en-learn ingest` — file and URL ingest

Proactive knowledge capture. Distinct from `capture` (reactive, post-fix). Ingest reads any engineering-relevant external source — a file path or a URL — and writes a structured summary to `docs/learnings/sources/<slug>-<date>.md`, then walks 5–15 related pages and adds back-references.

## Inputs

| Input | Tool used | Example |
|---|---|---|
| File path | `Read` (Claude Code) / `read_file` (Codex) | `learn ingest path/to/article.md` |
| URL | `WebFetch` (Claude Code) / equivalent (Codex) | `learn ingest https://example.com/article` |

## Optional flags

| Flag | Default | Effect |
|---|---|---|
| `--category {sources\|patterns\|decisions}` | `sources` | Where the summary lands. Use `decisions` if the source itself is a decision-log entry; `patterns` rare (patterns usually emerge from own work). |
| `--force` | off | Override the off-topic skip (default threshold 0.3 / 1.0; see below). |
| `--no-walk` | off | Skip the related-pages walk. Just write the summary. |

## Off-topic detection

Engineering-relevance score against the project's `foundation.md`. Threshold: **0.3 / 1.0** (per A18).

- Score < 0.3 → silently skip with note: "This source appears off-topic for an engineering wiki — skipped. Re-run with `--force` to ingest anyway."
- Score ≥ 0.3 → proceed.

The check is LLM-judged, not a keyword match. Implementation: `en-learn` reads the source's first 500 tokens + `foundation.md` Section 1 (executive summary) + Section 2 (goals), and asks itself "engineering-relevant for this project: 0–1?"

## URL fetch with Wayback fallback (A13)

URL inputs frequently hit Cloudflare 403 blocks. Strategy:

1. Try direct fetch via `WebFetch` (or platform equivalent).
2. On 403 / Cloudflare challenge → try `https://web.archive.org/web/<URL>` via the same fetch.
3. On Wayback failure → ask the user to paste the content directly.

Rationale: many engineering articles are blocked by anti-bot CDNs. Wayback usually has them. Paste-fallback handles the rest.

## Process

1. **Read source.** File: `Read`. URL: WebFetch with Wayback fallback. On failure of all three: log and exit.
2. **Off-topic check.** LLM relevance score vs `foundation.md`. Skip if < 0.3 (unless `--force`).
3. **Discuss takeaways.** Briefly tell the user what's being extracted (one to two paragraphs).
4. **Slug + path.** Generate `<slug>-<date>` from the source title; write to `docs/learnings/<category>/<slug>-<date>.md`.
5. **Frontmatter.** Use the schema from `learning-frontmatter-schema.md` plus the sources fields:
   ```yaml
   source_type: file | url
   source_uri: <repo-relative path | full URL>
   fetched: YYYY-MM-DD
   ```
6. **Body.** Structured summary:
   - **One-paragraph TLDR**
   - **Key claims** (bulleted; quote where possible)
   - **Patterns / decisions worth importing**
   - **Open questions** (where the source is ambiguous or contested)
   - **Citations** (excerpts with page/section refs)
7. **Identify related pages.** Use `learnings-research` agent (or grep + read) to find 5–15 existing pages that touch on the same concepts. For each:
   - Add the new entry's path to the related page's `related:` field (the always-on cross-ref behavior — see `learn-cross-ref-maintenance.md`).
   - Surface a one-line update if the new source materially changes the page's claims (a contradiction, a stronger version, a new example). User decides whether to reconcile now or defer.
8. **Append always-on artifacts:**
   - `docs/learnings/index.md` — append entry to Sources (or chosen category) section.
   - `docs/learnings/log.md` — append `## [<date>] ingest-file | <title>` or `ingest-url | <title>`.

## Slug generation

- Lowercase the title.
- Replace non-alphanumeric with `-`.
- Collapse repeats; trim trailing `-`.
- Limit to 60 characters.
- Append `-YYYY-MM-DD`.

Examples:

| Title | Slug |
|---|---|
| "OpenAI harness-engineering essay" | `openai-harness-engineering-essay-2026-04-20` |
| "Karpathy's LLM Wiki gist" | `karpathys-llm-wiki-gist-2026-04-22` |

## Boundaries

Engineering-relevant sources only. If the user wants a personal knowledge base for unrelated topics (recipes, financial advice), they should run a different system. The off-topic skip + `--force` opt-in handles edge cases.

## Failure protocol

| Failure | Behavior |
|---|---|
| Source unreadable (404, 403, paste declined) | Log; exit with non-zero; no partial write |
| Off-topic skip | Log; exit 0; one-line note |
| Slug collision (same date, same title) | Append `-<short-hash>` to disambiguate |
| Cross-ref walk partial failure | Primary write succeeds; surface the partial; `--lint` self-heals later |
| Schema validation fails | Log; exit with diff against expected schema; user fixes manually |

## Worked example

```bash
$ /en-learn ingest https://openai.com/index/harness-engineering/

Fetching https://openai.com/index/harness-engineering/
  Direct fetch: 403 (Cloudflare) — falling back to Wayback.
  Wayback fetch: 200 OK.
Off-topic check: 0.92 / 1.0 → engineering-relevant for "Ensemble" project.

Extracting:
  - "AGENTS.md as a map, not encyclopedia" — informs §17.3.
  - "Plans split by lifecycle" — already in our D2.
  - "Recurring drift cleanup" — informs en-garden design.
  - "Failure means a missing capability" — operating principle.

Writing docs/learnings/sources/openai-harness-engineering-2026-04-20.md
Walking 12 related pages for back-refs:
  + docs/learnings/decisions/agents-md-as-pointer-map-2026-04-21.md
  + docs/learnings/patterns/plans-by-lifecycle-2026-03-12.md
  + docs/learnings/patterns/garden-event-driven-2026-04-15.md
  + docs/learnings/decisions/failure-as-capability-gap-2026-04-22.md
  ... (8 more)

Updated docs/learnings/index.md
Appended to docs/learnings/log.md

Done. New source: docs/learnings/sources/openai-harness-engineering-2026-04-20.md
```
