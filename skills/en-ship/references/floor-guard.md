# Floor guard (`/en-ship`'s floor-guard step)

Read when `ensemble-floor-guard` blocks, or when deciding whether an exception is warranted.

**Why it exists.** An agent under pressure has four cheap ways to turn a red build green without fixing anything: delete the failing test, skip it, silence the checker, or lower the threshold. Each is a one-line diff a reviewer can miss. "Never weaken a test" was a rule nothing enforced. The guard reads the diff `/en-ship` is about to push and refuses those four.

## What it reads

The merge base of `origin/<base>` and `HEAD`, against the working tree, plus untracked files, diffed with `--text --no-textconv --no-ext-diff` so a `.gitattributes` entry cannot hide added lines behind a binary marker or a filter. That is what this ship will commit and push, not only what is already committed. A git command that fails exits 2. An empty listing is never read as "nothing to check" (`docs/learnings/empty-git-listing-passes-every-gate-2026-09-26.md`).

## The moves

| Move | Blocks? | Detected as |
|---|---|---|
| `test-deleted` | yes | a deleted path under `tests/`, `test/`, `__tests__/` or `spec/`, or named `*.test.*`, `*.spec.*`, `*_test.*` or `test_*.py`; also a kept test file left with no assertion line |
| `test-skipped` | yes | an added line in a test file calling `.skip(`, `.only(`, `xit(`, `xdescribe(`, `it.todo(`, `t.Skip(` or `@pytest.mark.skip` |
| `checker-silenced` | yes | an added comment, outside docs, carrying `@ts-ignore`, `@ts-nocheck`, `eslint-disable`, `biome-ignore`, `noqa`, `type: ignore`, `istanbul ignore`, `nosemgrep`, `gitleaks:allow` or `pragma: ensemble-allow-secret` |
| `threshold-lowered` | yes | in a coverage config (`package.json`, `pyproject.toml`, `setup.cfg`, `tox.ini`, `pytest.ini`, `.coveragerc`, `codecov.yml`, `.nycrc`, a jest, vitest, karma or nyc config, a CI workflow), a `coverageThreshold`, `branches`, `functions`, `lines`, `statements`, `fail_under` or `min_coverage` value that fell, or was deleted |
| `assertion-removed` | no, reported | a kept test file losing more `expect`, `assert` or `should` lines than it gains |
| `stub-added` | no, reported | an added empty `catch`, a "not implemented" throw, a raise of the not-implemented error, or `pass  # stub` |

**Why two moves only report.** A test rewrite legitimately moves assertions around, and a regex cannot tell a weakened test from a reshaped one. Blocking those would train everyone to write exceptions by reflex, which costs the four blocks that matter their meaning. Reported moves go into the PR body under **Quality bar**, for a person to read.

**Why regex is acceptable here,** when the guardrail needs parsers: the guardrail faces an attacker probing its matcher. This faces an agent cutting corners. A miss lets one weakened test reach review, where it would have gone anyway. A false block costs one trailer.

## Exceptions

A blocked move is legitimate sometimes: a test superseded by a better one, a skip for an upstream outage with an issue open. Record it, never bypass it:

1. **Committed work:** a `Floor-Exception: <move> <path>: <reason>` trailer on any commit in the branch. The move and path must match exactly. One trailer excuses that move on that path.
2. **Deletions by `/en-test-audit`:** its `Test-Audit-Ledger: <path>` trailer on the deleting commit excuses `test-deleted` with no extra trailer, when that commit adds or changes the ledger and it has a row marking the path `D` (deleted) or `C` (consolidated). A trailer alone is a claim; the ledger is the evidence.
3. **Uncommitted work** (the usual case at ship time): ask the user for a reason per blocked move, re-run with `--pending-exception "<move> <path>: <reason>"`, and write each as a `Floor-Exception:` trailer in `/en-ship`'s own commit. Every exception lands in history, where review and `git log` can see it.

A reason the user did not give is never invented. With no reason, the ship stays stopped.

## Exit codes

`0` nothing blocked · `1` at least one blocked move · `2` could not run (stop the ship; a guard that could not run is not a pass) · `3` usage error.
