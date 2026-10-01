---
name: en-test-audit
description: "Prune an existing test suite one owner-boundary batch at a time: evidence for every deletion in a committed ledger, proof that kept tests still fail, and a peer check for lost coverage. Trigger phrases: 'audit tests', 'prune tests', 'test bloat', 'test audit'."
disable-model-invocation: true
---


# `/en-test-audit`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.

Finds tests that cost more than they protect and removes them, one owner-boundary batch per run. **Optimize for confidence, not deletion count**: a run that deletes three tests with proof beats one that deletes thirty on a hunch.

> **What a test is worth** is defined once, in `references/good-tests.md`, shared byte-identical with `/en-build` (which writes tests against it) and `/en-review` (which judges them). This skill hunts existing tests for the same anti-patterns; it does not keep a second list.

> **Never pushes, never opens a PR, never merges.** It commits on the current feature branch; `/en-ship` owns the rest. A PR that deletes tests is read by a person.

## Invocation

`/en-test-audit [<path>]`. The scope defaults to the whole repo.

| Flag | Effect |
|---|---|
| `--campaign <path>` | Prune one subsystem's whole test surface in one PR: lanes, a layer pass, product-defect control runs and a reconcile with main. **Read `references/campaign.md` now**; it owns the order of work, and the steps below run inside it lane by lane. |
| `--resume <ledger>` | Return to a batch that stopped staged because the preservation review could not run. Step 1 runs the preflight with `--resume <ledger>`, which accepts only the ledger's own staged batch; the run then continues at **Stage, then the preservation review**. |
| `--no-peer` | Only with `--resume`. Commit the staged batch without a preservation review, writing `preservation_review: skipped-by-flag` into the ledger and saying so in the hand-off. The only route to an unreviewed commit. |

## Process

1. **Preflight.** If `ENSEMBLE_PEER_REVIEW=true`, stop: this skill never runs inside a peer subprocess. Then `bash "$SKILL_DIR/scripts/ensemble-test-audit-preflight" --scope <path>`. Exit 2 stops the run with the reason it printed: default branch, dirty tree, missing scope, or no Test command in AGENTS.md. Keep its `baseline_sha=` and `test_command=`. **`baseline=red` is a finding, not a licence:** report each failing test as a probable product bug, reproduce it, and leave it alone. A test that fails on the baseline is never deleted to make the suite pass.
2. **Read the maps.** Root and scoped `AGENTS.md` / `CLAUDE.md` files for the scope, and the project's test conventions.
3. **Discover, read-only.** Nothing is edited until step 6. Pick the files to judge, preferring a few high-confidence files over a long speculative inventory. For a broad scope, split discovery by owner boundary (core packages, plugins or services, UI and tooling, a cross-cutting pattern sweep) and run the lanes in parallel. Hunt for the anti-patterns in `references/good-tests.md`, and for:
   - duplicate invocations of the same contract, or a provider-local replay of a shared helper's tests;
   - copied fixtures, inventories or export lists asserted against themselves;
   - dead production code whose only callers are tests.
