---
type: plan
plan_type: improvement
plan_id: EN26
title: Review tiers set by a script, so every change gets the right depth of review
status: completed
location: active
created: 2026-11-04
shipped: 2026-11-04
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: revise
peer_review_iterations: 2
peer_review_last_run: 2026-11-04
peer_review_plan_hash: 72e316bd6bd583d7a87de010e7bcd41714d67735115fe7302b4e22610d00293d
peer_review_resolutions:
  - finding_id: 1-1
    iteration: 1
    severity: P1
    title: The receipt gate forgets raised review requirements
    status: applied
    location: U5
  - finding_id: 1-2
    iteration: 1
    severity: P2
    title: Lite override reasons omit unreadable diffs
    status: applied
    location: U3
  - finding_id: 2-1
    iteration: 2
    severity: P1
    title: Existing receipt checks can bypass a raised requirement
    status: applied
    location: U5
depth: standard
data_scale: small
---

# EN26: Review tiers set by a script, so every change gets the right depth of review

## Context

By the written rules, a bare `/en-review` on a diff under 50 lines has no reviewer: `--peer` dispatches no host reviewers (`skills/en-review/SKILL.md` step 7), the size row turns the peer off (step 2a), and "the persona findings are the envelope" with no personas behind it (step 9). In the EN25 and D139 evals the agents noticed and improvised. A 13-file, 48-line change got no outside reader, and `/en-fix` picks its depth from an instruction the agent got wrong once before correcting itself.

The user set the rule: every change gets a review, and only the depth varies. A small change gets a quick pass. A big or risky one gets different agents validating it before it ships. A script decides, not the agent.

## Requirements covered

No foundation requirement. This amends D79 (size does not gate `--lite`) and D139 (`/en-fix` picks its own review depth).

## Out of scope for this plan

- The `/en-fix` risk-surface override. It is the next PR and relies on the Full tier built here.
- A tier gate in `/en-ship` for branches that never ran `/en-fix`. See Decisions.
- `/en-plan`'s own peer skips. `skip_peer_below_lines` and `skip_peer_on_lightweight` keep working for plan documents.
- `/en-fix`'s plan check. It keeps the model's concept reading of `references/diff-signal-detection.md`.
- How research agents and `code-simplifier` start on Codex. They may inherit parent history too, which was not tested. U8 changes reviewers only.

## Approach (high-level)

A new script, `ensemble-review-tier`, classifies the branch diff into one of three tiers:

| Tier | When | Who reviews |
|---|---|---|
| `quick` | Under 50 lines, 10 files or fewer, no risk signal | Host only: the existing lite roster |
| `standard` | 50 to 300 lines, 10 files or fewer, no risk signal | Peer only, full brief |
| `full` | Over 300 lines, over 10 files, any risk signal, or a diff it cannot read | Host roster and peer together |

With no mode flag, `/en-review` runs what the tier says. An explicit `--peer`, `--host` or `--cross` still runs as asked, and the run reports the tier it actually reached. The model may raise the tier with a reason, for example when a conditional persona's heuristic fires, and never lowers it. No run may end with zero reviewers: whenever the peer is off, the host roster runs. When the cross-agent peer fails, the same peer pass reruns once in a fresh session of the host's own CLI, with no history from the session that wrote the code, so an outage does not stop a ship.

`/en-review` records the depth it reached in the verification receipt, and `/en-fix`'s receipt gate requires the tier the script computes on the final diff. A diff that grew during review therefore refuses to ship until it is reviewed at the new tier.

The script replaces prose: the diff-size peer skip, `is_low_risk`, `is_small_and_safe` and `/en-fix`'s size count all go.

Every reviewer, host or peer, runs outside the build session on every harness. Its context is its prompt, the files that prompt names and the project. On a live Codex 0.165 run, a `spawn_agent` child with `agent_type` and no `fork_turns`, which is how `/en-review` dispatches today, recited a secret word from the parent session. A child with `fork_turns="none"` did not, and that call also accepted a `model`. Fresh does not mean under-informed: host reviewers get the goal, the plan and the branch's commit messages, none of which they get today.

## Test seams

- **The script's CLI against throwaway git repos.** New, in the shape of `tests/en-ship/floor-guard.test.sh`. Every classification rule is tested here.
- **Skill wording pins under `tests/lint/`.** Existing. They hold the steps that consume the tier.
- **Behavioral evals under `tests/evals/`.** Existing, on demand, and the only seam that shows a real run honours the tier.

## Technical design

```text
git diff (merge base..working tree, untracked)
   -> ensemble-review-tier -> REVIEW_TIER, REVIEW_TIER_REASONS
   -> /en-review step 2a: tier + flags -> review mode, peer decision, depth
   -> steps 7-9: reviewers run; persona heuristics may raise the tier
   -> report and envelope: review_tier {required, ran, reasons}
   -> post-review check: receipt gains review_<tier> checks for the depth reached
   -> /en-fix receipt gate: rerun script, verify --requires ...,review_<required>
```

