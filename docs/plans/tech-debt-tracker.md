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

## Resolved

<!-- none yet -->
