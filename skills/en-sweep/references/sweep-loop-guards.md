# Sweep loop guards

`/en-sweep` runs on `push` to `main`. Its auto-merging PRs are themselves pushes to `main`. Without guards, this creates an infinite loop. Five guards in place; defense-in-depth.

## Guard 1 — Skip sweep-authored commits

The workflow's first step inspects `${{ github.event.head_commit.author.name }}` and `${{ github.event.head_commit.message }}`:

```bash
AUTHOR='${{ github.event.head_commit.author.name }}'
MSG='${{ github.event.head_commit.message }}'

if [ "$AUTHOR" = "ensemble-sweep[bot]" ] \
   || [[ "$MSG" == "chore(en-sweep):"* ]] \
   || [[ "$MSG" == "chore(arch):"* ]] \
   || [[ "$MSG" == "chore(plans):"* ]] \
   || [[ "$MSG" == "chore(learnings):"* ]] \
   || [[ "$MSG" == "chore(maps):"* ]] \
   || [[ "$MSG" == "chore(docs):"* ]]; then
  echo "Skipping: sweep-authored commit"
  exit 0
fi
```

The `chore(*)` prefix list reflects the conventional-commit scopes sweep uses for its batches. Adjust here if new sweep batch types are added.

## Guard 2 — Concurrency group

GitHub Actions `concurrency:` keyed on the branch:

```yaml
concurrency:
  group: en-sweep-${{ github.ref }}
  cancel-in-progress: false
```

`cancel-in-progress: false` queues subsequent triggers rather than cancelling the running job. Result: only one sweep run per branch at a time. Subsequent triggers wait their turn.

## Guard 3 — Sweep PR labeling

Every sweep-opened PR carries the label `en-sweep`. After a sweep PR auto-merges, the merge commit triggers another `push` event. Guard 3 inspects whether that merge came from a labeled PR:

```bash
PR_NUM=$(echo '${{ github.event.head_commit.message }}' | grep -oE '#[0-9]+' | head -1 | tr -d '#' || true)

if [ -n "$PR_NUM" ]; then
  LABELS=$(gh pr view "$PR_NUM" --json labels -q '.labels[].name' 2>/dev/null || true)
  if echo "$LABELS" | grep -q '^en-sweep$'; then
    echo "Skipping: merge of an en-sweep-labeled PR"
    exit 0
  fi
fi
```

Tighter than Guard 1's commit-message regex — catches edge cases where the merge commit message doesn't carry the `chore(*)` prefix (e.g., a squash-merge with an edited commit message).

## Guard 4 — No-material-diff termination

After running all checks, if **no fix-PR batches were generated**, exit silently. No notification, no commit, no PR.

```bash
if [ ${#BATCHES[@]} -eq 0 ]; then
  echo "No drift detected. Sweep is a no-op for this run."
  exit 0
fi
```

Keeps sweep quiet when there's nothing to do — no spam in the source PR's comments, no empty PRs to clean up.

## Guard 5 — Recursion depth cap

The workflow checks `${{ env.ENSEMBLE_SWEEP_DEPTH }}`; defaults to `0`, increments on each spawn. Hard cap at depth 1.

```bash
if [ "${ENSEMBLE_SWEEP_DEPTH:-0}" -ge 1 ]; then
  echo "Sweep recursion depth cap reached. Skipping."
  exit 0
fi
export ENSEMBLE_SWEEP_DEPTH=$(( ${ENSEMBLE_SWEEP_DEPTH:-0} + 1 ))
```

Defense-in-depth — Guards 1 and 3 should already prevent cascades. This is the belt-and-suspenders backstop. **Sweep never spawns sweep.**

## Why all five

Each guard addresses a different failure mode:

| Failure | Caught by |
|---|---|
| Sweep-authored commit hits `main` and re-triggers | Guards 1, 3 |
| Two sweep runs collide (race during long run) | Guard 2 |
| Bug in batch logic produces empty PR set | Guard 4 |
| Sweep somehow invokes itself in-process | Guard 5 |
| Squash-merge changes commit message; Guard 1 misses | Guard 3 |
| `gh` CLI auth fails (Guard 3 returns empty labels) | Guard 1 (still catches by commit-message prefix) |

If any one guard misses, another catches.

## Testing the guards

Per foundation §20, sweep has dedicated dry-run tests that adversarially trigger each guard:

- **Test 1:** Push a commit by `ensemble-sweep[bot]` — assert sweep exits at Guard 1.
- **Test 2:** Trigger two pushes in quick succession — assert Guard 2 queues the second.
- **Test 3:** Merge a PR with `en-sweep` label and a non-`chore(*)` commit message — assert Guard 3 catches it.
- **Test 4:** Run sweep against a clean repo (no drift) — assert Guard 4 silent exit.
- **Test 5:** Set `ENSEMBLE_SWEEP_DEPTH=1` in env — assert Guard 5 exits.

Tests live under `tests/en-sweep/dry-run/`.

## When a guard fires

Each guard logs a single line to GitHub Actions output and exits 0 (success — skipping is correct behavior). The workflow shows up as "skipped" in the action history; no PR comment, no failure email.

## What guards don't protect against

- **A bug in the doc-only check** (`bin/ensemble-doc-only-check`) that lets a code-file edit through. That's a separate guard — see `references/sweep-security-model.md`.
- **A malicious actor with `contents: write`** who pushes a commit author-spoofing as `ensemble-sweep[bot]`. Out of scope; addressed by repo access control, not the workflow.
- **Branch protection misconfiguration** that bypasses sweep's checks. See `references/sweep-security-model.md`.
