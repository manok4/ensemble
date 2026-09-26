---
type: plan
plan_type: feature
plan_id: EN21
title: /en-test-audit, audit and prune an existing test suite with evidence before every deletion
status: in_progress
location: active
created: 2026-09-26
shipped:
deepened:
covers_requirements: []
requirements_pending: true
related_design:
peer_review_verdict: revise
peer_review_iterations: 3
peer_review_last_run: 2026-09-26
peer_review_plan_hash: b11c7bde09148dd8fcd3040349ed99a2da8be2fbfe45a8aaa98a278a08077905
peer_review_resolutions:
  - finding_id: "1-1"
    iteration: 1
    severity: P1
    title: U1 exposes deletion before its safety gates exist
    status: disagreed
    rationale: The units are commits on one branch shipped as one PR, and the installed skill runs from a separate checkout tracking main, so no one runs U1's intermediate state. Recorded as a decision.
    location: Decisions, assumptions & risks
  - finding_id: "1-2"
    iteration: 1
    severity: P1
    title: Ledger scope is undefined for batch mode
    status: applied
    location: Technical design (ledger contract), U1, U2
  - finding_id: "1-3"
    iteration: 1
    severity: P1
    title: Batch flow lacks behavior scenarios
    status: applied
    rationale: Refusals and baseline moved into ensemble-test-audit-preflight with fixture scenarios; candidate judgment stays prose and is checked by the verifier, mutations and peer rather than a scenario.
    location: U1
  - finding_id: "1-4"
    iteration: 1
    severity: P1
    title: Name search cannot verify declaration removal
    status: applied
    location: Technical design (ledger contract), U2
  - finding_id: "1-5"
    iteration: 1
    severity: P1
    title: Timeout is treated as proof of a caught mutation
    status: applied
    location: Technical design, U3, Decisions
  - finding_id: "1-6"
    iteration: 1
    severity: P1
    title: Peer outage bypasses the preservation review
    status: applied
    location: U4, Decisions
  - finding_id: "1-7"
    iteration: 1
    severity: P1
    title: Peer artifact and staging steps are unspecified
    status: applied
    location: Technical design, U4
  - finding_id: "1-8"
    iteration: 1
    severity: P1
    title: Campaign tests cover loading, not campaign behavior
    status: applied
    rationale: Lane coverage, one-lane-per-file and product-defect fields are now verifier rules with U2 scenarios, and U5 asserts the reference and verifier agree. Shared-harness ownership stays a prose rule with no script test.
    location: U2, U5
  - finding_id: "1-9"
    iteration: 1
    severity: P1
    title: Campaign reconciliation discards changed tests
    status: applied
    location: U5
  - finding_id: "2-0"
    iteration: 2
    severity: P0
    title: Reconciled declarations cannot pass baseline verification
    status: applied
    rationale: Peer re-raised under id 1-9; recorded as 2-0 to keep ids unique. reconciled_sha added; superseded in iteration 3 by a single moving baseline_sha plus rebaselined_from.
    location: Technical design (ledger contract), U2
  - finding_id: "2-4"
    iteration: 2
    severity: P1
    title: Campaign coverage does not require ledger rows
    status: applied
    rationale: Peer re-raised under id 1-8; recorded as 2-4.
    location: Technical design (ledger contract), U2
  - finding_id: "2-1"
    iteration: 2
    severity: P1
    title: Whole-file deletions have no defined tree check
    status: applied
    location: Technical design (ledger contract), U2
  - finding_id: "2-2"
    iteration: 2
    severity: P1
    title: Mutation proof can accept an unrelated failure
    status: applied
    location: Technical design, U3
  - finding_id: "2-3"
    iteration: 2
    severity: P1
    title: Peer failure recovery is blocked by preflight
    status: applied
    location: Technical design, U1, U4
  - finding_id: "3-1"
    iteration: 3
    severity: P1
    title: Mutation flow still passes a declaration name as the expected failure
    status: applied
    rationale: Peer re-raised under id 2-2; recorded as 3-1.
    location: U3
  - finding_id: "3-2"
    iteration: 3
    severity: P1
    title: Resume rejects staged production seams the batch is allowed to remove
    status: applied
    rationale: Peer re-raised under id 2-3; recorded as 3-2.
    location: Technical design, U1
  - finding_id: "3-3"
    iteration: 3
    severity: P1
    title: Reconciliation verifier cannot detect unlisted changed declarations
    status: applied
    rationale: Peer re-raised under id 1-9. Fixed by simplifying rather than adding a check - one moving baseline_sha with rebaselined_from, full per-declaration coverage in campaign mode, and a reconciled row for each file main changed. Replaces reconciled_sha.
    location: Technical design (ledger contract), U2, U5
depth: standard
data_scale: small
---

# EN21 — /en-test-audit, audit and prune an existing test suite with evidence before every deletion

## Context

