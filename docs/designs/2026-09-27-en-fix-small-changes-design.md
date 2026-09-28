---
type: design
created: 2026-09-27
topic: /en-fix, one skill that takes a small bug fix or improvement from request to PR without a plan
status: accepted
related_plan: EN23
---

# /en-fix, one skill that takes a small bug fix or improvement from request to PR without a plan

## Problem

Small work has no good route today. `/en-plan` and `/en-build` cost a plan file, research agents, a unit loop and a post-build phase, which is more than a one-concern change returns. The cheaper routes each stop short:

- `/en-plan`'s no-file path states the change and stops. `/en-build` cannot run without a plan file, so the user makes the edit by hand (`skills/en-plan/references/plan-prewrite.md:19`).
- `/en-debug` code mode fixes bugs test-first, then only suggests `/en-ship` (`skills/en-debug/SKILL.md:145-150`). It covers bugs, not improvements, and runs no review.
- `/en-simplify` preserves behavior exactly, so it cannot make an improvement.

A small improvement, done with a test, a review and a PR, has no skill at all. `/en-fix` is that skill. It also becomes the only skill that writes small fixes, which lets `/en-debug` return to diagnosis.

## Constraints and context

Verified in this repository:

- **No `en-fix` exists** in `skills/`, `README.md`, `AGENTS.md` or `docs/foundation.md`.
- **`/en-review` already has the review this needs.** A bare `/en-review` runs the cross-agent peer as the sole reviewer, and `--lite` gives it a one-turn brief sized for quick fixes. `--lite` fails closed: a risk signal in the diff forces the full brief (`skills/en-review/SKILL.md:68`, `:113`, `:118`). It applies accepted findings and writes a verification receipt when its post-review check passes (`skills/en-review/SKILL.md:139`).
- **`/en-ship` needs no build receipt.** It runs lint, typecheck and targeted tests itself when no valid receipt exists, and accepts one `/en-review` wrote for the identical tree (`skills/en-ship/SKILL.md:42-53`).
- **Only `/en-flow` chains lifecycle skills today** (`skills/en-flow/SKILL.md:12`). `/en-loop` suggests `/en-ship` but does not invoke it. `/en-fix` becomes the second skill that invokes others in sequence and should follow `/en-flow`'s pattern, including passing the user's words rather than `$ARGUMENTS` (D70, `skills/en-flow/SKILL.md:44`).
- **No skill calls `/en-debug`** (`skills/en-debug/SKILL.md:16`). Its code-mode gate is blocking because a person is always present. `/en-fix` changes that, so the note and any remaining blocking question in `/en-debug` need a caller-aware path.
- **Five skills are manual-invoke only** (`disable-model-invocation: true`): en-flow, en-loop, en-setup, en-sweep, en-test-audit.
- **A new skill must be registered** in the README skill catalog (`README.md:287`) and foundation §5.1 (`docs/foundation.md:253`). `tests/lint/readme-catalog-drift.test.sh` and `tests/lint/foundation-catalog-drift.test.sh` fail otherwise.
- **Removing `/en-debug`'s fix path touches:**
  - `tests/lint/en-debug-fix-loop.test.sh`, which asserts the "Fix it now" choice;
  - D62 and D89 in `docs/foundation.md`, which record the convergent/divergent rule and the findings-before-gate ordering;
  - the README line "code mode fixes only on request";
  - `skills/en-debug/SKILL.md` step 4 and the fix-choice gate (lines 139-150).
- **Leanness rule** (`docs/designs/2026-09-26-agent-trust-strategy-design.md`, "replace, don't add"). `/en-fix` qualifies because it replaces plan plus build for small work and takes over `/en-debug`'s fix path. It changes none of the four hot-path skills. It only calls `/en-review` and `/en-ship` as they are.

## Assumptions & unverified claims

- Assumed that the Linear MCP `get_issue` result carries a suggested branch name. Refuted in planning: nothing reads one, and branches are built as `<IDENT>-<slug>` (`skills/en-build/references/build-preflight.md:150`). EN23 follows that pattern. Whether `get_issue` returns labels is still unverified.
- Assumed `/en-review --lite` runs for a caller without a blocking question. Confirmed in planning for `--mode headless` (`skills/en-review/CONTRACT.md`). A P0 halts its automatic edits, and EN23 treats a P0 as a stop.

## Decisions settled in the brainstorm

1. **Scope.** Both bug fixes and small improvements.
2. **What counts as small.** One concern that fits in one commit, with no risk surface: auth, payments, migrations, or external contracts. This reuses `/en-plan`'s never-skip rule (`skills/en-plan/SKILL.md:102`), so the two skills agree. There is no file-count limit, because a rename across eight files is still small. Anything over the limit gets handed to `/en-plan`.
3. **Division of labor.**
   - `/en-debug` diagnoses only. It never fixes or ships anything. Run directly, it ends with the diagnosis and offers `/en-fix`.
   - `/en-fix` owns every small change.
4. **When `/en-debug` runs.**
   - For a bug, it always runs first. Its trivial-bug fast path keeps obvious cases cheap (`skills/en-debug/SKILL.md:126`).
   - For an improvement, it never runs up front. An improvement has no symptom to trace. If the work hits real broken behavior partway through, `/en-fix` calls `/en-debug` then.
5. **Bug or improvement.** This is `/en-debug`'s own convergent/divergent split (D62).
   - A bug restores behavior everyone agrees is correct.
   - An improvement changes behavior that works as designed, and the user's request is the decision `/en-debug` would otherwise refuse to make.
   - When a Linear issue has a Bug label or type, `/en-fix` uses it. Otherwise it makes the call from the description and states it up front, and the user can override it.
