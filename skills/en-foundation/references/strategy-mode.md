# Strategy mode

How `/en-foundation` writes or revises a repo's Strategy section: §1 of
`docs/foundation.md`, titled `## 1. Strategy`, opened by the marker
`<!-- strategy: author-approved YYYY-MM-DD -->`. Read under `--strategy`, and at
step 9 of a fresh or retrofit run, where §1 is drafted this way.

The section is the project's accept/resist policy. `en-review`'s peer checks
every change against it, `/en-plan` names the ST-IDs a plan touches, and the lint
resolves ST citations. Only this flow writes it, and only with the author: a
strategy the author did not approve is a guess that every review then enforces.

The anatomy is in `references/templates/foundation-template.md` §1: an identity
opener, 3 to 6 `### ST<N>. <heading>` principles, a `### Scope` of concrete
non-goals, and the closing pair "A change aligns when ..." and "A change should
be resisted when ...". 40 to 70 lines. No roadmap, no feature list, no marketing
voice.

## 1. Locate

Run `bash "$SKILL_DIR/scripts/ensemble-strategy-section"`.

- **It prints a section: delta mode.** That section is the baseline. The run
  keeps it and proposes only line-level changes, each backed by evidence newer
  than the marker's date, and each accepted or declined on its own. It never
  redrafts the section from scratch.
- **It prints nothing:** the repo has no approved section, and the run drafts one.
  First check for an unmarked heading the reader would match (`## Strategy` or
  `## <N>. Strategy`, outside fenced code). If there is one, ask the author
  whether it is the strategy: on yes, step 7 writes into that heading and adds
  the marker; on no, it is retitled before step 7 adds a section, so the file
  never holds two Strategy headings.
- **It exits 3:** `docs/foundation.md` has two Strategy headings. Stop and ask
  the author which one is the strategy. Write nothing until they answer.
- **`--strategy` with no `docs/foundation.md`:** stop and say to run
  `/en-foundation` first. Write nothing.

## 2. History gate

Applies to `--strategy` and `--retrofit` only. A fresh (greenfield) run skips
this step and step 3, and drafts from the author's answers.

Count commits with `git rev-list --count <default-branch>` (the branch
`origin/HEAD` names, else `main`, else `HEAD`). Under 20, stop with:

> This repo has <N> commits; a strategy drawn from that little history would be guesswork.

The run continues only when the author says, in their own words, to proceed
without history. A yes to a question you phrased is not that. Then every line
cites the author's answers instead of history.

## 3. Mine

Gather what the project has actually done:

- Merged PRs: `gh pr list --state merged --limit 100 --json number,title,mergedAt`
  for titles, then 8 to 15 full bodies spread across the range. Without `gh` or a
  remote, `git log --first-parent <default-branch>` instead.
- The README, foundation §2, any principles section, and the D-ID log in §4.

Write an evidence sheet to `/tmp/ensemble/en-foundation/<run-id>/strategy-evidence.md`,
never into the repo: one row per value the project acts on, with the PRs,
commits, files and D-IDs that show it. Drop any generic virtue ("quality",
"simplicity") that has no specific evidence behind it.

## 4. Draft

Draft to the anatomy above. Every line traces to a row of the evidence sheet or
to an author answer. Principles are declarative and in the present tense, and
each is one a reviewer could apply to a concrete PR. A non-goal names an example
of what it rules out.

## 5. Stress-test

Write 8 to 12 fault-line hypotheticals that test the draft: tempting
off-mission features, two principles that collide, slippery slopes, scope
expansions, and identity questions the draft leaves open. Each one names the
proposal in 2 to 4 sentences, quotes the ST line it tests, and steelmans both
answers. Replace any whose answer you can predict: a question with an obvious
answer teaches the draft nothing.

Ask them one at a time with `QUESTION_TOOL`, never as a batch. After each
answer, fold the reasoning into the draft and show a one-line changelog, such as
`H3 no → ST2 now says local files only, no sockets`. Never copy the
hypotheticals or the answers into the repo.

## 6. Approve

Show the full section and ask the author to approve it. The author approves the
full text explicitly. Silence, or approving one card, is not approval. Declined:
write nothing, and stop.

## 7. Write

- **Delta mode:** replace only the lines of the section the reader located,
  wherever it sits and whatever its number. Nothing else in the file moves.
- **An unmarked heading the author named in step 1:** replace its body and add
  the marker; nothing else moves.
- **No section yet:** retitle §1 in place to `## 1. Strategy` and replace its
  body. With no §1, insert the section after the title block, before the first
  `##` heading.

Set the marker's date to today. ST-IDs are append-only: a new principle takes
the next unused number, and a removed one keeps its heading, marked
`(retired YYYY-MM-DD)`, with its number never reused.

## 8. Consolidate

List numbered proposals for lines elsewhere in the repo's docs that repeat the
strategy, judged by meaning, not wording. §2.2 Non-Goals becomes the one line
"Non-goals live in §1 Strategy, Scope."; other repeats are deleted or replaced
with a pointer. Apply only the ones the author says yes to.

When `AGENTS.md` lacks them, offer its "Where things live" row
(`| Strategy: what the project owns, refuses, and how a change is judged | docs/foundation.md §1 (ST-IDs) |`)
and `ST<N>` in its Stable IDs line. `/en-setup` never rewrites an existing
`AGENTS.md`, so nothing else adds them.

## 9. Close debt

When `docs/plans/tech-debt-tracker.md` has an open entry with rule key
`strategy-missing`, which `/en-sweep` files for a repo with no section, move it
to Resolved with `Resolved: YYYY-MM-DD by /en-foundation --strategy`.

## 10. Peer

Under `--strategy`, run the Outside Voice review that SKILL.md describes, with the
section the reader prints, written to a temp file, as `--artifact-file`, and
`--goal "Strategy review"`. A fresh or retrofit run keeps its whole-foundation
pass, which covers §1.