Test suites in the repos Ensemble runs on keep growing, and nothing in Ensemble removes a test. `/en-simplify` preserves behaviour over the branch diff only, and `/en-sweep` is doc-only. D121 (commit 982a700 on this branch) gave `good-tests.md` four anti-patterns that describe suite weight: tests the mock, cannot fail, duplicated contract, test-only seam. That gates new tests. This plan adds the other half, a user-invoked skill that finds existing tests matching those patterns and removes them one owner-boundary batch at a time, with written evidence for every deletion and a proof that consolidated assertions can still fail.

The design is adapted from OpenClaw's `test-audit` skill (MIT; `.agents/skills/test-audit/SKILL.md` and `CAMPAIGN.md` at github.com/openclaw/openclaw). Its prose gates become two fail-closed scripts here, its preservation review goes to Ensemble's cross-agent peer, and its Vitest and openclaw-specific tooling is replaced by the project's AGENTS.md test commands.

## Requirements covered

None: `docs/foundation.md` states goals, use cases and decisions but no R-IDs, so `requirements_pending: true`, as on EN20. The plan serves G10 (lean skills; the campaign workflow loads only when asked) and G12 (debt paid down continuously). It records D122.

## Out of scope for this plan

- **Running a campaign on Ensemble's own 170-file suite.** A follow-up run after this ships, so a defect in the skill cannot also delete real tests in the same PR.
- **Any caller.** `/en-sweep`, `/en-review` and `/en-build` do not invoke `/en-test-audit`. It is `disable-model-invocation: true`, so `tests/lint/contract-shape.test.sh` requires that nothing does, and it carries no `CONTRACT.md`.
- **Run metrics.** No `ensemble-run-metrics` copy or outcome event. The vocabulary work that needs is its own change once there is a run to measure.
- **An `/en-ship` check of the ledger trailer.** Filed as tracked debt in U5.
- **Auto-merge, push or PR.** `/en-ship` owns those, as for every code-changing skill.

## Approach (high-level)

`/en-test-audit [<path>]` runs in **batch mode** by default: read-only discovery over the scope (the whole repo when no path is given), candidates judged against `references/good-tests.md` and a retention bar, then one owner-boundary batch edited and committed on the current feature branch. `--campaign <path>` covers one subsystem's whole test surface in one PR. It loads `references/campaign.md`, and only then (D75).

Both modes write one committed **ledger**, `docs/test-audits/<YYYY-MM-DD>-<slug>.md` in the target repo: a markdown table with one row per test declaration, marked R (retain), F (fix the assertion), C (consolidate into a keeper) or D (delete), with the keeper or contract and the evidence. The ledger is the PR's evidence of why each test went. Two scripts make its promises checkable rather than prose. `ensemble-test-ledger-verify` fails closed on any row missing what its mark requires. `ensemble-mutation-check` proves a keeper goes red under a deliberate mutation and that the source is restored exactly. The skill commits only on the verifier's exit 0, and the commit carries a `Test-Audit-Ledger:` trailer naming the ledger.

Before committing, the **preservation review** sends the ledger and the staged diff to the cross-agent peer, which has read-tree access and its own brief. It asks one question: did a deleted or consolidated test take the only proof of some contract with it? Each gap the peer finds is restored as an F or C row with its own mutation. The retention bar is written for repos like this one, where tests grep SKILL.md prose because the prose is the product. Source inspection is retained when it is the cheapest independent guard of a user-facing contract, and the carve-outs in `good-tests.md` apply.

## Test seams

- **The two scripts' command lines, run against a throwaway git repo** (new seam, `tests/en-test-audit/`). Each test builds a repo under a temp dir with a tiny source file, a test script and a ledger. It then asserts exit codes and output lines, and afterwards the repo state. This is the highest seam that observes the behaviour, since the skill only ever calls the scripts this way.
- **The existing repo lints** (existing seam) for the skill's shape: `skill-payload`, `skill-size`, `skill-description-budget`, `reference-parity`, `script-parity`, `foundation-catalog-drift`, `contract-shape`, `skill-self-path`, `skill-helper-anchor`. Nothing new is written for what they already check.
- **`ensemble-build-peer-prompt` with the new brief** (existing seam, as `tests/lint/peer-prompt-contract.test.sh` uses it) for the preservation review's prompt.

One skill-specific lint, `tests/lint/en-test-audit-contract.test.sh`, guards the flow's ordering invariants: the verifier runs before the commit, and `campaign.md` is named only under `--campaign`. Everything else is covered by the three seams above.

## Technical design

Four components (the skill flow, the ledger verifier, the mutation check, the peer preservation review), and a five-stage flow per batch:

```
preflight ─▶ discover (read-only) ─▶ ledger rows ─▶ edit batch ─▶ mutation-check each C/F row
                                                                           │
                                            stage batch + ledger ◀─────────┘
                                                     │
                                     review artifact ─▶ peer preservation review
                                                                  │
          commit with Test-Audit-Ledger: trailer ◀── ledger-verify --tree exit 0 ◀┘
```

**Ledger contract** (`references/ledger-format.md`, U1; enforced by U2):

