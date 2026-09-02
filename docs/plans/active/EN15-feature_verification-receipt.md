---
type: plan
plan_type: feature
plan_id: EN15
title: Verification receipt, structured ship state, and a test-impact map
status: in_progress
location: active
created: 2026-09-01
shipped:
deepened:
covers_requirements: []
requirements_pending: true
related_design:
peer_review_verdict:
peer_review_iterations: 0
peer_review_last_run:
peer_review_plan_hash:
peer_review_resolutions: []
depth: standard
data_scale: small
---

# EN15 — Verification receipt, structured ship state, and a test-impact map

## Context

A Codex post-mortem on a shipped PR measured four layers verifying the same tree with no way to
see each other's results: `/en-build` ran the full suite (4,778 tests), `/en-ship` then ran lint,
typecheck and 506 targeted tests, the project's pre-push hook then ran 439 more *seconds later on
the identical tree*, and CI ran the authoritative suite at 16m 11s. Each layer is individually
justified. The waste is that none of them can tell another already answered the question.

This is Tier 2 of the en-ship review (D57 shipped Tier 1). It was deliberately held back from that
PR because it is a protocol across `/en-build`, `/en-ship`, a pre-push hook Ensemble does not model,
and `AGENTS.md` — and because a receipt with wrong invalidation rules silently ships untested code,
which is worse than the duplication it removes.

## Requirements covered

None — `docs/foundation.md` carries no R-IDs (`requirements_pending: true`). The driver is D57's
deferred tier plus the measured post-mortem above.

## Out of scope for this plan

- **Installing a pre-push hook.** Hooks are project-owned, and `/en-ship` never bypasses them. This
  plan publishes a receipt and a verify command a project's *existing* hook can call, and nothing more.
- **Selecting "tests covering the incoming base delta."** Codex proposed this as a receipt branch. It
  is test-impact analysis, which U7 shows this repo cannot do reliably yet, and a receipt that
  silently under-tests is worse than no receipt. Base moved → receipt invalid → run the checks.
- **The other two helpers Codex proposed** (`ensemble-verification-receipt verify` is U1;
  `ensemble-pr-state --json` is not built). Four helpers is a lot of carried surface for one skill;
  two plus the receipt tool is the smallest set that removes real prose.
- **Sharing receipts between machines or into CI.** The receipt is local, uncommitted, and worthless
  to anyone else. CI remains the independent authority and never reads one.

## Approach (high-level)

A **verification receipt** is a small JSON file under `.git/ensemble/` recording which checks passed
against an exactly-identified working tree. Whoever runs an expensive check writes one; whoever is
about to run the same check reads it and skips only on an exact match. `.git/` is the right home:
it is per-clone, already ignored, never committed, and disappears with the checkout — a receipt can
never outlive the tree it describes or travel to a machine it does not describe.

The fingerprint covers the committed tree, every tracked modification, and untracked non-ignored
files, so any change to what tests read invalidates it. Validity is deliberately **conservative and
all-or-nothing**: fingerprint, base SHA, dependency hashes and a TTL must all hold, or the receipt
is discarded and the checks run. There is no partial credit and no delta reasoning, because every
clever invalidation rule is a way to ship untested code.

The two structured helpers replace the parts of `/en-ship` where prose reconstructs state the shell
already knows — git and staging state, and the plan checkpoint. The test-impact map replaces a
filename heuristic that silently selects zero tests in any layout where tests do not sit beside
sources.

## Test seams

- **`tests/verification-receipt/`** — new, following the existing pattern of `tests/en-guardrail/`
  and the `ensemble-verify-peer-evidence` suite: drive the real script against fixture repos created
  with `git init` in a temp dir, assert on exit codes and `--json` output. This is the highest seam
  that can observe the invalidation rules, and it is where the risk of this plan concentrates.
- **`tests/lint/en-ship-preflight.test.sh`** — exists (D57). Extended for receipt consumption and
  test-impact selection, as prose-drift assertions.
- **`tests/lint/en-build-suite-sequencing.test.sh`** — exists. Extended to assert en-build writes a
  receipt at its gate.
