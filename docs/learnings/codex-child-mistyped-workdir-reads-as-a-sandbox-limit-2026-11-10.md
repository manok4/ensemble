---
title: A Codex child that mistypes its workdir looks like a sandbox limit
applies_when: Concluding from a live Codex run that a spawned child cannot run commands, push or reach the network
date: 2026-11-10
tags: [codex, live-tests, subagents, diagnosis]
related: [docs/learnings/live-control-that-contradicts-the-agent-never-fires-2026-10-30.md]
status: active
---

# A Codex child that mistypes its workdir looks like a sandbox limit

In EN28's U4 reproduction, a Codex `spawn_agent` child was handed a long
absolute scratch path in its message. It passed that path back as the `workdir`
of every `exec_command`, with one character changed (a `.` where the directory
name has a `-`). Every command then failed with
`CreateProcess ... No such file or directory`. The child's own account blamed a
missing tool and a workspace that "disappeared". That reads as a child sandbox
that cannot exec, which would have sent U4 to its "Codex dispatch unsupported"
outcome. The rollout's `cwd` fields held the mangled path, and that was the real
cause. The same spawn worked once the message said the working directory was
already right and never to pass `workdir` or `cd`, and it later pushed and
opened a PR. So before concluding a Codex child cannot do something, read the
paths and arguments in its rollout, not its explanation, which is D115's lesson
about self-reports in another form. Keep child messages free of long absolute
paths the child might copy. Evidence: the 2026-11-10 Codex rows in
`tests/evals/ledger.md`.
