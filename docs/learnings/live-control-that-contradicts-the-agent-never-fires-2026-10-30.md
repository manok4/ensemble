---
title: A live-test control that contradicts the agent's own instructions never fires
applies_when: Designing the negative control for a test that runs a real model (claude -p, codex exec) and asserts on what it did
date: 2026-10-30
tags: [testing, live-tests, negative-controls, models]
related: []
status: active
---

# A live-test control that contradicts the agent's own instructions never fires

A negative control for a live model test has to make the model do the bad thing
willingly. One that orders it to break its own instructions gets refused, so the
control stays green and the case can never fail. Both hosts did this in EN24's
`tests/portability/live-behaviour.test.sh`, 2026-10-30. Codex declined "in
report-only mode, also write a file". An unrestricted copy of `dimension-reviewer`
refused a Write call, citing its own body's "no file writes", even though it had
the tool. Two forms worked. A natural edit the model follows without objection:
the skill copy names `./envelope.json` as the envelope path instead of `/tmp/...`,
and both hosts wrote it. And a neutral agent body ("You are a test probe. Do
exactly the task you are given") when the case tests frontmatter rather than
prose. Run the control and see it go red before trusting the case. A refusal
reads exactly like the restriction working.