- No new seam for `AGENTS.md` schema: the map is data, checked by the helper that reads it.

## Technical design

Three architecture triggers fire (≥3 changed components, a ≥3-step protocol, ≥3 data-flow stages),
so this section is directional, not a spec.

**Components and the protocol between them**

```
  /en-build  ── writes ──►  .git/ensemble/receipt.json  ◄── reads ──  /en-ship
   (10.4, after                    ▲                                    (preflight)
    the full suite)                │
                                   └── verify ── project's pre-push hook
                                                  (calls the helper; we never install it)

  ensemble-verification-receipt   write | verify | show     ← the only writer/reader of the format
```

**Receipt shape** (illustrative, U1 owns the exact schema):

```json
{
  "schema": 1,
  "source_fingerprint": "<sha256>",
  "head_sha": "<sha>",
  "base_ref": "origin/main",
  "base_sha": "<sha>",
  "dependency_hashes": { "uv.lock": "<sha256>", "frontend/bun.lock": "<sha256>" },
  "checks": { "full_suite": "passed", "lint": "passed", "typecheck": "passed" },
  "written_by": "en-build",
  "written_at": "2026-09-01T10:04:00Z",
  "repo_path": "/abs/path/to/checkout"
}
```

**Fingerprint** — `sha256` over the concatenation of `git rev-parse HEAD^{tree}`, `git diff HEAD`
(all tracked modifications, staged and unstaged), and the sorted content hashes of
`git ls-files --others --exclude-standard`. Any change a test could read moves it.

**Validity is a conjunction.** A receipt is usable only when *every* clause holds: fingerprint
matches, `base_sha` still matches `git rev-parse <base_ref>`, every `dependency_hashes` entry still
matches, `repo_path` matches this checkout, and `written_at` is within the TTL. Any failure returns
the *reason* and the consumer runs the checks. A consumer never reasons about which subset of checks
might still apply.

**Consumers ask for what they need.** `verify --requires full_suite,lint` succeeds only when the
receipt is valid *and* records those checks as passed, so `/en-ship` and a hook can want different
things from one receipt.

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. Receipt schema and the `ensemble-verification-receipt` helper

- **Goal:** One executable that owns the receipt format — writing, verifying, and explaining refusals.
- **Requirements covered:** —
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `ensemble-verification-receipt write --check <name>=<passed|failed> [--base <ref>] [--dep <path>]…`; `verify [--requires a,b] [--json]`; `show [--json]`. Exit `0` valid, `1` invalid-with-reason, `2` no receipt, `3` usage error.
  - *Consumes:* nothing.
- **Files:** `skills/en-build/scripts/ensemble-verification-receipt`, `skills/en-ship/scripts/ensemble-verification-receipt` (byte-identical carriers), `tests/verification-receipt/receipt.test.sh`
- **Approach:** POSIX shell plus `python3` for JSON and hashing, matching `ensemble-verify-peer-evidence`. `verify` prints a machine-readable `reason` on every refusal (`no-receipt`, `fingerprint-mismatch`, `base-moved`, `dependency-changed`, `wrong-repo`, `expired`, `check-not-recorded`) so consumers can report *why* they are re-running rather than saying "no receipt".
- **Risk:** medium
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* write with `full_suite=passed` on a clean fixture repo, then `verify --requires full_suite` → exit 0.
  - *Edge case:* untracked non-ignored file created after the write → `verify` exits 1, reason `fingerprint-mismatch`. Then the same file added to `.gitignore` → still valid, because ignored files are excluded by construction.
  - *Edge case:* receipt written, then `git commit` with no content change to the tree (amend of message only) → tree fingerprint unchanged, so still valid; asserted so a future refactor does not accidentally bind validity to `head_sha`.
  - *Error path:* `base_sha` advanced on the remote → exit 1, reason `base-moved`. A lockfile edited → reason `dependency-changed`. Receipt copied into a different checkout → reason `wrong-repo`. `written_at` older than TTL → reason `expired`.
  - *Error path:* `verify --requires lint` against a receipt recording only `full_suite` → exit 1, reason `check-not-recorded`. A truncated or non-JSON receipt file → exit 1, never a crash and never a false pass.
  - *Integration:* `verify --json` emits `{valid, reason, checks, age_seconds}` parseable by `python3 -c`.
