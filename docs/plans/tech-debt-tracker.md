---
type: tech-debt-tracker
generated: false
created: 2026-08-26
updated: 2026-08-26
---

# Tech debt tracker

> Noticed-but-deferred items. Append-only; do not renumber TD-IDs.
> `/en-plan` reads this when planning new work and may cite items
> via `Resolves: TD<n>` in unit metadata.

## Open

### TD1. Peer review blocks one tool call, so a killed or truncated call reads as success

- **Source:** review of the Compound Engineering plugin's cross-agent design, during EN12 planning
- **Severity:** P1
- **Confidence:** 9/10
- **Location:** `bin/ensemble-peer-invoke:104` (`timeout_secs`), `references/build-handoff.md:106`
- **Why it matters:** `ensemble_peer_invoke` wraps the peer in `timeout ${peer_timeout_seconds:-600}` and holds a single tool call open for up to ten minutes. A harness that caps tool-call duration kills the supervising shell mid-run and the peer dies with it. Worse, the failure is not always classified: observed on 2026-08-26 during EN12's own peer review, the helper exited 0 with `{"peer":"on","reason":"default-on"}` and an output file containing only `{"type":"thread.started",...}`. The identical prompt piped straight into `codex exec --json` returned the full five-finding review. A truncated stream read as a completed peer pass, which is exactly the "a degraded peer must never read as a normal one" invariant EN11 exists to protect.
- **Suggested fix:** Adopt the detached-job lifecycle the Compound Engineering plugin uses (`skills/*/scripts/peer-job-runner.py`, 2250 lines, byte-duplicated into six skills and pinned by `tests/peer-job-runner-parity.test.ts`). Split the peer call into `start` / `status` / `wait` / `result` / `reap`, where `start` double-forks with `setsid`, prints a job id and returns immediately, and every durable fact lives on disk. Specific mechanics worth taking: liveness measured as output byte growth rather than process existence; the status file written last so it is always the final record; atomic publish via tmp plus rename; idle window and hard cap as separate limits; byte caps that classify as failed with a recorded reason; and an explicit `died-without-result` state instead of folding that into `failed`. Do not take CE's routing apparatus (route tokens, recipient sanctioning, egress disclosure, config layers) — Ensemble's single `peer_decision` object with a closed reason enum is tighter than CE's receipts, and the fix should preserve it. Two design notes: CE's duplicated assets are deliberately dependency-free (`peer-job-runner.py` imports stdlib only, `cross-model-adversarial-review.sh` sources nothing local), which is what makes byte-duplication tractable; and EN12's U5 closure walker follows bash `. "$_dir/sibling"` lines only, so a Python runner would need either the same single-file discipline or an extended walker.
- **Sequencing:** deliberately deferred until EN12 ships. Building this first means building it against the current root layout and migrating it afterwards; building it second lands it directly in the target shape as one more `shared/manifest.json` entry. Decided with the user on 2026-08-26.
- **Logged:** 2026-08-26

### TD2. Most SKILL.md bodies exceed the Codex 8000-byte injection limit

- **Source:** EN12 U12, measured during the build
- **Severity:** P1
- **Confidence:** 8/10
- **Location:** `skills/*/SKILL.md` — 15 of 17 skills
- **Why it matters:** Codex injects only the first 8000 bytes of a SKILL.md. Everything past that is invisible to that host, so a rule placed deep in a long body silently does not apply there — the skill appears to load and then behaves differently on Codex than on Claude Code, with no error. This is a cross-host correctness gap (G9), not a tidiness concern. EN12's plan named three skills from an earlier spot-check; the measured picture is worse:

  | `en-build` | 49,768 | 6.2x |
  | `en-plan` | 32,805 | 4.1x |
  | `en-setup` | 27,656 | 3.5x |
  | `en-review` | 25,527 | 3.2x |
  | `en-ship` | 21,185 | 2.6x |
  | `en-learn` | 16,213 | 2.0x |
  | `en-loop` | 15,650 | 2.0x |
  | `en-brainstorm` | 15,601 | 2.0x |
  | `en-resolve-pr` | 15,169 | 1.9x |
  | `en-debug` | 14,001 | 1.8x |
  | `en-sweep` | 13,569 | 1.7x |
  | `en-foundation` | 11,618 | 1.5x |
  | `en-guardrail` | 11,012 | 1.4x |
  | `en-qa` | 10,089 | 1.3x |
  | `en-cross-review` | 8,188 | 1.0x |

  `en-cross-review` at 8,188 bytes is only just over, so it loses a few lines; `en-build` loses roughly five sixths of its body, including the whole post-build phase, the evidence audit and the learning checkpoint.
- **Suggested fix:** Move load-bearing rules out of long bodies and into references the skill reads at a named early step, so what must be honored arrives through a read the agent performs rather than through an injection that may be truncated. The Compound Engineering plugin routes `lfg` to `references/plan-brief.md` for exactly this reason, and its parity test records the constraint explicitly. Audit per skill in body order: anything past roughly 8,000 bytes that changes behavior (a gate, an enum, a refusal condition, a safety rule) moves; narrative and examples can stay. Verify by loading each skill on Codex and checking that a rule from the tail is actually honored — byte count alone does not prove the rule survived.
- **Not caused by EN12, and not fixed by it.** EN12 makes skills self-contained; it does not shorten them. Recorded here so the gap is tracked rather than absorbed into a migration unit, where it would weaken the atomic review of the riskiest change in that plan.
- **Logged:** 2026-08-26

### TD3. `doc-lints.md` pointed at a CI template this repo never shipped

- **Source:** EN12 U7, surfaced by the single-skill-install dangling check
- **Severity:** P3
- **Confidence:** 9/10
- **Location:** `shared/references/doc-lints.md:9`
- **Why it matters:** The file recommended running the doc lints in CI "via `references/ci-templates/lint.yml`", and no such file exists anywhere in the repo or its history. Harmless while nothing resolved relative paths; once every skill carries its own copies, a link to a file that cannot exist is a dangling reference in 7 skills at once. The pointer is now replaced with a note, so the recommendation survives without promising an artifact.
- **Suggested fix:** Either ship the template (a small workflow running `shared/bin/ensemble-lint --scope docs/`, which `.github/workflows/ensemble-tests.yml` already does for this repo and which a consuming project would want too), or drop the CI recommendation. Shipping it is the better answer, since `references/templates/` already carries `github-workflow-en-sweep.yml` and `github-workflow-claude-review.yml` for exactly this purpose.
- **Logged:** 2026-08-26

## Resolved

<!-- none yet -->
