# Sweep loop guards

> **This file described a `push`-triggered sweep until 2026-09-03.** Back then
> sweep fired on every push to `main`, its own auto-merging PRs were pushes to
> `main`, and five guards existed to break that cycle. **Sweep is scheduled
> now**, by launchd on a dedicated machine through `scripts/ensemble-sweep-runner`
> (D101; GitHub Actions until then), so it cannot trigger itself, and the two
> guards whose only job was catching a self-trigger are gone rather than
> demoted. Their numbers are not reused: this file and `SKILL.md` count the
> same three guards the same way.

The cadence is the rate-limiter. What remains guards against overlap, noise,
and in-process recursion.

## The activity gate comes first

Before any guard runs, `scripts/ensemble-sweep-activity-check` decides whether
the cycle happens at all: it finds the most recent sweep-authored commit and
counts the non-sweep commits since. Zero means skip, with no LLM call.

It is not numbered as a guard because it protects a different thing. The guards
below stop sweep from running *twice* or *forever*; the gate stops it from
running *pointlessly*. Its correctness rests on no human ever writing a commit
in one of sweep's scopes, which is why the scope list is short and deliberate.
See `SKILL.md`'s activity-gate section, and `tests/en-sweep/activity-gate/`.

## Guard 1 — One run per machine

```bash
mkdir "$LOCK_DIR" || { log "another run holds $LOCK_DIR"; exit 0; }
printf '%s\n' "$$" > "$LOCK_DIR/pid"; trap 'rm -rf "$LOCK_DIR"' EXIT
```

The runner takes `~/.ensemble/sweep.lock` before touching any repo and skips,
exit 0, when another run holds it; a lock whose pid is dead is taken over. A
second run is skipped rather than the first killed, because a killed run can
leave half its batches open as PRs with nothing to finish them.

This still matters on a schedule: `install-sweep-schedule run-now` can land
while the weekly slot is still going.

## Guard 2 — No-material-diff termination

If the checks produce no batches, exit silently. No comment, no PR, no commit.

```bash
if [ ${#BATCHES[@]} -eq 0 ]; then
  echo "No drift detected. Sweep is a no-op for this run."
  exit 0
fi
```

Fires inside the skill, at the step named "Guard 2" in `SKILL.md`'s process
list. The activity gate covers the common no-op case earlier and more cheaply;
this covers the rest, a repo with new commits that turn out to have caused no
drift.

## Guard 3 — Recursion depth cap

```bash
if [ "${ENSEMBLE_SWEEP_DEPTH:-0}" -ge 1 ]; then
  echo "Sweep recursion depth cap reached. Skipping."
  exit 0
fi
export ENSEMBLE_SWEEP_DEPTH=$(( ${ENSEMBLE_SWEEP_DEPTH:-0} + 1 ))
```

The runner exports `ENSEMBLE_SWEEP_DEPTH=1` before launching Codex, so a
sweep that reaches this check from inside a sweep exits. This is the one guard
the scheduled model did not weaken, because what it stops was never a trigger
problem: an agent reading `SKILL.md` and invoking `/en-sweep` from inside a
sweep. **Sweep never spawns sweep.**

## What was retired, and why it is not coming back

| Retired guard | What it did | Why it is gone |
|---|---|---|
| Skip sweep-authored commits | Read `head_commit.message` on the `push` event and exited on a `chore(*)` prefix | There is no `push` trigger and no `head_commit` to read. The scope list it used lives on in the activity gate, doing a different job |
| Skip sweep-PR-labeled merges | Resolved the merge commit's PR number and exited if the PR carried the `en-sweep` label | Same reason, plus it needed `gh` auth on a path that had no other use for it |

Both existed to stop sweep re-triggering on its own merge. Nothing re-triggers
sweep now. Adding either one back would mean restoring the `push` trigger, and
that is the change to argue about, not the guard.

## When a guard fires

One line to `~/.ensemble/logs/sweep.log`, exit 0. Skipping is correct
behaviour, so the run reads as successful. A guard that exited non-zero would
train the operator to ignore a failed sweep, and the runner reserves non-zero
for a repo that genuinely failed.

## What guards do not protect against

- **A bug in `scripts/ensemble-doc-only-check`** that lets a source edit
  through. Different guard, different file: `references/sweep-security-model.md`,
  and `tests/en-sweep/doc-only-enforcement/`.
- **Branch-protection misconfiguration** that lets a sweep PR merge without its
  checks. Also `references/sweep-security-model.md`.
- **A human committing in one of sweep's scopes.** That does not loop, it
  silences: the activity gate reads the commit as sweep's own and skips the
  cycle. The defence is keeping the scope list to names humans do not reach for.