- Frontmatter: `type: test-audit`, `mode: batch | campaign`, `scope: <path>`, `test_glob: <glob>`, `baseline_sha: <sha>`, `created: <YYYY-MM-DD>`, `preservation_review: cross-agent | single-agent-fallback | skipped-by-flag`. A campaign that merged main moves `baseline_sha` to main's merged SHA and records the previous one as `rebaselined_from: <sha>`.
- **Where a declaration must have existed.** At `baseline_sha`. After a rebaseline this still covers every deletion, because main's side still has the tests the campaign removed, and it covers what main added. A row for a test that main itself deleted fails, and is correctly dropped.
- **Rebaseline coverage.** When `rebaselined_from` is set, every file under `scope` matching `test_glob` that `git diff --name-only <rebaselined_from> <baseline_sha>` lists needs at least one row whose Evidence starts `reconciled:`, so a changed assertion is re-judged and not silently deleted.
- **What needs a row.** Batch mode: every test declaration in every file the batch judged, including the ones retained, so each retained false positive is on record. A file the batch never opened needs no row. Campaign mode: every test file under `scope` that matches `test_glob` is in exactly one lane of a `## Lanes` table (`| Lane | Files |`), and every declaration in it at `baseline_sha`, in a supported form, has its own `## Ledger` row unless the file has a whole-file row. A file in an unsupported format therefore needs a whole-file row.
- **Whole-file rows.** A `Test` cell with no `::name` is a whole file. The file must have existed at the relevant SHA (`git cat-file -e`). A D or C whole-file row requires the file to be gone from the working tree. A C row's keeper is always `<path>::<name>`, never a bare path.
- One `## Ledger` table with exactly these columns: `| Test | Mark | Keeper or contract | Evidence | Mutation |`.
- `Test` is `<repo-path>` for a whole file or `<repo-path>::<declaration name>`. A declaration name is only resolvable in a supported form: a quoted string passed to `it`, `test`, `describe`, `context`, `specify`, `t.Run`, `pass` or `fail`; or a `def`/`func`/`function` name. A name not found in one of these forms at `baseline_sha` is a violation, so an unsupported format fails closed and the row has to be written at file level.
- Campaign mode adds `## Product defects` (`| Defect | Fix commit | Control evidence |`), where every column is required.
- Rules by mark:
  - **R:** names the contract.
  - **F:** names the contract, and a mutation is required.
  - **C:** names the keeper as `<path>::<name>`, evidence is non-empty, and a mutation is required.
  - **D:** keeper as `<path>::<name>` or `none: <reason>`, and evidence is non-empty.
- `Mutation` is `-` or a path relative to the ledger to a `.diff` file that exists.
- An optional `## Seams removed` table (`| Path | Reason |`) lists deleted test-only production seams. Those paths may be staged with the batch.

**Script interfaces** (the flow calls these; U2 and U3 produce them):

- `ensemble-test-audit-preflight [--scope <path>] [--resume <ledger.md>]` (U1). Prints `branch=`, `baseline_sha=`, `test_command=` and `scope=` lines. Exit 0 ready; exit 2 on the default branch, a dirty tree, a missing scope path, or no test command declared in AGENTS.md. `--resume` is the path back into a batch that stopped staged. It accepts a tree whose changes are all staged, and whose staged paths are exactly the ledger, its mutation diffs, the files its rows name, and the paths in its `## Seams removed` table. Anything unstaged, or any other staged path, is exit 2 and named. A resumed run starts at the preservation review.
- `ensemble-test-ledger-verify <ledger.md> [--tree]`. Exit 0 valid, 1 violations (one `ledger: <row>: <rule>` line each), 2 unreadable or malformed file. With `--tree`, it also checks, against `baseline_sha` and the working tree:
  - every declaration existed at baseline in a supported form;
  - a D or C row's declaration is gone now, and its keeper is present;
  - in campaign mode, the lane coverage rule holds.
- `ensemble-test-audit-review-artifact <ledger.md>` (U4). Writes one file holding the ledger and `git diff --cached`, under a heading each, and prints its path. Exit 2 if nothing is staged.
- `ensemble-mutation-check --patch <file.diff> --test '<command>' --expect '<text>' [--timeout <seconds>]`. It runs the command on the unmutated tree first, applies the patch with `git apply`, and runs the command again. It then reverses the patch and confirms the touched files' hashes match the originals. `--test` should run the keeper alone, focused by the project's runner. `--expect` is required and must be the keeper's failure message, not just its name. The unmutated baseline output must not contain it: if it does, the text is not failure-specific and the script exits 2. A red run with the text is therefore the keeper failing, not a sibling failing beside a keeper that printed its name on a pass. Exit codes:
  - 0: caught (non-zero exit, and the output contains the `--expect` text).
  - 1: survived (zero exit).
  - 2: bad input, the patch does not apply, a target file has uncommitted changes, or the `--expect` text appears in the passing baseline output.
  - 3: the baseline run is already red.
  - 4: the restore failed. Stop, and name the files.
  - 5: inconclusive (timed out, or red without the `--expect` text). Blocks the row like a survival.

## Implementation units

### U1. The skill, batch mode, and its registration

