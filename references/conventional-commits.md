# Conventional commits

Commit message format Ensemble enforces. Used by `/en-build`, `/en-ship`, and validated by `standards-reviewer`.

## Format

```
<type>(<scope>): <subject>

<body>

<trailer>
```

| Field | Required | Notes |
|---|---|---|
| `<type>` | yes | One of `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf` |
| `<scope>` | optional | Module / area; use existing scopes from the project's git log when possible |
| `<subject>` | yes | ≤ 50 chars; imperative mood (`add`, not `added`); no trailing period |
| `<body>` | optional | Wrap at 72 chars; explain WHY, not WHAT; reference issues if relevant |
| `<trailer>` | optional | `Co-authored-by:`, `Fixes: #<n>`, `Resolves: TD<n>`, etc. |

## Type semantics

| Type | When |
|---|---|
| `feat` | New user-visible capability |
| `fix` | Bug fix (production behavior corrected) |
| `docs` | Documentation only — no code change |
| `style` | Formatting / whitespace; no behavior change |
| `refactor` | Internal restructure; no behavior change |
| `test` | Adding or fixing tests; no production code change |
| `chore` | Tooling, deps, CI, config, build — anything not user-facing |
| `perf` | Performance improvement; behavior unchanged |

## Examples

✓ Good:

```
feat(auth): rotate refresh token on every access
fix(qa): adjust singleFlight TTL for network jitter
docs(foundation): add D31 single-agent fallback
chore(deps): bump bun to 1.1.x
refactor(billing): extract subscription state machine
test(auth): cover refresh-token race edge case
perf(queries): batch user lookups in dashboard render
```

✗ Avoid:

```
update auth                        ← no type/scope; vague
feat: Added login button.          ← past tense; trailing period
fix(billing): Fixed the bug        ← "fixed the bug" is meaningless
feat(auth): implement the entire authentication system across the codebase  ← over the 50-char subject
```

## Per-unit body format (`/en-build`)

When `/en-build` commits a unit, the body includes peer-review attribution:

```
feat(auth): rotate refresh token on every access — U3

Wrap rotateRefreshToken() in singleFlight to serialize concurrent
calls per user_id. Eliminates the race window where two near-
simultaneous refresh requests both rotated and one's new token got
invalidated.

Implementer: codex (worker)
Code-simplifier: 2 changes
Host review findings:
  - Applied: 1 finding
  - Deferred to tech-debt-tracker.md: 1 finding (TD11)
  - Disagreed: 0
```

## Trailers Ensemble uses

| Trailer | Meaning |
|---|---|
| `Resolves: TD<n>` | Closes a tech-debt-tracker entry |
| `Fixes: #<n>` | Closes a GitHub issue |
| `Addresses peer finding: <title>` | Inline in body, not a trailer; cited when a peer finding was applied |
| `Reverts: <commit-sha>` | Standard conventional-commits revert |

## What NOT to include

- **No emoji.** They render inconsistently across tools.
- **No marketing language.** "Massively improves performance" is not a commit subject.
- **No invented metrics.** "30% faster" requires real benchmark data; if untested, drop the claim.
- **No `WIP:` commits.** If you must commit unfinished work, use a feature branch and don't push to `main`.

## Validation

`standards-reviewer` flags non-conforming commit messages as P2 findings (unless `chore(release):` or `Revert ...` which are auto-generated).

`/en-ship` performs a final commit-message check before pushing; offers to amend if the format is off.
