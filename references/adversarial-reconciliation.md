# Adversarial reconciliation (en-review Adversarial tier)

How `/en-review` reconciles two **independent** finding sets — the host persona roster (H) and the cross-agent Outside Voice peer (P) — into one decision about what's worth fixing. Used only in the Adversarial tier (`is_high_stakes` or `--adversarial`).

> **Independence is the whole point.** The peer reviews the same diff **without seeing H first** — a true second opinion. Agreement between two independent reviewers (especially two different model families) is the strongest signal in the set; it's what makes the adversarial pass worth its cost.

## Inputs

- **H** — findings from the host persona subagents (steps 7–8), each with severity, confidence anchor, `first_evidence` where applicable.
- **P** — findings from the cross-agent peer (step 9), same schema. The peer is dispatched with the diff only — never with H.

## Reconciliation

1. **Fingerprint each finding:** `normalize(file) + line_bucket(line, ±3) + normalize(title)`. Findings within 3 lines on the same file with a similar title are the same issue.

2. **Agreement (in both H and P)** → the strongest signal. Merge into one finding, **promote one confidence anchor** (`50→75→100`; promotion never bypasses the quote-the-line gate — a promoted 75/100 still needs `first_evidence`), and mark `worth_fixing: true`. Record both reviewers (`personas: ["correctness", "peer"]` etc.). Cross-**model** agreement (host model vs peer model) is the highest-confidence case — surface it as such.

3. **Single-source (in H xor P)** → run a short **adversarial judgment**: "is this real AND worth fixing?" The finding survives to the actionable tier only if it carries hard evidence (anchor 75/100 with `first_evidence`, per the quote-the-line gate). Otherwise:
   - demote to anchor 50 → **advisory** (surfaced as low-priority) or **filed as TD** (en-review's edge — not silently dropped), per the confidence gate in `references/finding-schema.md`.
   - A single-source P0 still survives at anchor 50+ (critical-but-uncertain is never silently dropped).

4. **Conflict (same fingerprint, incompatible severity/route)** → keep both, mark `conflict: true`, choose the more conservative route, and surface for user judgment (per `references/persona-dispatch.md`).

5. The reconciled set flows into the normal synthesis (step 10), but **dedup is already complete here** — reconciliation IS the dedup for the adversarial path (it fingerprinted and merged across H and P). Step 10's dedup is therefore a **no-op** on a reconciled set (re-running it changes nothing); the host skips it and proceeds to conflict-marking, the confidence gate (step 11), and thematic grouping (step 11.5). Do not re-promote anchors in step 10 — corroboration promotion already happened in step 2 here.

## Output

The reconciled envelope records the reviewer mix so the user can see how each finding was corroborated:

- `reviewer: adversarial` on the run.
- Per finding: `personas` lists the contributing reviewers; `worth_fixing` is set on agreement; `corroboration: cross-model` when host and peer (different model families) agreed.

## Why this beats either reviewer alone

The host just-implemented-it bias and the peer's lack of repo context are different blind spots. Two independent passes catch what one misses, and agreement filters out the false positives that plague a single aggressive reviewer — the reconciliation turns "two opinions" into "what's actually worth your time."