- **Goal:** `/en-test-audit [<path>]` exists as a user-invoked skill that discovers candidates, records them in a ledger, and edits one batch, and the repo's catalog knows it.
- **Requirements covered:** none (see Requirements covered)
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `skills/en-test-audit/references/ledger-format.md`, the ledger contract in the Technical design section, which U2's verifier enforces word for word.
  - *Produces:* `skills/en-test-audit/scripts/ensemble-test-audit-preflight [--scope <path>]`, as in Technical design.
- **Files:**
  - `skills/en-test-audit/SKILL.md` (new)
  - `skills/en-test-audit/references/ledger-format.md` (new)
  - `skills/en-test-audit/scripts/ensemble-test-audit-preflight` (new, executable)
  - `tests/en-test-audit/preflight.test.sh` (new)
  - `skills/en-test-audit/references/good-tests.md` (new, byte-identical copy of `skills/en-build/references/good-tests.md` at this branch's HEAD)
  - `skills/en-test-audit/references/script-invocation.md` (new, byte-identical copy)
  - `tests/lint/en-test-audit-contract.test.sh` (new)
  - `docs/foundation.md` (§5 count sentence, §5.1 row 17, new §5.2.17, D122 in §4.1)
  - `README.md` (skill table row and the diagram)
  - `AGENTS.md` ("Working with this project" line)
  - `.claude-plugin/marketplace.json`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` (the stale "11 skills + 11 agents" count reworded so it cannot go stale again)
- **Approach:** Frontmatter: `name`, a description under the 300-character cap with trigger phrases ("audit tests", "prune tests", "test bloat", "test audit"), and `disable-model-invocation: true`. The flow in SKILL.md:
  1. Run `ensemble-test-audit-preflight`, and stop on a non-zero exit. The script, not prose, refuses the default branch, a dirty tree, a missing scope and an undeclared test command. It reads `Test:` and the Test impact block from AGENTS.md the same way `ensemble-test-select` does, and it runs the test command once to record the baseline.
  2. Read root and scoped AGENTS.md files.
  3. Discover read-only and pick the files to judge, preferring a few high-confidence files over a long speculative list.
  4. Judge every declaration in those files against `good-tests.md` and the retention bar, which lives in SKILL.md, adapted from OpenClaw, with the prose-is-the-product case stated.
  5. Fill the ledger per `references/ledger-format.md` before any edit: a row for every declaration judged, retained ones included, with every candidate-evidence field.
  6. Edit one owner-boundary batch, deleting the test-only seams it unlocks and preferring net-negative production lines.
  7. Run the owner and sibling tests.
  8. Commit tests and ledger together.
  9. Hand off: removed categories, retained false positives, proof run, production versus test lines, follow-ups.

  Rules that hold throughout: a baseline failure is a product bug, reproduced and reported, never deleted; slowness is not a deletion reason; never edit while the project's test runner is running. The OpenClaw credit goes in SKILL.md's closing lines. Registration: the §5 sentence says seventeen, the §5.1 row, a §5.2.17 block in the shape of 5.2.9, and D122 recording why this is a separate skill from D121's authoring gate and why it never auto-merges.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** `skills/en-sweep/SKILL.md` frontmatter and boilerplate; D75 (byte budget).
- **Test scenarios:**
  - *Happy path (preflight):* a temp repo on branch `audit` with a clean tree, an AGENTS.md declaring `Test: sh test.sh`, and a passing `test.sh` → exit 0. The output has `branch=audit`, the HEAD SHA as `baseline_sha=` and `test_command=sh test.sh`, and the tree is unchanged.
  - *Error path (preflight):* the same repo on `main` → exit 2, `refusing: default branch`. An untracked file present → exit 2, `refusing: dirty tree`. AGENTS.md without a Test command → exit 2. `--scope missing/` → exit 2. In every case the tree is unchanged.
  - *Happy path (resume):* the repo with a ledger, its one mutation diff and the test file it names all staged, nothing unstaged → `--resume <ledger>` exits 0. The same, plus an unstaged edit to `src.sh` → exit 2 naming `src.sh`. Plus a staged file the ledger does not name → exit 2 naming it. A staged deletion of `lib/reset-for-tests.sh` listed under `## Seams removed` → exit 0, and the same deletion without that listing → exit 2.
  - *Edge case (preflight):* a red `test.sh` → exit 0 with `baseline=red` printed. The skill then reports the failure as a product bug before judging anything, and never deletes the failing test.
  - *Happy path:* `./tests/run.sh -k en-test-audit-contract` passes. SKILL.md carries `disable-model-invocation: true`, calls the preflight first, names `references/ledger-format.md` and `references/good-tests.md`, and says the ledger is committed with the batch.
  - *Happy path:* `skill-payload`, `skill-size` (SKILL.md at or under 24,576 bytes), `skill-description-budget`, `reference-parity` (the third `good-tests.md` copy is byte-identical) and `foundation-catalog-drift` all pass with the new directory present.
  - *Error path:* deleting the §5.1 row turns `foundation-catalog-drift` red. Deleting `disable-model-invocation` turns the contract lint red.
  - *Edge case:* changing one byte of the new `good-tests.md` copy turns `reference-parity` red.
- **Verification:** `./tests/select-for.sh <changed paths>` green; `bin/ensemble-lint --scope docs/foundation.md` clean; negative controls above observed red.

### U2. Ledger verifier

- **Goal:** a ledger that is missing what a mark requires cannot be committed.
- **Requirements covered:** none
- **Dependencies:** U1
- **Interfaces:**
  - *Produces:* `skills/en-test-audit/scripts/ensemble-test-ledger-verify <ledger.md> [--tree]` with exit codes 0 / 1 / 2 as in Technical design.
  - *Consumes:* the ledger contract in `references/ledger-format.md` (U1).
- **Files:**
  - `skills/en-test-audit/scripts/ensemble-test-ledger-verify` (new, executable)
  - `skills/en-test-audit/SKILL.md` (the step before the commit: run the verifier with `--tree`, commit only on exit 0, add the `Test-Audit-Ledger: <path>` trailer)
  - `tests/en-test-audit/ledger-verify.test.sh` (new)
  - `tests/en-test-audit/fixtures/` (new ledgers)
  - `tests/lint/en-test-audit-contract.test.sh` (ordering assertion: the verify step precedes the commit step)
- **Approach:** Bash with awk, in the style of `skills/en-build/scripts/ensemble-verify-peer-evidence`. Parse the frontmatter, the first table under `## Ledger`, and in campaign mode the `## Lanes` and `## Product defects` tables. Trim cells, and apply every rule in the ledger contract. A row with the wrong cell count is malformed, and a missing or unknown `preservation_review` value is a violation. Each violation is one line naming the row's `Test` cell and the rule, and every violation is reported, not just the first. Relative `Mutation` paths resolve against the ledger's directory.

  `--tree` resolves paths against the git top level. A `path::name` resolves only in the supported declaration forms, matched with an extended regex over each line after leading comment markers (`#`, `//`, `*`) are rejected. The check runs twice: against `git show <sha>:<path>`, where the declaration must exist (at `baseline_sha`; a whole-file row checks the file with `git cat-file -e`), and against the working tree, where a D or C declaration must be gone and a keeper must be present. Campaign lane coverage lists `git ls-files <scope>`, filters by `test_glob`, and requires each file in exactly one lane.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a ledger with one row of each mark, all fields filled, and the C and F mutation diffs present → exit 0, no output.
  - *Error path:* a D row with empty Evidence → exit 1, one line naming that row and the evidence rule. A C row with keeper `none: duplicate` → exit 1 (C needs a real keeper). An F row with Mutation `-` → exit 1. A Mutation path to a missing file → exit 1. Mark `X` → exit 1.
  - *Error path:* two broken rows → exit 1 with two lines.
  - *Error path:* frontmatter without `preservation_review` → exit 1.
  - *Edge case:* no `## Ledger` heading, or a table with a wrong column header → exit 2. A missing file → exit 2. A row with a pipe inside a cell (six cells) → exit 2 naming the row.
  - *Integration (`--tree`):* in a temp repo whose baseline commit has `test.sh` with `pass "adds two numbers"` and `pass "rejects letters"`:
    - A D row `test.sh::adds two numbers` while the declaration is still in the tree → exit 1. After it is removed → exit 0.
    - The name left behind only in a comment (`# pass "adds two numbers"`) still passes, since a comment is not a declaration.
    - A D row naming `test.sh::no such test` → exit 1 (not found at baseline), so a typo or an unsupported format fails closed.
    - A C row whose keeper `keeper.sh::covers addition` is absent → exit 1.
    - A whole-file D row `old.test.sh`, with the file present at baseline and removed from the tree → exit 0. The file still present → exit 1. A whole-file row naming a file absent at baseline → exit 1.
  - *Integration (campaign):* scope `tests/` holding `a.test.sh` and `b.test.sh`:
    - A `## Lanes` table that lists only `a.test.sh` → exit 1 naming `b.test.sh`.
    - Both files listed, but `a.test.sh` in two lanes → exit 1.
    - Both in one lane each, but no ledger row for `b.test.sh` → exit 1 naming it.
    - A `## Product defects` row with an empty Control evidence cell → exit 1.
    - Full declaration coverage: `a.test.sh` has `pass "one"` and `pass "two"` at baseline, and the ledger has a row for `a.test.sh::one` only → exit 1 naming `a.test.sh::two`. A whole-file row for `a.test.sh` instead → exit 0.
    - Rebaseline: `rebaselined_from` is set, and main changed an assertion inside `b.test.sh::keeps order` between the two SHAs. With no `reconciled:` row for `b.test.sh` → exit 1 naming the file. With one → exit 0. A new declaration main added to `a.test.sh` with no row → exit 1, by the full-coverage rule.
- **Verification:** `./tests/run.sh -k ledger-verify` green; a negative control that disables the evidence rule in the script turns the test red.

### U3. Mutation check

- **Goal:** "the keeper still catches it" is a measured result, and the source is provably restored afterwards.
- **Requirements covered:** none
- **Dependencies:** U1
- **Interfaces:**
  - *Produces:* `skills/en-test-audit/scripts/ensemble-mutation-check --patch <file.diff> --test '<command>' --expect '<text>' [--timeout <seconds>]` with exit codes 0 to 5 as in Technical design.
- **Files:**
  - `skills/en-test-audit/scripts/ensemble-mutation-check` (new, executable)
  - `skills/en-test-audit/SKILL.md` (a step after the edit: write one `.diff` per C and F row under `docs/test-audits/<slug>/mutations/` and run the check on each, with `--test` focused on the keeper and `--expect` set to the keeper's failure-specific output (its assertion message, or the runner's failure line for it), never the bare declaration name. Exit 1 or 5 means the keeper has not been shown to catch it, so the row goes back to R or the keeper is repaired. Exit 4 stops the run)
  - `tests/en-test-audit/mutation-check.test.sh` (new)
