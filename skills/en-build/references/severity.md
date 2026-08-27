# Severity, confidence, and autofix routing

How findings are graded and how the host decides what to do with them.

## Severity (P0–P3)

| Level | Meaning | Examples |
|---|---|---|
| **P0** | Blocking. Don't proceed without resolution. | Security vulnerability, data loss path, broken core flow, license incompatibility, breaking change to public API without migration |
| **P1** | High priority. Apply or surface for explicit decision. | Logic bug, missing required test, plan misses a documented requirement, broken cross-link, frontmatter schema violation |
| **P2** | Should fix soon. Apply if cheap; defer otherwise. | Missing edge-case test, naming inconsistency, minor coverage gap, freshness window exceeded |
| **P3** | Advisory. Note and move on. | Style preference, cosmetic improvement, optional refactor, "consider doing X later" |

## Confidence (1–10)

How sure the reviewer is. Surfacing rules:

| Confidence | Behavior |
|---|---|
| 8–10 | Surface in main report. |
| 6–7 | Surface with a caveat tag (`(conf 7)`). |
| 5 | Surface only if severity ≥ P1. |
| 1–4 | Suppressed unless severity = P0. |

## Autofix classes

Each finding routes through one of four classes:

| Class | Host behavior | Examples |
|---|---|---|
| `safe_auto` | Apply automatically without asking. Re-verify after. | Typos, broken cross-link repair, frontmatter field missing-but-known, naming convention fixes |
| `gated_auto` | Show user a one-line summary; default = apply; user can decline. | Variable rename across a unit, dead-code removal, simple refactor with test coverage |
| `manual` | Surface to user with the full finding; user decides. | Logic change, architectural choice, security-sensitive edit |
| `advisory` | Note in the report. Don't act. Add to `tech-debt-tracker.md` if useful. | "Consider extracting this helper later", style preference |

## Routing rules

The host applies findings using this matrix:

| Severity | Confidence | Autofix class | Default host action |
|---|---|---|---|
| P0 | any | any | **Pause and ask user.** Even `safe_auto` doesn't apply silently for P0. |
| P1 | ≥7 | `safe_auto` | Apply, re-verify, note in commit body. |
| P1 | ≥7 | `gated_auto` | Apply with one-line announcement; user can revert. |
| P1 | ≥7 | `manual` | Surface; user decides. |
| P1 | <7 | any | Surface; user decides. |
| P2 | ≥8 | `safe_auto` | Apply silently. |
| P2 | ≥8 | `gated_auto` | Apply with one-line announcement. |
| P2 | <8 | any | Add to `tech-debt-tracker.md`; mention in summary. |
| P2 | any | `manual` | Surface; user decides. |
| P3 | any | `advisory` | Add to summary. No action. |
| P3 | any | other | Add to `tech-debt-tracker.md`. |

## Three host responses to a finding (D30 contract)

When the host walks the peer's findings:

1. **Agree and apply.** Host modifies code per the finding. Mechanical fixes (typos, naming, simple refactors) and clear correctness fixes apply autonomously when severity/confidence/autofix-class allow per the matrix above. Note in commit body: `Addresses peer finding: <title>`.
2. **Agree but defer.** Finding is valid but out of scope for this unit/PR. Append entry to `docs/plans/tech-debt-tracker.md` with stable TD-ID. Cite the unit (`From U3 review`).
3. **Disagree with rationale.** Host believes the peer is wrong. Note one-line rationale in the unit progress report. Do not apply.

## When to surface to user

The host pauses and asks the user when:

- **Peer verdict = `reject`** → always pause.
- **P0 finding the host disagrees with** → pause; user judgment required.
- **Security/architectural finding with confidence ≥ 8 the host wants to defer** → pause; deferring high-confidence security to debt is a user-level call.
- **Two P1+ findings that conflict** → pause; user picks.
- **Otherwise** → host proceeds without confirmation per the matrix.

## Re-verification after applying findings

If the host applies any code changes in response to peer findings, re-run unit tests + lint before commit. On failure: `git restore` the changes and surface to the user. The host never commits broken code in pursuit of a finding.

## Tech-debt-tracker entry format

When deferring a finding to `docs/plans/tech-debt-tracker.md`:

```markdown
### TD<N>. <Finding title>

- **Source:** <skill-or-peer> review of <unit/plan/branch>
- **Severity:** P1
- **Confidence:** 7/10
- **Location:** `src/auth/refresh.ts:42`
- **Why it matters:** <1-2 sentence rationale from the finding>
- **Suggested fix:** <concrete description from the finding>
- **Logged:** YYYY-MM-DD
```

`TD<N>` IDs are append-only. `en-plan` cites them via `Resolves: TD<N>` in unit metadata when a plan addresses tracked debt.
