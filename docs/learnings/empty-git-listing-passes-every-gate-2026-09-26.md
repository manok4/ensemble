---
title: A gate over a git file listing passes silently when the listing fails
applies_when: Writing a script that checks "every file (or declaration) in a git listing", or a guard that decides what a batch changed
date: 2026-09-26
tags: [git, shell, verifiers, silent-failure, guards]
related: []
status: active
---

# A gate over a git file listing passes silently when the listing fails

A check of the form "every file in `git ls-tree` / `git diff --name-only` has a
row" treats an empty listing as "nothing to check" and passes, so a listing that
*failed* is indistinguishable from a clean one unless its exit code is read.
Git makes the failure easy to trigger: `""` is not a pathspec (git 2.50 exits 128
with "empty string is not a valid pathspec"), so mapping a whole-repo scope of
`.` to an empty string, which reads naturally when building `-- <scope>`, turns
every such gate off. EN21's `ensemble-test-ledger-verify` did exactly that: with
`scope: .` its lane-coverage, full-coverage and rebaseline checks all passed on a
ledger that should have failed four ways, while the same ledger with `scope: src`
reported every violation. It was found by review, not by a test, because every
fixture used a named subdirectory. Use `.` for the whole tree, die on a non-zero
exit from any listing a gate iterates, and give the whole-repo scope its own
scenario.

The listing can also succeed and still not show the change. EN32's
`ensemble-doc-only-check` passed three bypasses a review found, each a listing
that was valid but narrower than the batch: `git diff --cached` against `HEAD`
misses an edit committed on the branch before the check runs; under default
rename detection `--name-only` prints only a rename's new path, so a source
file moved into `docs/` hides its deletion; and `ls-tree` / `ls-files`
resolve pathspecs against the current directory, so a call from a
subdirectory finds nothing. A guard lists against the branch's merge-base with
the default branch, with `--no-renames`, from the repo root, and gives each of
those three cases a test.

Last updated 2026-11-24.