4. **Judge every declaration in those files** against the retention bar below. Before judging one, read the whole test and its production owner: entry point, callers, callees, sibling implementations, overlapping tests, CI routing, and the history of why it exists. When a test claims behaviour from a dependency, read the dependency's source or types. **Judge a test by its assertions, not its name**: a test named for retiring a window may assert the window was not cleared.
5. **Write the ledger first.** `docs/test-audits/<YYYY-MM-DD>-<slug>.md`, per `references/ledger-format.md`: a row for every declaration judged, retained ones included, marked R, F, C or D. A D or C row is not ready until it carries every candidate-evidence field below.
6. **Edit one owner-boundary batch, tests first.** Delete the D rows, move each C row's assertion into its keeper first, repair each F row. Never add a replacement test that restates the one removed. Never edit source or tests while the project's test runner is running. Production code stays untouched until step 8.
7. **Prove each moved or repaired assertion can fail.** For every C and F row, break the production behaviour the keeper guards, save it as a patch, and restore the file: edit it, `git diff -- <file> > docs/test-audits/<date>-<slug>/mutations/<name>.diff`, `git checkout -- <file>`. Then `bash "$SKILL_DIR/scripts/ensemble-mutation-check" --patch <diff> --test '<the keeper alone>' --expect '<the keeper's failure output>'`. `--expect` is the assertion message or the runner's failure line for that keeper, never its bare name. Exit 0 is caught: it writes `<diff>.caught`, the receipt the verifier requires; record the diff's path, relative to the ledger, in the row's Mutation cell and keep the receipt beside it. Exit 1 (survived) or 5 (inconclusive) means the keeper has not been shown to catch it: repair the keeper, or return the row to R. Exit 3 means the keeper is red before any mutation: a product bug or a broken keeper, never a row to delete. Exit 2 is a refusal: the patch does not apply, `--expect` shows up in a passing run, or a target is untracked or has unstaged changes (staged changes are fine). Exit 4 means the restore failed: **stop** and name the files.
8. **Remove the seams the batch unlocked.** Delete the test-only exports, flags, wrappers and reset hooks whose only callers were the removed tests, and list them under `## Seams removed`; do not keep aliases. Prefer a net-negative production line count.
9. **Run the owner and sibling tests** for everything the batch touched. A retained test that now fails is a product bug to reproduce, not a row to flip to D.
10. **Stage, then the preservation review.** Stage the batch, the ledger, its mutation diffs and their `.caught` receipts by path, never `git add -A`. `bash "$SKILL_DIR/scripts/ensemble-test-audit-review-artifact" <ledger>` writes them into one file and prints its path. Then run the peer the way `/en-review` does:
    - `eval "$(bash "$SKILL_DIR/scripts/ensemble-detect-host")"` for `PEER_CMD`, `PEER_FORMAT`, `PEER_TURNS`, `PEER_MODE`; read `peer_model_<peer>` and `peer_effort_<peer>` with `$SKILL_DIR/scripts/ensemble-config-get` and translate them with `$SKILL_DIR/scripts/ensemble-peer-flags`.
    - Build the prompt: `bash "$SKILL_DIR/scripts/ensemble-build-peer-prompt" --brief "$SKILL_DIR/references/peer-brief.md" --artifact-file <artifact> --project-context "<one line>" --goal "Preservation review of a test-audit batch" --peer-mode "$PEER_MODE"`.
    - Source `$SKILL_DIR/scripts/ensemble-peer-invoke` and, with `ENSEMBLE_PEER_REVIEW=true`, start it detached with `ensemble_peer_start --access read-tree --schema "$SKILL_DIR/scripts/peer-findings.schema.json"` plus the flags above; `ensemble_peer_wait` in slices up to the read-tree ceiling (1200s), then `ensemble_peer_result`. Findings follow `references/finding-schema.md`.

    Decide each finding per the brief's last section. A restored row gets its own caught mutation (step 7), is re-staged, and the artifact is rebuilt before step 11. Write the reviewer into the ledger's `preservation_review`: `cross-agent`, or `single-agent-fallback` when only the host's CLI ran, which still counts as a fresh reviewer. **A decision of `peer: "off"` or any `peer-failed:*` reason stops the run here, uncommitted**, with the batch staged and the reason reported; the way back is `--resume <ledger>`, with `--no-peer` only if the user chooses to commit unreviewed.
11. **Verify the ledger.** `bash "$SKILL_DIR/scripts/ensemble-test-ledger-verify" <ledger> --tree`. It checks every row against its mark, and every named declaration against `baseline_sha` and the working tree. Exit 1 prints one line per violation: fix the ledger or the batch, never the verifier's input to dodge it, and re-run. Exit 2 means the file is malformed. **Nothing is committed until it exits 0.**
12. **Commit** the batch and the ledger together, staged by path, never `git add -A`, with a `Test-Audit-Ledger: <ledger path>` trailer so the justification is findable from the commit.
13. **Hand off**:
   - the anti-pattern categories removed, with counts;
   - production seams simplified;
   - retained false positives, and why each stays;
   - the proof actually run, focused and full;
   - who did the preservation review (the ledger's `preservation_review`), and each finding with its decision;
   - production and tooling lines changed, reported separately from test and test-support lines (`git diff --numstat`);
   - named follow-ups: the next batch's candidates and any product bugs found.

## Retention bar

Keep a test when it independently enforces a contract someone outside the code depends on: a public API, protocol, config, migration, storage, security, platform, default value, prompt or generated text, package, release or architecture contract. Also keep:

- call ordering, when the order is observable behaviour;
- a regression test with a credible failure mode;
- **source inspection, when it is the cheapest independent guard of the contract**: it fails when the user-facing key, path or text changes and survives a rename of an identifier. In a repo whose product is prose (skill files, prompts, templates), a test that greps that prose may be the contract itself; the carve-outs in `references/good-tests.md` apply;
- a retained test that fails on the baseline. Treat it as a probable product bug: reproduce it and report it rather than deleting it.

**Slow or static is not a reason to delete.** A test that resembles implementation may still be the only independent proof of a contract; show otherwise before removing it. An existing test that breaks under a behaviour-preserving refactor is **suspect, not automatically deletable**.

## Candidate evidence

Every D and C row carries all of these before any edit. A missing field means the candidate is not ready:

- the exact test name and location;
- the failure it can actually detect;
- the non-test callers of the production code or support seam it covers;
- the stronger proof that remains at the owning boundary, or why no proof is needed;
- the history: why the test or seam exists;
- the production or test-support deletion it unlocks;
- the risk, and the command that validates the batch.

## What this skill never does

- Deletes a test that fails on the baseline.
- Converts an uncertain candidate into a deletion to raise the count.
- Pushes, opens a PR, or merges.
- Runs from inside a peer subprocess, or is invoked by another skill.

Adapted from OpenClaw's `test-audit` skill (MIT): the value bar, retention bar, candidate evidence and campaign order are theirs; the committed ledger and its checks are Ensemble's.