- **Approach:** Resolve the patch's target files with `git apply --numstat`, and refuse with exit 2 if any of them has uncommitted changes. Hash them, then run the test command once unmutated (exit 3 if it is red: a mutation "caught" on a red baseline proves nothing). Apply the patch, run the command under the timeout (default 300 seconds), and capture its exit status and combined output. Classify the run: a zero exit is survived; a timeout is inconclusive; a non-zero exit is caught only when the output contains the `--expect` text, and inconclusive otherwise. Reverse with `git apply -R`, then re-hash. A `trap` on EXIT, INT and TERM reverses the patch if the script dies between apply and reverse. A hash mismatch, or a reverse that fails, exits 4 and names the files. The `.diff` stays on disk as evidence.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible (the script writes to the working tree and must restore it)
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* temp repo with `src.sh` (`add() { echo $(( $1 + $2 )); }`) and `test.sh`, which prints `FAIL adds two numbers` and exits 1 unless `add 2 3` prints 5. A patch changing `+` to `-`, with `--expect 'FAIL adds two numbers'` → exit 0, and `git status --porcelain` is empty afterwards.
  - *Error path:* a patch that changes a comment only → exit 1 (survived), and the tree is clean afterwards.
  - *Error path:* a patch that makes `src.sh` a syntax error, so `test.sh` dies with a shell error that lacks the expected text → exit 5 (red for an unrelated reason), tree restored.
  - *Error path:* `test.sh` holds two checks and prints `ok adds two numbers` when the keeper passes. A patch that breaks only the sibling, run with `--expect 'adds two numbers'` → exit 2, because the text appears in the passing baseline. Run with `--expect 'FAIL adds two numbers'` instead → exit 5, because the keeper passed and only the sibling failed.
  - *Error path:* `test.sh` already failing → exit 3, patch never applied.
  - *Error path:* the target file has an uncommitted edit → exit 2, file untouched. A patch that does not apply → exit 2. `--expect` omitted → exit 2.
  - *Edge case:* a mutation that makes `add` loop forever, run with `--timeout 1` → exit 5 (inconclusive, not caught), and the tree is restored.
  - *Integration:* the script killed with TERM while the mutated test runs → the tree is restored by the trap.
