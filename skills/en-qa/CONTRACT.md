# `/en-qa` — contract for calling skills

What another skill may rely on. Owned by `en-qa`; a caller depends on this page,
never on `SKILL.md` internals and never on a file inside this directory.

## Accepted invocations

| Form | Caller |
|---|---|
| `/en-qa` | `en-loop`'s Morning Review, as independent verification of the loop's branch |
| `/en-qa [--url <url>] [--browser \| --system-only] [--flow <name> \| --all-flows] [--no-fix]` | a person |

This skill is model-invocable on purpose. A `disable-model-invocation: true`
flag would let only a person run it, and the callers above would have nothing
to invoke.

## Non-interactive guarantee

When a caller drives, this skill **never blocks**. The three pre-flow questions
a person would be asked, no URL found, no usable browser driver, no test
framework to bootstrap, each become a `Skip` with its reason, and the run
continues. Inside the flow window it pauses only for the five enumerated cases
in its autonomy contract, and a bug that needs judgment is reported, not
guessed. A caller may run it unattended.

## Return

A QA report. Callers branch on these fields:

| Field | Values |
|---|---|
| system checks | `lint`, `typecheck`, `tests`: pass or fail; a failure stops the run before any flow |
| per flow | `Pass` · `Fail` · `Skip — <reason>`; **every flow selected for the run has one**, none is absent |
| Phase 2 | ran, or skipped with one named reason (no URL, no driver, no frontend files changed, `--system-only`) |
| bugs | each with root cause, fix commit, regression test; those past the per-run cap listed unfixed |
| impact undetermined | changed files no flow could be attributed to |

**Branch on these exact spellings.** An absent flow is the failure this shape
exists to prevent; do not read absence as a pass.

## Authority envelope

Inherited from the caller. **Permitted:** edit source to fix a reproduced bug,
add its regression test, and commit each fix atomically as `fix(qa): …` on the
current branch; bootstrap the project's own test framework only with a person's
consent. **Excluded:** pushing, opening PRs, installing a browser stack to make a
run possible, committing a guessed fix, and any edit outside a reproduced bug.
`--no-fix` narrows the envelope to reporting.

## Cost bounds

Phase 2 runs only for changes the detector classifies as touching frontend files,
or with `--browser`, and exercises only the flows the change reaches unless
`--all-flows` is passed. Fixes per run are capped (`qa.max_bugs_to_fix_per_run`,
default 5); the rest are listed. No peer subprocess and no learning prompt.

## Recursion

Under `ENSEMBLE_PEER_REVIEW=true` this skill exits without acting. It never
invokes itself and never invokes `/en-learn`; the learning checkpoint belongs to
`/en-build`.