**The receipt holds only `passed` values**, so ordering is encoded by writing every check at or below the depth reached. A `full` run writes `review_quick`, `review_standard` and `review_full`. A gate then requires exactly `review_<required>`, and `ensemble-verification-receipt` does not change.

**A run that falls short of its own requirement records nothing.** `required` here is the run's effective tier, after any raise. When `ran` is below it, the run first removes any existing receipt, because `write` merges on an identical tree and an earlier `review_standard` would otherwise survive. It then writes only what its post-review check ran, with no `review_*` check. A raise therefore survives to the gate even though the gate recomputes only the script's tier: a script-`standard` diff raised to `full`, whose peer and fresh host session then both fail, is refused, whatever an earlier run recorded on that tree.

**What each run counts as (`ran`):**

| What ran | `ran` |
|---|---|
| Host lite roster, or a peer given the lite brief, or both | `quick` |
| Peer with the full brief alone, or full host roster alone | `standard` |
| Full host roster and peer, including `single-agent-fallback` | `full` |
| Full host roster where `PEER_AVAILABLE=false` (the user turned the peer off) | `full` |
| Full host roster and a fresh host session, after a `peer-failed:*` peer | `full` |
| Fresh host session alone, after a `peer-failed:*` peer | `standard` |
| Full host roster after the peer and the fresh host session both failed | `standard`, which is below a `full` requirement, so that run records no review check |

## Implementation units

### U1. Classify the diff with a script

- **Goal:** `ensemble-review-tier` prints the tier and why, the same way every time, for any branch diff.
- **Requirements covered:** none
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `ensemble-review-tier --base <ref> [--json]`. Default output is eval-able lines: `REVIEW_TIER='quick|standard|full'`, `REVIEW_TIER_REASONS='<comma-joined>'`, `REVIEW_TIER_FILES=<n>`, `REVIEW_TIER_LINES=<n>`. `--json` prints `{"tier","reasons":[],"files":n,"lines":n,"excluded":[],"risk":[{"signal","path"}]}`. Reasons: `empty-diff`, `under-limits`, `size-standard`, `over-300-lines`, `over-10-files`, `risk:<signal>`, `diff-unreadable`. Signals: `auth`, `payments`, `migrations`, `secrets`, `data-mutation`, `external-effects`, `dependency`. Exit 0 whenever a tier is printed, including the fail-closed `full`; exit 3 on bad usage.
- **Files:**
  - `skills/en-review/scripts/ensemble-review-tier` (create)
  - `skills/en-fix/scripts/ensemble-review-tier` (create)
  - `tests/en-review/review-tier.test.sh` (create)
