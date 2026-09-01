---
expect_type: decision
expect_path: docs/decisions/
---
We chose to derive each skill's file set from its own body over maintaining a
declaration of it. A declaration can say a file was listed; it can never say
anything reads it, and ours carried a reference calling itself the source of
truth for CLI flags while nothing consulted it. A path counts as payload when it
is backticked, linked, or fenced, and not when it is bare prose.