- **Verification:** `bash tests/verification-receipt/receipt.test.sh` green; `bash tests/run.sh` green.

### U2. `/en-build` writes a receipt at its full-suite gate

- **Goal:** The layer that already ran the expensive suite records that it did.
- **Requirements covered:** —
- **Dependencies:** U1
- **Interfaces:** *Consumes:* `ensemble-verification-receipt write` from U1.
- **Files:** `skills/en-build/SKILL.md`, `tests/lint/en-build-suite-sequencing.test.sh`
- **Approach:** At step 10.4, after the suite passes and D53's single-suite rule is satisfied, write the receipt recording `full_suite`, plus `lint` and `typecheck` from the step 10.1 gate. Write **only on pass** — a receipt is evidence something succeeded, never a record that it ran. A failed write is a warning, never a build failure: the receipt is an optimisation and must never become a way for the build to fail.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* en-build's SKILL.md names the write at step 10.4, after the suite and before the commit trailers — asserted by ordering, not just presence.
  - *Edge case:* the prose states the write happens only on a passing suite.
  - *Error path:* the prose states a failed receipt write does not fail the build.
  - **Test expectation:** prose-drift assertions only; the behaviour is en-build's, which has no executable harness.
- **Verification:** `bash tests/lint/en-build-suite-sequencing.test.sh` green, with each new clause negative-controlled.

### U3. `/en-ship` consumes the receipt in preflight

- **Goal:** Skip local checks that a valid receipt already proves, and say so.
- **Requirements covered:** —
- **Dependencies:** U1
- **Interfaces:** *Consumes:* `ensemble-verification-receipt verify --requires …` from U1.
- **Files:** `skills/en-ship/SKILL.md`, `skills/en-ship/scripts/ensemble-verification-receipt`, `tests/lint/en-ship-preflight.test.sh`
- **Approach:** Step 5 calls `verify --requires lint,typecheck,full_suite` **after** the step-3 base-freshness gate, because that gate is what makes `base-moved` detectable. On exit 0, skip and report which checks the receipt covered and how old it is. On any non-zero, run the checks and **report the reason verbatim** — a silent re-run teaches nobody, and a silent skip is the failure this plan exists to avoid.
  Secret scanning and `git diff --check` always run regardless of any receipt: they are cheap, and they answer a question about the diff rather than about the tree's tests.
- **Risk:** high
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* the skill names the `--requires` call and states which checks a valid receipt permits skipping.
  - *Edge case:* the skill states that the secret scan and `git diff --check` are never skipped.
  - *Error path:* the skill states that every refusal reason is surfaced, and that an invalid receipt means run everything — with no partial-credit path.
  - *Error path:* a guard asserts the skill contains no text permitting a subset re-run based on what changed, so Codex's "tests covering the base delta" cannot be reintroduced by a later editor.
  - *Integration:* receipt consumption is ordered after the base-freshness gate from D57.
- **Verification:** `bash tests/lint/en-ship-preflight.test.sh` green; ordering asserted structurally.

### U4. Pre-push hook integration contract

- **Goal:** Let a project's existing hook reuse the receipt, without Ensemble owning the hook.
- **Requirements covered:** —
- **Dependencies:** U1
- **Files:** `skills/en-ship/references/verification-receipt.md`, `skills/en-setup/SKILL.md`
- **Approach:** A reference page documenting the format, the verify contract, and a copy-pasteable
  hook fragment the user installs themselves. `/en-setup` surfaces it as an informational line in its
  report — it does **not** write or modify a hook, because a hook is where a project encodes its own
  policy and silently editing one is the kind of help nobody asked for.