- **Approach:** A bash shim that execs inline python3, as `skills/en-ship/scripts/ensemble-floor-guard` does, byte-identical in both skills (`tests/parity/script-parity.test.sh` discovers it). Read the diff from the merge base of `<ref>` and `HEAD` to the working tree, plus untracked files, with `-c core.quotePath=false`, `-M` and `-z` listings. Any git failure prints `full` with `diff-unreadable`.
  - **Size.** `files` and `lines` (insertions plus deletions) skip excluded files: lockfiles (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `poetry.lock`, `uv.lock`, `Pipfile.lock`, `Cargo.lock`, `Gemfile.lock`, `go.sum`, `composer.lock`), any path with a `generated` or `__generated__` segment, `*.min.js`, `*.min.css`, and files whose `linguist-generated` attribute is set. A binary file counts as one file and zero lines.
  - **Risk on paths,** matched case-insensitively on a whole segment or file name, against every changed path including excluded ones and both sides of a rename. `auth`: `auth`, `oauth`, `login`, `session`, `sessions`, `permissions`, `rbac`, `acl`. `payments`: `payment`, `payments`, `billing`, `invoices`. `migrations`: `migrations`, `alembic`, `schema.prisma`, `schema.sql`. `secrets`: `secrets`, `.env`, `.env.*`. `dependency`: `package.json`, `requirements*.txt`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`, `composer.json`, and every lockfile above.
  - **Risk on content,** over added and removed lines only. Skip files ending `.md`, `.mdx`, `.rst` or `.txt`, except `requirements*.txt`, and skip lines whose first non-space characters are `#`, `//`, `/*`, `*` or `--`. Split camelCase with an underscore first, then match case-insensitively with letters and digits as the only word characters, so `_`, `-` and `.` are boundaries. `auth`: `auth`, `token`, `access_tokens`, `refresh_tokens`, `auth_tokens`, `api_tokens`, `password`, `passwd`, `oauth`, `jwt`, `bearer`, `csrf`, `rbac`, `cookie`, `authorization`, `session`, `login`, `permission`, `permissions`. `payments`: `payment`, `payments`, `billing`, `invoice`, `stripe`, `refund`, `charge`. `secrets`: `secret`, `api_key`, `apikey`, `private_key`, `cors`, `content-security-policy`. `external-effects`: `webhook`, `smtp`, `sendgrid`, `twilio`. `data-mutation`: `backfill`. Case-sensitive over the raw line: `migrations`: `ALTER TABLE`, `CREATE TABLE`, `DROP (TABLE|COLUMN|SCHEMA|DATABASE|INDEX)`. `data-mutation`: `DELETE FROM`, `TRUNCATE`, `UPDATE \w+ SET`.
  - **Order.** No changed files: `quick` with `empty-diff`. Any risk: `full`. Over 10 files or over 300 lines: `full`. 50 lines or more: `standard`. Otherwise `quick`.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* 10 lines in 1 file gives `quick` with `under-limits`. 120 lines in 3 files gives `standard`. 301 lines gives `full` with `over-300-lines`. 11 files of one line each gives `full` with `over-10-files`.
  - *Edge case:* 49, 50, 300 lines and 10 files land on the table's boundaries. A 13-file, 48-line diff gives `full`. A 5,000-line `package-lock.json` alone gives `full` with `risk:dependency` and `lines` 0. 400 lines under `docs/generated/` plus 10 lines of source gives `quick`, with the generated file in `excluded`. An untracked new file counts. No changes gives `quick` with `empty-diff`. A path with a space, a non-ASCII name and a rename all classify correctly.
  - *Concept match:* `refresh_token`, `refreshToken` and `src/auth/x.js` give `risk:auth`. `max_tokens`, `maxTokens`, `author` and `oracle` give none. `token` only in a `//` comment, or only in a `.md` file, gives none. `const q = "DROP TABLE x"` gives `risk:migrations`, proving strings count. A removed line reading `password` counts.
  - *Error path:* A `--base` that does not resolve prints `full` with `diff-unreadable` and exits 0. A missing `--base` exits 3.
- **Verification:** `tests/en-review/review-tier.test.sh` passes, and `tests/parity/script-parity.test.sh` passes with both copies present. Negative controls: dropping the underscore boundary, or skipping removed lines, turns its assertion red.

### U2. Run what the tier says, and never run zero reviewers

- **Goal:** A bare `/en-review` maps tier to reviewers, and every peer-off path falls back to the host roster.
- **Requirements covered:** none
- **Dependencies:** U1
- **Interfaces:**
  - *Consumes:* `ensemble-review-tier` from U1.
  - *Produces:* envelope field `"review_tier": {"required": "<tier>", "ran": "<tier>", "reasons": []}`, summary line `review_tier: <ran> (required <required>; <files> files, <lines> lines; <reasons>)`, peer-decision reason `review-tier:quick`. All additive, except that a bare `/en-review` no longer always means peer-only.
- **Files:**
  - `skills/en-review/SKILL.md` (modify)
  - `skills/en-review/references/review-report.md` (modify)
  - `skills/*/references/peer-contract.md` (modify)
  - `skills/*/references/peer-model-policy.md` (modify)
  - `tests/lint/en-review-peer-default.test.sh` (modify)
  - `tests/lint/en-review-mutation-gate.test.sh` (modify)
- **Approach:** At the top of step 2a, for a branch-diff target (bare or `--base`), run the script and carry its result. An ad-hoc `--peer <path-or-ref>` and `--verify` are not branch reviews and skip it, with `review_tier` null.
  - **Mode.** No mode flag: `quick` is `--host` with the lite roster, `standard` is `--peer`, `full` is `--cross`. Report-only never runs a peer: `quick` uses the lite roster, and `standard` or `full` use the full host roster. An explicit `--peer`, `--host` or `--cross` runs as asked.
  - **Peer gate.** Replace the `skip_peer_below_lines` row and the `skip_peer_on_lightweight` row with `Tier quick, no mode flag | off | review-tier:quick`. An explicit `--peer` therefore always runs the peer, however small the diff. Add `review-tier:quick` to the closed enum in every `peer-contract.md` and `peer-model-policy.md` copy, keeping `auto-skip:diff-below-threshold` and `auto-skip:lightweight-depth`, which `/en-plan` reports.
  - **Raising.** After step 7's detection, a fired conditional persona raises a bare run below `full` to `full`, adding `conditional-persona:<names>` to `reasons`. A model may raise for any other reason it names. Nothing lowers the tier.
  - **Peer failure.** On any `peer-failed:*` decision, rerun the peer pass once in a fresh session of the host's own CLI, never in the reviewing session and never as a subagent. Rebuild the prompt with `--peer-mode single-agent-fallback` and call `ensemble_peer_invoke` with the host's values from `references/host-detect.md`: on Claude Code `claude -p`, `--output-format json`, `--max-turns 1`; on Codex `codex exec`, `--json`, no turn flag. Re-resolve `$PEER_MODEL` and `$PEER_EFFORT` through `ensemble-peer-flags` for that command, and keep the same access mode. Record `reviewer: single-agent-fallback`, and show the original `peer-failed:*` reason on the `peer_decision:` line, so the report never reads as a cross-agent pass.
  - **Zero reviewers.** Rewrite step 9's "Peer off" bullet: when the peer is off for any reason, including both the peer and the fresh session failing, and the run dispatched no personas, run the full host roster and treat its findings as the envelope. This covers `peer-unavailable` and `recursion-guard` under `standard`, and report-only.
  - **Wording.** Change "`--peer` is the default" at the flags table and the review-mode line to the tier mapping, and record `ran` per the Technical design table.
  - **Budget.** `skills/en-review/SKILL.md` sits at 25,297 of 26,624 bytes. Remove as much as this adds, and move detail to `review-report.md` if needed. The budget does not rise.
