# The parts of setup that are text, not decisions

Read when the step that owns each of these fires. They live here because they
are fixed blocks a run prints or pastes, not judgements it makes: the flow keeps
when each fires and what it records.

## The sweep machine's commands

    2. **Print the machine-side commands**, with this repo's path filled in:
       ```
       # on the sweep machine, once per repo (the installer is carried by /en-sweep, beside this skill):
       bash <ensemble>/…/en-sweep/scripts/install-sweep-schedule add-repo <path-to-this-checkout>
       # once per machine (re-run to change cadence or the default model):
       bash <ensemble>/…/en-sweep/scripts/install-sweep-schedule install --cadence weekly --hour 9 --model <alias-or-id> --effort high
       ```
       and note that the machine needs `codex`, `gh` (logged in with an identity allowed to merge green PRs) and `jq` on PATH, a clean clone of this repo, and `sweep.model` / `sweep.effort` in that clone's `.ensemble/config.local.yaml` if this repo should override the machine default.
    3. **Note the activity gate:** "The runner skips a repo silently when no non-sweep commits landed since the last sweep; `--force` bypasses it."

## The verification-receipt notice

14. **Verification-receipt notice (informational).** Surface once, and write nothing:

    > "`/en-build` records which checks passed against an exact working tree, and `/en-ship` skips what
    > that receipt covers. Your pre-push hook can read the same receipt instead of re-running a suite
    > `/en-ship` finished seconds earlier. `/en-ship` carries a `verification-receipt` reference with a
    > snippet to paste into `.git/hooks/pre-push`."

    **This step never creates or edits a hook.** A hook is where a project encodes its own policy;
    rewriting one on a user's behalf is help nobody asked for, and `/en-ship` never bypasses hooks
    either. Print the pointer and move on.

## Recommended next steps

16. **Recommend next steps:**
    ```
    Two paths:
      - Run /en-foundation --retrofit to back-fill docs/foundation.md and docs/architecture.md from existing code.
        (Recommended for projects that will see continuing development with Ensemble.)
      - Or jump to /en-plan for the next feature; foundation can be filled in later.

    Once /en-foundation has settled and you've seen the codebase's
    conventions surface in real reviews, consider:
      - /en-learn capture — file the first real learning when one earns it
        from the codebase (opt-in; one-time; lower-confidence entries).
    ```