- **Verification:** `./tests/run.sh -k mutation-check` green; negative control: removing the baseline run from the script turns the red-baseline scenario red.

### U4. Preservation review by the cross-agent peer

- **Goal:** before the batch is committed, an independent agent looks for contracts that lost their only proof and for assertions that cannot fail.
- **Requirements covered:** none
- **Dependencies:** U2, U3
- **Interfaces:**
  - *Produces:* `skills/en-test-audit/scripts/ensemble-test-audit-review-artifact <ledger.md>`, as in Technical design.
- **Files:**
  - `skills/en-test-audit/scripts/ensemble-test-audit-review-artifact` (new, executable)
  - `skills/en-test-audit/references/peer-brief.md` (new; this skill's question, listed exception in `reference-parity` already covers the basename)
  - `skills/en-test-audit/references/peer-contract.md`, `references/finding-schema.md` (byte-identical copies; no `host-detect.md`, since the skill runs `ensemble-detect-host` directly, per D91)
  - `skills/en-test-audit/scripts/ensemble-build-peer-prompt`, `ensemble-peer-invoke`, `ensemble-peer-flags`, `ensemble-config-get`, `ensemble-detect-host`, `ensemble-extract-json`, `ensemble-cli-smoke`, `peer-findings.schema.json` (byte-identical copies, as carried by `skills/en-review/scripts/`)
  - `skills/en-test-audit/SKILL.md` (the review step, between the mutation checks and the verifier)
  - `tests/en-test-audit/peer-brief.test.sh` (new)
- **Approach:** After the mutation checks pass, stage the batch's files and the ledger by path (never `git add -A`). Then `ensemble-test-audit-review-artifact <ledger>` writes the ledger and `git diff --cached` into one file. Detect the host with `ensemble-detect-host`. Build the prompt with `ensemble-build-peer-prompt --brief "$SKILL_DIR/references/peer-brief.md" --artifact-file <that file>`, and invoke it with `ensemble-peer-invoke --access read-tree` and `ENSEMBLE_PEER_REVIEW=true`, the same way `/en-review` does. The brief asks the peer three things:
  - For each D and C row, whether the named keeper or the stated reason covers the deleted assertion. It must answer with source evidence.
  - Whether any F or C assertion can pass for an unrelated reason.
  - Whether any retained R row is actually junk the retention bar should not have kept. This is advisory only.

  Findings use the shared contract. The host decides on each: a gap is restored as an F or C row with its own mutation, and a rejected finding gets a line of source evidence in the ledger. Two cases leave nothing committed. The first is a finding that restores a row: that row's mutation check reruns, the file is re-staged, and the artifact is rebuilt before the verifier runs. The second is a peer decision of `off` or `peer-failed:*`. That run **stops before the commit**, with the batch staged and the reason reported. The way back is `/en-test-audit --resume <ledger>`, which runs the preflight's resume check and restarts at the review. It is committed without a review only when the user adds `--no-peer` to that resume, which writes `preservation_review: skipped-by-flag` into the ledger and says so in the hand-off. `single-agent-fallback` still counts as a review: it is a fresh process with the same brief, and the ledger records it as such. The recursion guard skips the review under `ENSEMBLE_PEER_REVIEW=true`. Before building, the builder confirms the carried file list against what `/en-review`'s peer step actually calls, and copies only those.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path (artifact):* a temp repo with a ledger and one staged deletion → the script prints a path. The file holds the ledger under `## Ledger file` and the deletion's hunk under `## Staged diff`, and the index is unchanged.
  - *Error path (artifact):* nothing staged → exit 2, and no file is written.
  - *Integration:* the artifact passed to `ensemble-build-peer-prompt` with the new brief → a prompt containing the brief's three questions, the ledger rows and the staged hunk, exit 0. Then `ensemble-peer-invoke` with the PATH-shadowed mock CLI from `tests/lib/mock-peer.sh` returning a failure → a decision whose `reason` starts `peer-failed`, which the flow treats as a stop.
  - *Happy path:* the contract lint finds `--no-peer` documented as the only route to `skipped-by-flag`, and the review step placed before the verifier step.
  - *Happy path:* `script-parity` and `reference-parity` pass with the copies in place.
  - *Error path:* a brief missing its dimensions block → the builder's existing refusal fires. The test asserts the non-zero exit.
  - *Edge case:* `skill-payload` fails if a carried script is not named in SKILL.md's flow; the unit keeps it green.
- **Verification:** `./tests/select-for.sh <changed paths>` green, including both parity tests.

### U5. Campaign mode

- **Goal:** `--campaign <path>` prunes one subsystem's whole test surface with lanes, a layer pass, and product-defect control runs, loaded only when asked.
- **Requirements covered:** none
- **Dependencies:** U4
- **Files:**
  - `skills/en-test-audit/references/campaign.md` (new)
  - `skills/en-test-audit/SKILL.md` (the `--campaign` flag row, and one line that loads `references/campaign.md` under it)
  - `tests/lint/en-test-audit-contract.test.sh` (`campaign.md` is named only in the `--campaign` branch)
  - `docs/plans/tech-debt-tracker.md` (TD entry: `/en-ship` should verify the `Test-Audit-Ledger:` trailer's ledger)
- **Approach:** Adapt OpenClaw's eight steps, each ending on a done criterion:
  1. Baseline at a pinned SHA, with failures kept in their own list.
  2. Lanes along production owner boundaries, so every test file belongs to exactly one lane.
  3. A read-only ledger per lane, each lane dispatched to its own read-only agent that reads every declaration in full.
  4. A layer pass that names the keeper per contract and prefers the real transport boundary with a fake network.
  5. Cutover lane by lane. Shared harnesses are serialized through one owner, and each lane removes the seams it unlocks.
  6. Preservation review: U4's step, run per boundary group.
  7. Product defects: a baseline failure that survives into a keeper is fixed in its own commit, with a control run that reverts the fix.
  8. Reconcile: merge main rather than rebase, then move `baseline_sha` to main's merged SHA and record the old one as `rebaselined_from`. Reread every in-scope test file main changed between the two, and give each new or changed declaration its own `reconciled:` row, judged fresh. Carry each assertion that is kept into its keeper with a new mutation, and rerun the preservation review over the affected rows. Only then resolve a conflict on a deleted file as a deletion. `ledger-verify --tree` enforces this on the merged head: full declaration coverage catches a new declaration with no row, and the rebaseline rule catches a changed file with no `reconciled:` row.

  All lanes write into the one ledger, so U2's verifier checks the campaign, including its lanes and product-defects tables. The per-lane agent dispatch uses the read-only `Explore` pattern, not a new agent file (D122 records the choice).
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* the contract lint finds `references/campaign.md` named in SKILL.md only on the `--campaign` line, and `skill-payload` passes.
  - *Happy path:* the contract lint finds the reconcile step in `campaign.md` requiring the rebaseline, a fresh `reconciled:` row, a new mutation and a preservation rerun before a deleted-file conflict resolves. Deleting that clause turns the lint red.
  - *Integration:* the campaign rules the skill relies on (lane coverage, exactly one lane, product-defect fields) are U2's campaign scenarios. This unit adds a fixture campaign ledger in the shape `campaign.md` documents, and asserts that U2's verifier accepts it. That keeps the reference and the verifier in step.
  - *Error path:* moving the `campaign.md` pointer into the always-run flow turns the contract lint red.
  - *Edge case:* SKILL.md stays under 24,576 bytes with the flag added, while the campaign steps live in the reference.
- **Verification:** full `./tests/run.sh` green before the branch is reviewed; `bin/ensemble-lint --scope docs/` clean.

## Decisions, assumptions & risks

- **Decision:** the ledger is committed in the target repo's `docs/test-audits/` rather than kept under `/tmp/ensemble/` like the D98 run ledgers. A deletion's evidence has to outlive the session and be readable in the PR. `bin/ensemble-lint` only checks the doc paths it names, so the new directory needs no lint rule.
- **Decision:** every C and F row needs a caught mutation, in both modes. Those are the rows where the audit moved or rewrote an assertion, and so where coverage silently drops. D rows with an existing keeper do not need one, because the keeper predates the audit.
- **Decision:** a mutated run counts as caught only when it exits non-zero with the keeper's `--expect` text in its output. A timeout, or a red run from some other failure, is inconclusive and blocks the row, because otherwise it is exactly the "cannot fail" negative control `good-tests.md` names.
- **Decision:** a peer that is off or failed stops the batch before the commit. Only an explicit `--no-peer` rerun commits without the review, and the ledger records that it did.
- **Decision:** the preflight, the review artifact and the verifier are scripts, because each is a promise the flow makes and a model can skip. Candidate judgment stays prose, because it is judgment. The verifier, the mutation evidence and the peer check its output instead.
- **Decision:** the units are separate commits on one branch that ships as one PR, and the installed skill runs from a separate checkout that tracks `main`. U1's flow therefore exists without its gates only in intermediate commits nobody runs, so the units are ordered for reviewability, not for runtime safety.
- **Alternative:** one skill with an authoring mode, as OpenClaw has. Rejected: D109 keeps one rubric shared by `/en-build` and `/en-review`, and a third place stating it would fork it (D121).
- **Alternative:** host-side dimension reviewers per boundary group for the preservation review. Rejected in favour of the peer, which gives the independent view this step needs.
- **Assumption:** the peer stack copies listed in U4 are exactly what `ensemble-peer-invoke --access read-tree` needs. The builder checks against `/en-review`'s actual calls before copying, and `skill-payload` fails on any extra file.
- **Assumption:** a markdown table is parseable reliably enough with awk. Pipes inside a cell are the known hazard. `ledger-format.md` forbids them, and the verifier reports a row with the wrong cell count as malformed rather than guessing.
- **Risk:** the retention bar misreads Ensemble's prose-grepping tests as junk on the first campaign. — **Mitigation:** the bar names the case explicitly, and the peer's third question asks about wrongly retained rows only. The first campaign is a separate, reviewed run.
- **Risk:** `ensemble-mutation-check` leaves a mutated file behind. — **Mitigation:** it refuses dirty targets, restores via a trap, re-hashes, and exits 4 loudly. U3 has a TERM scenario.

## Tracked debt

None resolved. U5 files one entry (the `/en-ship` trailer check).

## Iteration log

> - 2026-09-26 (initial): plan v0 from the conversation reviewing OpenClaw's `test-audit` skill; architecture confirmed in two question rounds (batch mode commits on a branch, committed markdown ledger, peer preservation review in both modes, patch-file mutations, stacked on `test-quality-patterns`, dogfood campaign deferred).
> - 2026-09-26 (peer 1, Codex, revise, 9 P1): applied 8 (1-3 and 1-8 partly: what a script can check moved into the preflight and the verifier, judgment stays prose), disagreed 1 (1-1, units ship as one PR). New: preflight and review-artifact scripts, `--expect` and exit 5 on the mutation check, `preservation_review` in the ledger, stop on peer failure, campaign rules in the verifier, a safe reconcile.
> - 2026-09-26 (peer 2, Codex, revise, 1 P0 + 4 P1): applied all 5. `reconciled_sha` for declarations main adds during a campaign, a ledger row required for every campaign file, whole-file row checks, `--expect` must be absent from the passing baseline, `--resume <ledger>` as the way back from a stopped peer review. Iteration cap reached.
> - 2026-09-26 (peer 3, Codex, revise, 3 P1; cap raised by one at the user's request): applied all 3. Two sat inside pass 2's fixes, which is the design signal the repo's learning names, so the reconcile design was simplified instead of patched: one moving `baseline_sha` with `rebaselined_from`, full declaration coverage in campaign mode, and a `reconciled:` row per file main changed. `reconciled_sha` is gone. `--expect` is the failure output, not the name. Seam paths are on the resume allowlist.
> - 2026-09-26 (finalize): cap reached on `revise` with every finding resolved; user chose accept as-is. Status open.