- **Risk:** high
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* pins hold the three mode mappings, `review-tier:quick` in the peer gate and every enum copy, and the envelope and summary shapes.
  - *Edge case:* an explicit `--peer` has no skip row left to hit, pinned by the absence of `skip_peer_below_lines` from `skills/en-review/SKILL.md`. Report-only is pinned to run no peer and a host roster.
  - *Error path:* the Peer failure bullet is pinned to rerun in a fresh session of the host's own CLI with `--peer-mode single-agent-fallback`, and to forbid a subagent. The rewritten Peer off bullet is pinned to dispatch the full host roster, so a peer and fresh session that both fail under `standard` cannot end with no reviewers.
- **Verification:** `./tests/select-for.sh skills/en-review/SKILL.md` passes, including `tests/lint/skill-size.test.sh` and `tests/parity/`. Negative control: restoring the old Peer off wording turns the pin red.

### U3. Move `--lite` and the effort ladder onto the tier

- **Goal:** `--lite` applies only to a `quick` diff, and the two prose classifications the script replaces are gone.
- **Requirements covered:** none
- **Dependencies:** U2
- **Files:**
  - `skills/en-review/SKILL.md` (modify)
  - `skills/en-review/references/persona-dispatch.md` (modify)
  - `skills/en-review/references/review-report.md` (modify)
  - `skills/*/references/peer-model-policy.md` (modify)
  - `skills/en-review/references/diff-signal-detection.md` (modify)
  - `skills/en-fix/references/diff-signal-detection.md` (modify)
  - `skills/en-qa/references/diff-signal-detection.md` (modify)
  - `tests/lint/en-review-lite.test.sh` (modify)
  - `tests/lint/diff-signal-detection.test.sh` (modify)
  - `tests/lint/en-review-peer-default.test.sh` (modify)
  - `tests/lint/en-review-mutation-gate.test.sh` (modify)
  - `tests/lint/conditional-pointers.test.sh` (modify)
  - `tests/lint/en-foundation-discovery.test.sh` (modify)
- **Approach:** Step 7a: the run's depth is lite only when the tier is `quick`. `lite_gate` is `applied` for any run at lite depth, including a bare `quick` run. `--lite` on `standard` or `full` is `overridden` with reasons, in this order: `diff-unreadable`, `size`, `risk-signal`, `conditional-persona:<names>`. With no `--lite` and a tier above `quick`, it is `not-requested`. Update the reason table in `review-report.md` and the Lite roster section of `persona-dispatch.md`, including the line "Size does not gate". Step 7b's rung 2 becomes: `low` when the tier is `quick`, so a small `--cross` from `/en-build` keeps its low effort. Delete `is_low_risk`, `is_small_and_safe`, `EXEC_LINES`, `UNCOUNTED_FILES` and the override-reason table from `diff-signal-detection.md`, keep the risk patterns, the concept rule and `needs_browser`, and add one line saying `ensemble-review-tier` owns review depth while this file serves `/en-fix`'s plan check and `/en-qa`. Copy the file to all three skills.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* pins hold the `lite_gate` forms for a `quick` run, and for `--lite` on a `standard` diff (`overridden (size)`).
  - *Edge case:* a `--lite` on a `full` risky diff reports `overridden (risk-signal)`, or `overridden (size, risk-signal)` when both hold, in that fixed order. A `--lite` when the script could not read the diff reports `overridden (diff-unreadable)`.
  - *Error path:* no skill or reference under `skills/` still names `is_low_risk` or `is_small_and_safe`, pinned as an absence check.
- **Verification:** `./tests/select-for.sh skills/en-review/SKILL.md skills/en-review/references/diff-signal-detection.md` passes, including `tests/parity/`.

