# `--from-legacy <path>` — mint a new plan from an archived one

Read only when `/en-plan` is invoked with `--from-legacy`. The legacy file (typically `docs/plans/legacy/<file>.md`, archived by `/en-setup`'s retrofit) is **input**: it is never modified and never moved. The flag mints a *new* Ensemble plan from it.

1. Read the legacy file whole. Assume no frontmatter; treat all of it as narrative.
2. Confirm before doing anything else: *"Migrate this legacy plan into Ensemble. I'll run the normal plan flow (research → questions → U-IDs → peer review). The legacy file stays in `docs/plans/legacy/` untouched. Confirm? (y/n)"*
3. On `y`, treat the legacy content as the rough description (the source-the-request step) and run the flow normally: research, planning questions, U-IDs, a fresh `<PREFIX><NN>`, a new file in `docs/plans/active/`.
4. The new plan's frontmatter carries `migrated_from: docs/plans/legacy/<file>.md`.
5. Append a back-reference to the legacy README's list of archived files, *"Migrated to <new plan path> on <date>."*, in the same working-tree change as the plan file so the auto-commit picks it up.

Never convert a legacy plan in place. The point of the flag is proper R-ID and U-ID assignment and a peer pass, which an in-place edit would skip.