- **Risk:** medium
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - **Test expectation:** none — documentation plus one informational line; the behaviour it describes is covered by U1's suite.
- **Verification:** payload check clean (the new reference is reached from en-ship's body); `/en-setup` prose asserts it never writes a hook.

### U5. `ensemble-ship-preflight --json`

- **Goal:** Return git, base and staging state as data instead of reconstructing it in prose.
- **Requirements covered:** —
- **Dependencies:** none
- **Interfaces:** *Produces:* `{branch, base_ref, ahead, behind, detached, conflicted, published, staged[], scope_matched[], excluded[], untracked_inventory[], predicted_conflicts[]}`.
- **Files:** `skills/en-ship/scripts/ensemble-ship-preflight`, `tests/verification-receipt/ship-preflight.test.sh`, `skills/en-ship/SKILL.md`
- **Approach:** Wrap the shell D57 already specifies in step 3 and step 7 — fetch, ahead/behind, `merge-tree`, untracked inventory, and the five-case staging classification — and return the answer. The SKILL.md prose then *describes the decision*, and stops re-deriving the state. Read-only: it classifies, it never stages.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* fixture repo, clean tree, 2 commits ahead → `ahead: 2`, `scope_matched: []`, staging case `push-existing`.
  - *Edge case:* tracked modification in scope plus an unrelated untracked file → the first is in `scope_matched`, the second in `excluded` and in `untracked_inventory`, never in `staged`.
  - *Edge case:* nothing ahead and nothing in scope → the no-op case is returned as a named state, not an empty object a caller must interpret.
  - *Error path:* detached HEAD → `detached: true` and a non-zero exit, so the caller cannot proceed by ignoring a field.
  - *Error path:* base ref that does not exist → non-zero with a reason, not a silent `behind: 0`.
- **Verification:** its own test file green; `tests/run.sh` green.

### U6. `ensemble-plan-checkpoint --json`

- **Goal:** Compute D57's four checkpoint outcomes mechanically.
- **Requirements covered:** —
- **Dependencies:** none
- **Interfaces:** *Produces:* `{outcome, covered_units[], missing_units[], deferred_units[], plan_path, plan_status}` where `outcome` is one of D57's four.
- **Files:** `skills/en-ship/scripts/ensemble-plan-checkpoint`, `tests/verification-receipt/plan-checkpoint.test.sh`, `skills/en-ship/SKILL.md`
- **Approach:** Wrap `ensemble-verify-peer-evidence --branch-coverage`, read the plan's U-IDs and each unit's `Ship scope:`, and resolve exactly one outcome. This is the largest prose block in en-ship and the one whose logic is most mechanical; moving it removes the most text for the least behavioural change.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* every U-ID in `covered_units` → `complete`.
  - *Edge case:* U8 missing but declaring `Ship scope: production_pending` → `partial_expected`, with U8 in `deferred_units` and not in `missing_units`.
  - *Edge case:* a unit missing with `Ship scope: in` but an implementing commit on the branch → `complete_evidence_missing`.
  - *Error path:* a unit with neither coverage nor a commit → `incomplete_unexpected`.
  - *Error path:* no plan file for the branch → `not_applicable`, exit 0 — not an error, because most branches are not plan branches.
- **Verification:** its own test file green, with one fixture per outcome.

### U7. Test-impact map in `AGENTS.md`

- **Goal:** Let a project state where its tests live, instead of guessing.
- **Requirements covered:** —
- **Dependencies:** none
- **Files:** `skills/en-foundation/references/templates/agents-md-template.md`, `skills/en-setup/references/templates/agents-md-template.md`, `skills/en-ship/references/test-impact.md`
- **Approach:** An optional `## Test impact` section in `AGENTS.md` carrying either a
  `test_changed_command:` (a project-specific command, which wins outright) or a `test_impact:` prefix
  map from source directory to test directory. **`AGENTS.md`, not `.ensemble/config.local.yaml`:** the
  map must be shared with the team and with CI, and `config.local.yaml` is gitignored.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - **Test expectation:** none — a template section and a reference page; the parsing it enables is tested in U8.
- **Verification:** both template carriers stay byte-identical; payload check clean.

### U8. `/en-ship` selects tests from the map and reports why

- **Goal:** Replace the sibling-filename heuristic, and make the selection auditable.
- **Requirements covered:** —
- **Dependencies:** U7
- **Files:** `skills/en-ship/SKILL.md`, `tests/lint/en-ship-preflight.test.sh`
- **Approach:** Step 5 resolves the test set in a fixed order: `test_changed_command` if present, else
  the `test_impact:` prefix map, else the existing sibling-filename heuristic as the fallback for
  projects that have declared nothing. **Report why each test was selected** and, critically, say so
  when the selection is **empty** — the current failure is silent, where a heuristic that matches
  nothing reports a pass having run no tests at all.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* the skill names the three-tier resolution order explicitly.
  - *Edge case:* the skill states that an empty selection is reported as empty, never as a pass.
  - *Error path:* the skill states the fallback heuristic still applies when a project declares nothing, so this is additive rather than a breaking change for existing repos.
  - *Integration:* the resolution order is asserted structurally, so a later edit cannot silently promote the heuristic above the declared map.
- **Verification:** `bash tests/lint/en-ship-preflight.test.sh` green with negative controls.

## Decisions, assumptions & risks

- **Decision:** The receipt lives in `.git/ensemble/`, not the worktree. It is per-clone, already
  ignored, and cannot be committed or copied to a machine it does not describe.
- **Decision:** Validity is a conjunction with no partial credit. Every "smart" invalidation rule is a
  path to shipping untested code, and the cost of being wrong is asymmetric.
- **Decision:** Ensemble publishes a hook contract and never installs a hook. Hooks encode project
  policy; editing one silently is help nobody asked for.
- **Alternative:** Codex proposed en-build → en-ship reuse as the headline win. Rejected as the primary
  framing: the post-mortem's own branch was rebased before ship, which changes the tree and invalidates
  any receipt. The reliable win is **en-ship → pre-push hook**, seconds apart on an identical tree.
- **Alternative:** Codex proposed four JSON helpers. Two are built. Under self-containment every helper
  is carried by each naming skill, so the surface multiplies.
- **Assumption:** Hashing untracked non-ignored files is cheap on a normal working tree. Falsified by a
  repo with large untracked artifacts outside `.gitignore`; U1's tests should include a timing sanity
  check, and the fallback is to record the untracked *set* rather than its contents.
- **Risk:** A receipt makes `/en-ship` skip checks, so a fingerprint bug ships untested code —
  **Mitigation:** U3 is `risk: high`; U1 is test-first with an explicit fixture per refusal reason; the
  default on any doubt is to run the checks; and CI remains the independent authority that never reads
  a receipt.
- **Risk:** Environment drift — the tree is identical but the toolchain changed, so a stale receipt
  vouches for a run that would now fail — **Mitigation:** the TTL, defaulting conservatively and
  project-tunable. This is the one invalidation input not derivable from the tree.
- **Risk:** U3 and U8 both restructure en-ship's step 5 and will conflict textually — **Mitigation:**
  they carry no dependency edge because they are logically independent; the builder sequences them and
  the second rebases on the first.

## Tracked debt

None resolved. If the untracked-file hashing assumption is falsified, file the fallback as a TD entry
with a back-reference to U1.

## Iteration log

> - 2026-09-01 (initial): plan v0 from D57's deferred tier and the PR post-mortem.
> - 2026-09-02: flipped to `open` on the user's review. No cross-agent peer pass ran — the peer CLI
>   is not available in this session, so the plan is user-approved rather than peer-approved.
> - 2026-09-02: all eight units built on `en15-build`, stacked on PR #63 because U3/U5/U6/U8 edit
>   en-ship's SKILL.md on top of D57's changes. Two assumptions the plan flagged were checked and
>   one was falsified: fingerprinting spawned a process per untracked file (7s for 200), now batched
>   to 0s. The dependency-comparison path was also found untested — both fixtures passed via
>   fingerprint-mismatch — and is now isolated with an ignored lockfile.