### U4. Apply the concept rule to the security persona's keywords

- **Goal:** `max_tokens` stops firing the security persona, which today overrides `--lite` and pushes peer effort to `high`.
- **Requirements covered:** none
- **Dependencies:** none
- **Files:**
  - `skills/en-review/references/persona-dispatch.md` (modify)
  - `tests/lint/en-review-mutation-gate.test.sh` (modify)
- **Approach:** At the head of `## Detection heuristics`, add one rule: a keyword names a concept, not a substring, read the way `references/diff-signal-detection.md` says, and a hit whose meaning is unclear still fires. The keyword lists themselves do not change. Add the pin to `tests/lint/en-review-mutation-gate.test.sh`, next to the existing persona pins.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* a pin requires the rule under `## Detection heuristics`, and that it cites `references/diff-signal-detection.md`.
  - *Edge case:* the pin also requires "still fires" for an unclear hit, so the rule cannot read as a blanket skip.
- **Verification:** the pin passes, and goes red with the rule removed. The `fix-max-tokens` eval in U7 shows the behaviour.

### U5. Record the tier in the receipt and gate `/en-fix` on it

- **Goal:** `/en-fix` picks no depth itself, and refuses to ship a final diff reviewed below its tier.
- **Requirements covered:** none
- **Dependencies:** U2, U3
- **Interfaces:**
  - *Produces:* receipt checks `review_quick`, `review_standard`, `review_full`, written at or below the depth reached.
  - *Consumes:* `REVIEW_TIER` from U1, `ran` from U2.
- **Files:**
  - `skills/en-review/references/post-review-check.md` (modify)
  - `skills/en-fix/SKILL.md` (modify)
  - `tests/lint/en-fix.test.sh` (modify)
  - `tests/lint/en-review-receipt.test.sh` (modify)
- **Approach:** In `post-review-check.md`, the success write on a bare branch diff adds one `--check review_<tier>=passed` per tier at or below `ran`, and adds none when `ran` is below the run's effective `required`. In that case it first runs `rm -f "$(git rev-parse --git-dir)/ensemble/receipt.json"`, so no earlier review check on this tree survives; lint and test evidence is simply recorded again. When a valid receipt let the check skip the tests, still write those review checks, since the review did run on this tree and `write` merges on an identical tree. Runs that write no receipt today (`--defer-tests`, report-only, any other target) still write none, so `/en-build` is unchanged.

  In `/en-fix`, the Review step invokes `/en-review --mode headless` with no target and no depth flag, removing the shortstat count and the 10-file, 300-line rule. The Receipt gate first runs `eval "$(bash "$SKILL_DIR/scripts/ensemble-review-tier" --base <default branch>)"`, then adds `review_$REVIEW_TIER` to `--requires`. A refusal naming `review_<tier>` stops the run and names the next command: `/en-review --mode headless`, then `/en-ship`, never a fresh `/en-fix`. Update `## Stops and resuming`, the description, and the Excuses row about `--lite`.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a scratch repo receipt holding `review_quick` and `review_standard` passes `verify --requires review_standard`, in `tests/lint/en-review-receipt.test.sh`.
  - *Edge case:* the same receipt fails `verify --requires review_full` with `check-not-recorded`, the refusal a diff that grew during review produces. A `full` run's three checks pass a `review_quick` requirement.
  - *Raised tier:* `post-review-check.md` is pinned to write no `review_*` check when `ran` is below the effective `required`. In a scratch repo, write a receipt holding `lint` and `review_standard`, remove it the way the pinned command does, and write `lint` alone on the same tree: `verify --requires review_standard` then fails with `check-not-recorded`. This is the refusal for a script-`standard` diff, already reviewed once, raised to `full` on a later run whose peer and fresh host session both failed.
  - *Error path:* `en-fix.test.sh` pins that the Receipt gate requires `review_$REVIEW_TIER`, runs the script, and stops on refusal. It also pins the absence of `--lite` and of a size count from the Review step.
- **Verification:** both test files pass. Negative control: removing `review_$REVIEW_TIER` from the gate turns the pin red.

### U6. Update callers and the record

- **Goal:** Every document and caller says what now happens, and D139's wrong claim is corrected.
- **Requirements covered:** none
- **Dependencies:** U5
- **Files:**
  - `docs/foundation.md` (modify)
  - `README.md` (modify)
  - `.ensemble/config.local.example.yaml` (modify)
  - `skills/en-setup/references/templates/config-local-example.yaml` (modify)
  - `skills/en-sweep/SKILL.md` (modify)
  - `skills/en-loop/SKILL.md` (modify)
