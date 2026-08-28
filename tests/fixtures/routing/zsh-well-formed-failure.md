---
expect_type: solution
expect_path: docs/learnings/
---
Peer review returned a well-formed {"peer":"off","reason":"peer-failed"} because
BASH_SOURCE is unset under zsh, so the helper could not find its own directory. A
broken helper was indistinguishable from an unreachable peer. The durable lesson
is that a helper answering plausibly when broken is worse than one that fails.