6. **Gates before commit.**
   - A failing test first for a bug, and a test for any behavior change.
   - Lint, typecheck and targeted tests.
   - A self-review of the diff.
   - No separate simplify pass.
7. **Review.** `/en-review --lite` runs on every change, however small, and applies its findings. If round 2 still blocks, the run stops without shipping, reports the findings, and offers `/en-plan`. A second rejection means the change was not small (`docs/learnings/repeated-review-rejects-are-a-design-signal-2026-09-11.md`).
8. **Ship.** When the review passes, `/en-fix` invokes `/en-ship` for a normal PR. There is no auto-merge unless `--auto-merge` was passed to `/en-fix`.
9. **Branch.** If the run starts on the default branch, `/en-fix` creates a new branch first.
10. **Input.** Free text, context from the current conversation, a `file:line`, or a Linear identifier.
11. **Linear.**
    - Read the issue and its comments for the problem statement.
    - Name the branch from the issue.
    - Reference the identifier in the PR so Linear's GitHub integration links and closes it.
    - No status writes and no comments.
12. **Invocation.** Manual-invoke only. `/en-fix` pushes and opens a PR, so an offhand "fix this typo" must not trigger it.
13. **`/en-plan`'s no-file path hands to `/en-fix`.** It no longer tells the user to make the edit by hand. This goes in the same plan.

## Approaches considered

### A. New `/en-fix` skill that invokes existing skills

**Sketch:** a new skill runs triage, then `/en-debug` diagnosis for bugs or a scoped change spec for improvements. Then it runs a test-first change, lint, typecheck and targeted tests, and one commit. After that come `/en-review --lite` and `/en-ship`. It holds no review or ship logic of its own. `/en-debug` loses its fix path, and `/en-plan`'s no-file path points here.

**Pros:**
- One skill writes small changes, and one skill diagnoses. The overlap between `/en-debug` code mode and a new fixer never exists.
- It reuses `/en-review`'s risk escalation and receipt, and `/en-ship`'s preflight, unchanged.
- Net skill text is roughly flat, since `/en-debug` shrinks by its fix path.

**Cons:**
- It is the second skill that invokes lifecycle skills, so it inherits `/en-flow`'s cross-host invocation care (D70).
- It is one more skill to register, lint and keep in parity.

### B. Plan-less mode in `/en-build` (`/en-build --quick "<desc>"`)

**Sketch:** `/en-build` synthesizes a one-unit plan in memory and runs its normal unit loop and post-build phase.

**Pros:**
- No new skill. It reuses the unit loop, receipts and audit trailers.

**Cons:**
- It brings along the post-build phase (simplify, audit, learn), which small work does not need.
- It adds a fifth case to `/en-build`'s pre-flight matrix, in a SKILL.md that is already 24.2K and close to the size lint.
- It does not help `/en-debug`, and it does nothing for bugs.

### C. Broaden `/en-debug` into the fixer

**Sketch:** `/en-debug` code mode accepts improvements and chains review and ship after its fix.

**Pros:**
- No new skill. It keeps the root-cause discipline right next to the fix.

**Cons:**
- It contradicts the settled decision that `/en-debug` is diagnosis-only.
- An improvement has no root cause, so most of the skill would not apply.
- A skill named "debug" that ships PRs for UI tweaks is misleading.

## Recommendation

**Approach A.** It is the only option that meets decision 3 (one diagnoser, one fixer) without growing a hot-path skill. The leanness rule counts it as a replacement rather than an addition: small work stops going through plan plus build, and `/en-debug`'s fix path moves out instead of being duplicated. B keeps the overhead the user wants to avoid, and C conflicts with a decision already made.

## Devil's advocate

- **Scope creep.** `/en-fix` will be the easiest way to get code written, so medium work will drift into it. The triage check alone will not hold, because the agent judges "one concern" generously. The review cap is the real limit: a second blocked round stops the run and offers `/en-plan`. Planning should decide whether triage also refuses a diff that grows past what the lite brief escalates on.
- **Review cost on trivial changes.** A typo pays for a peer turn. The lite brief keeps that to one turn with access to the diff only. The user accepted this so that no PR goes out unreviewed.
- **Divergent diagnosis while `/en-fix` is running.** If `/en-debug` returns a divergent fix, an unclear causal chain, or "design problem", `/en-fix` must stop and show the diagnosis. It must never pick a side, since that is exactly the rule D62 exists to enforce.
- **Chained runs fail in the middle.** A run can die between commit and PR, for example on a peer timeout or a failed push. `/en-fix` should report where it stopped, and the next step should be `/en-review --lite` or `/en-ship` on the existing branch rather than a re-run.
- **Losing `/en-debug`'s direct fix.** Someone who used "Fix it now" to fix locally and keep iterating now gets a diagnosis only. They then either edit by hand or run `/en-fix`, which ships. The user chose this deliberately, so it is not an oversight.

## Open questions

- Should `/en-fix` accept a TD ID from the debt register as input? EN22's correction router produces small lint and test TD entries that fit this skill. It was not settled here.
- For improvements, how much of the change spec does `/en-fix` show before editing? One confirmation, or none when the request is specific?

## Next steps

- Run `/en-plan` with this design. The plan covers:
  - the new skill;
  - the `/en-debug` fix-path removal and its four touch points;
  - the `/en-plan` no-file hand-off;
  - catalog registration.

  Set a byte budget for each SKILL.md touched.