- **Approach:** Add D140 to `docs/foundation.md`, amending D79 and D139, naming the three tiers, the script, the gate and the zero-reviewer rule. Correct D139, which says the security persona's keywords only cost a reviewer: they also override `--lite` and raise peer effort, and U4 changes them. Update the `en-review` and `en-fix` catalog rows, and §5.2.5 and §5.2.18. Reword the `skip_peer_below_lines` comments in both config examples and in `README.md` to say they apply to `/en-plan`'s plan documents. `setup` and foundation's config block keep the key.

  `/en-sweep`: step 13 gains that report-only runs the host roster per tier. `/en-loop`: its checkpoint keeps the explicit `--peer`, which now always runs the peer, and says so. `/en-build` keeps `--cross` and `--review peer` unchanged, and needs no edit.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test expectation:** none, because the unit is documentation and caller wording, covered by `bin/ensemble-lint` and the suite's existing wording pins.
- **Verification:** `bin/ensemble-lint --scope docs/foundation.md` is clean. `./tests/select-for.sh` passes on the changed paths.

### U7. Measure it with real runs

- **Goal:** Real sessions show a small diff gets a reviewer, a wide one gets both, and the gate holds.
- **Requirements covered:** none
- **Dependencies:** U5, U6, U8
- **Files:**
  - `tests/evals/grade` (modify)
  - `tests/evals/run-behavioral` (modify)
  - `tests/evals/grade.test.sh` (modify)
  - `tests/evals/README.md` (modify)
  - `tests/evals/ledger.md` (modify)
  - `tests/evals/behavioral/review-tier-quick/` (create)
  - `tests/evals/behavioral/review-tier-wide/` (create)
  - `tests/evals/behavioral/review-tier-small-auth/` (create)
- **Approach:** `grade review` reads a new optional `tier` key and compares it with `envelope.review_tier.required`, and a new optional `ran` key with `.ran`. `modes` gains `auto`, for which `run-behavioral` appends no mode flag, so the tier decides. Cases, all `auto`: `review-tier-quick` plants one logic defect in a diff under 50 lines, with `tier: quick` and recall 1.0, which proves a host reviewer ran. `review-tier-wide` is 13 files and 48 lines, with `tier: full`, `ran: full`, and `personas_include: ["correctness"]`. `review-tier-small-auth` is a 5-line change under `src/auth/`, with `tier: full` and a planted defect. Then rerun `fix-wide-change`, `fix-max-tokens` and `fix-real-token`, one run each. Finally run `review-tier-wide` once with a stub `codex` on `PATH` that exits 1, which must end with `ran: full` and `reviewer: single-agent-fallback`. Delete the stub afterwards; it is never committed. Last, run the fresh-context check on a Codex host: a secret word in the parent session, then a child dispatched exactly as `persona-dispatch.md` says, which must not recite it. `tests/evals/README.md` carries that prompt, because it is a manual check and not a case. Record all eight in the ledger.
- **Risk:** low
- **Category:** diagnostics
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* `grade.test.sh` grades a recorded envelope whose `review_tier` matches `tier` and `ran` as a pass, and `grade validate` accepts all three cases and `modes: ["auto"]`.
  - *Error path:* an envelope with `required: standard` against `tier: quick` fails and names both. An envelope with no `review_tier` fails when `tier` is set.
  - *Integration:* `run-behavioral review-tier-quick --dry-run` prints an invocation with no mode flag.
- **Verification:** `tests/evals/grade.test.sh` passes. The ledger holds the eight real results, and any failure is reported with its cause, suspecting the grader first per `tests/evals/README.md`.

### U8. Keep every reviewer out of the build session, and give it what it needs

- **Goal:** No reviewer on any harness sees the build session, every reviewer can still choose its model, and each gets the goal, the plan and the branch's commit messages, without `skills/en-review/SKILL.md` growing.
- **Requirements covered:** none
- **Dependencies:** U2, U3
- **Interfaces:**
  - *Produces:* `ensemble-build-peer-prompt --plan-file <path>`, optional, adding a `## Plan` section to the prompt. `dimension-reviewer` inputs `goal`, `plan` and `commits`. Finding titles prefixed `Plan coverage:`.
- **Files:**
  - `skills/en-review/SKILL.md` (modify)
  - `skills/en-review/references/persona-dispatch.md` (modify)
  - `skills/en-review/agents/dimension-reviewer.md` (modify)
  - `skills/en-review/references/review-report.md` (modify)
  - `skills/*/references/agent-dispatch.md` (modify)
  - `skills/en-review/references/peer-brief.md` (modify)
  - `skills/en-review/scripts/ensemble-build-peer-prompt` (modify)
  - `skills/en-test-audit/scripts/ensemble-build-peer-prompt` (modify)
  - `docs/foundation.md` (modify)
  - `tests/lint/en-review-lite.test.sh` (modify)
  - `tests/lint/en-review-peer-default.test.sh` (modify)
  - `tests/lint/peer-prompt-contract.test.sh` (modify)
