---
title: A gate over a git file listing passes silently when the listing fails
applies_when: Writing a script that checks "every file (or declaration) in a git listing" and derives the pathspec from config or frontmatter
date: 2026-09-26
tags: [git, shell, verifiers, silent-failure]
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
