# Running a bundled script

Every script this skill invokes lives in its own `scripts/` directory. Anchor
each call to that directory:

```
SKILL_DIR="<absolute path of the directory containing the SKILL.md you just read>";
bash "$SKILL_DIR/scripts/ensemble-lint" --scope docs/
```

## Why the anchor, and not a bare relative path

The Bash tool's working directory is the **user's project**, not the skill
directory, on Claude Code and Codex alike. A bare `bash scripts/ensemble-lint`
therefore resolves against the project and exits 127. A capable agent often
translates the path anyway, but the failure mode is a fenced block copied
verbatim into a Bash call, and recovering from that costs a wasted round trip.
Anchoring bakes the resolution into the command, so it does not depend on the
agent noticing.

`SKILL_DIR` is **model-filled**, not a harness variable. Every host loads
SKILL.md from a real absolute path you know, so you supply it. That is exactly
why it works everywhere: it depends on no host-specific variable.
`${CLAUDE_SKILL_DIR}` is not a portable alternative — it is a Claude-Code-only
content substitution that expands to empty on Codex, which turns a guarded call
into a silent skip.

## Two things that look like style and are not

**Keep the trailing `;` on the assignment line.** Some hosts flatten a fenced
multi-line block into a single line before executing it. Without the semicolon,
`SKILL_DIR="…"` + newline + `bash "$SKILL_DIR/…"` collapses into the
env-var-prefix form, where the shell expands `$SKILL_DIR` *before* the
assignment takes effect. It expands to empty, the path becomes
`/scripts/…`, and the call fails with "No such file or directory".

**Set it inline in the same command, every time.** Shell state does not persist
between Bash tool calls, so `SKILL_DIR` cannot be set once and reused.

A script that needs its *own* directory — to read a sibling it sources — derives
it from `BASH_SOURCE`, not from `SKILL_DIR`. `SKILL_DIR` is the orchestrator's
shell variable and is not exported to the child process.