- **Approach:** State the rule once, at the head of `persona-dispatch.md`'s Parallel dispatch section: "A reviewer's context is its prompt, the files it names and the project. The build session is not part of it."
  - **Codex dispatch.** Replace "In Codex: equivalent `spawn_agent` calls in a batch" with calls that keep `agent_type: "dimension-reviewer"` and add `fork_turns: "none"`, plus `model: $AGENT_MODEL` from `ensemble-agent-model --tier <tier>` when non-empty. A refused model retries once without `model` and is named in the run summary. A CLI whose `spawn_agent` has no `fork_turns` still runs, and the summary says `host_context: inherited`. `ensemble-build-peer-prompt` keeps its two identical code-review copies identical, and the plan and foundation variants do not change. Correct "selects nothing per call" in every `agent-dispatch.md` copy, and "not bound per call" in `persona-dispatch.md`.
  - **What reviewers get.** After step 5, write two files to the run directory: the plan with its frontmatter and its `## Iteration log` section removed, so no earlier verdict reaches a reviewer, and `git log --format='%h %s%n%b' <base>..HEAD`. Its `## Decisions, assumptions & risks` section stays visible, and a reviewer may challenge it. Each `dimension-reviewer` prompt names those paths under `plan` and `commits`, and carries `goal`. The peer gets the same copy through `--plan-file`, except on the verification pass and the lite brief. No tool changes: `dimension-reviewer` keeps exactly `Read, Grep, Glob`, as `tests/lint/agent-tool-restrictions.test.sh` requires.
  - **Goal.** `--goal` and the `goal` input come from the plan's or the request's own words. They state what the change is for, and never a verdict such as "simple fix" or "tests pass".
  - **Plan check.** Add one row to `### correctness` in `skills/en-review/references/peer-brief.md`, the only copy with that section, for a review given a plan: Missing, Unasked-for and Implemented but wrong, each citing the U-ID, with its title prefixed `Plan coverage:`. Correctness prompts already extract those rows, so `correctness` on a roster and the peer on its own both carry the check, and no reviewer is added. Step 7c shrinks to: findings with that prefix are listed apart and never reranked against the rest, and with no plan, or with a lite-brief peer alone, say so in Coverage.
  - **`fast-pass`.** Delete it from the lite roster at `SKILL.md` step 7a and the flags table, and from `persona-dispatch.md`. It has no dispatch, so it could only run inside the reviewing session.
  - **Record.** Add D141 to `docs/foundation.md`.
  - **Budget.** `skills/en-review/SKILL.md` must not grow from this unit: moving 7c's detail out pays for the rest.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* pins hold the rule sentence, `fork_turns: "none"` and `model: $AGENT_MODEL` on the Codex dispatch, and the `Plan coverage:` row in `### correctness`. `ensemble-build-peer-prompt --plan-file` puts the plan in the prompt, and leaving it out adds no `## Plan` section.
  - *Edge case:* a fixture plan with `peer_review_verdict` in its frontmatter and a `## Iteration log` followed by another section keeps that later section and `## Decisions, assumptions & risks`, and loses both the verdict and the log.
  - *Error path:* a missing `--plan-file` path exits 2, as a missing artifact does. Pins require the retry without `model` and the `host_context: inherited` line. `fast-pass` is absent from `skills/en-review/`, pinned as an absence check.
- **Verification:** `./tests/select-for.sh skills/en-review/references/persona-dispatch.md skills/en-review/scripts/ensemble-build-peer-prompt` passes, including `tests/lint/skill-size.test.sh`, `tests/lint/agent-tool-restrictions.test.sh` and `tests/parity/`. `skills/en-review/SKILL.md` is no larger than before this unit. Negative control: removing `fork_turns` from the dispatch turns the pin red. The live Codex check in U7 shows the behaviour.

## Decisions, assumptions & risks

- **Decision:** Only `/en-fix` enforces the tier, as the user approved. `/en-build` always runs `--cross`, the top depth, with its own trailer audit. `/en-sweep` writes no receipt. An explicit `--peer` or `--host` remains a person's choice, and `ran` reports what it reached.
- **Decision:** A peer outage does not stop a ship. The user ruled on 2026-11-04: when Codex fails, ship on a host review run in a separate session with no history. A `peer-failed:*` pass therefore reruns in a fresh session of the host's own CLI, the mechanism `single-agent-fallback` already uses, and counts toward `full`. This reverses the earlier stop-the-ship answer, and it changes `/en-build` too, since step 9 is shared and `ensemble-verify-peer-evidence` already accepts that reviewer.
- **Decision:** If the peer and the fresh session both fail under `full`, the run counts as `standard` and records no review check, so `/en-fix` stops. No separate session could run at all, so this is more than a Codex outage. `PEER_AVAILABLE=false` counts as `full`, because it means the user turned the peer off. A machine with no second CLI is already `single-agent-fallback`, which is a fresh session.
- **Decision:** `is_low_risk` and `is_small_and_safe` are deleted, not kept beside the script. Keeping them leaves two size definitions (39 executable lines and 50 changed lines) that would drift.
- **Decision:** Thresholds are constants in the script, not config. `skip_peer_below_lines` no longer affects `/en-review`, including for anyone who set it to a custom value. The gate would otherwise depend on per-machine config.
- **Alternative:** A separate `verify` subcommand comparing tier ranks. Rejected: writing every check at or below `ran` lets the existing receipt gate do the comparison with no new code in a script four skills carry.
- **Alternative:** Tiering only inside `/en-fix`. Rejected: a bare `/en-review` under 50 lines would keep having no reviewer.
- **Decision:** Reviewers see the plan's decisions section, as the user chose on 2026-11-04. It explains why code looks the way it does, and a reviewer may still challenge it. `ce-code-review` withholds settled decisions and filters afterwards, which reads more independently but adds noise and leaves the build session doing the filtering.
- **Decision:** The plan check goes to a reviewer already running, not a new dispatch, so a plan-backed review costs no extra agent. On `--cross` both `correctness` and the peer make it, and agreement corroborates as usual.
- **Decision:** Host reviewers get the branch's commit log as a file, not a shell. It keeps the read-only guard and adds no tool. They lose `git blame` on older code, which `ce-code-review`'s reviewers have. Add it only if evals show false positives on deliberate code.
- **Decision:** Unlike `ce-code-review`'s lite path, the Quick tier still dispatches fresh reviewers, because the user's rule covers every review.
- **Assumption:** The lite roster of `correctness` + `standards` is what the user means by the quick pass. The user named those two; `fast-pass` is removed in U8.
- **Risk:** `model` is accepted on Codex, but the spawn result does not report which model served the call, so the override is unproved. **Mitigation:** The rendered agent TOML remains the default, and a refused model falls back and is named in the summary.
- **Risk:** A Codex CLI with no `fork_turns` still leaks parent history. **Mitigation:** The summary says `host_context: inherited`, so it is visible rather than silent. This is the one known exception to the fresh-session rule.
- **Risk:** Inlining the plan grows the peer prompt, by about 9,400 tokens for a plan this size, estimated at four bytes a token. **Mitigation:** The verification pass and lite peer omit it. Codex host reviewers also stop carrying build history, a saving not yet measured.
- **Risk:** The risk match is a word list, and code can avoid it by naming. **Mitigation:** It decides review depth, not safety, and `/en-guardrail` and `/en-fix`'s plan check are separate. It only raises the tier, and persona heuristics can raise it further. `/en-review` is not a security boundary against a hostile author, unlike the guardrail matcher that `docs/learnings/` warns about.
- **Risk:** A false-positive word such as a lexer's `token` sends a small diff to `full`. **Mitigation:** The cost is minutes of review. The user accepted that trade.
- **Risk:** A dishonest agent could write `review_full` without running it, as with any receipt check. **Mitigation:** The envelope and `peer_decision` line remain visible in the report. The threat here is an agent's mistake, which a recorded tier does catch.
- **Risk:** More peer and host time on larger changes. **Mitigation:** Accepted by the user. `bin/ensemble-metrics --time` can show the effect afterwards.
- **Risk:** Installed copies lag the repo until `~/.ensemble-source` is updated. **Mitigation:** Update after merge, as with EN25.

## Tracked debt

None resolved. If `/en-ship` should later enforce the tier for branches that skip `/en-fix`, file it then with evidence that it happens.

## Iteration log

> - 2026-11-04 (initial): plan v0 from the user-approved tier design, in conversation after D139 shipped.
> - 2026-11-04 (peer pass 1, revise): applied 1-1, a run below its own effective tier records no review check, so a raised tier survives to the gate. Applied 1-2, `diff-unreadable` joins the `--lite` override reasons.
> - 2026-11-04 (peer pass 2, revise): applied 2-1, a run below its effective tier removes the existing receipt first, since receipt writes merge on an identical tree. The iteration cap is reached, so this fix has no further peer pass. The user accepted the plan as-is on 2026-11-04, and chose that a failed peer under `full` stops the ship.
> - 2026-11-04 (user correction after promotion): the user reversed that choice. A failed peer now reruns in a fresh host session and the ship continues; it stops only if that session fails too. Plan hash recomputed; no further peer pass, per the cap.
> - 2026-11-04 (user addition after promotion): added U8 after a live Codex test and a comparison with `ce-code-review`; U7 gains the live check and depends on U8. The user approved it and kept the decisions section visible. Plan hash recomputed. U8 has had no peer pass, per the cap, so the verdict above does not cover it.
