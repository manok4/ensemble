# Verification receipt — reusing a check another layer already ran

On a measured PR, four layers verified the same tree and none could see the
others: `/en-build` ran the full suite, `/en-ship` ran lint and targeted tests,
the project's pre-push hook ran 439 more *seconds later on an identical tree*,
and CI ran the authoritative suite. Each layer is justified. The waste is that
none of them could tell another had already answered the question.

A receipt is how one layer tells the next what it proved.

## Where it lives

`$(git rev-parse --git-dir)/ensemble/receipt.json` — inside `.git`, so it is per
clone, already ignored, never committed, and gone when the checkout is. A receipt
cannot outlive the tree it describes or travel to a machine it does not describe.

## What makes one valid

Validity is a **conjunction**. All of these must hold:

| Clause | Refusal reason |
|---|---|
| The working tree is byte-identical to the one checked | `fingerprint-mismatch` |
| The recorded base ref still points at the same commit | `base-moved` |
| Every recorded dependency file still hashes the same | `dependency-changed` |
| The receipt belongs to this checkout | `wrong-repo` |
| It is younger than the TTL | `expired` |
| It records the checks the caller asked for | `check-not-recorded` |
| It parses, and its schema is known | `malformed` |

There is no partial credit and no reasoning about which subset of checks might
still apply. Per-suite check names are not partial credit: a caller that asks
for `db` gets `db` or `check-not-recorded`, never an inference from `unit`. **Every clever invalidation rule is a way to ship untested code**,
and the cost of being wrong is asymmetric: a needless re-run costs minutes, a
wrongly-skipped run costs a broken main branch. When anything is unclear the
command exits non-zero and the caller runs the checks.

The **fingerprint** is the tree a commit of everything would produce: tracked
files as they sit on disk, staged or not, plus the *content* of untracked
non-ignored files. It is built in a throwaway copy of the index and named by
`git write-tree`, so it hashes content, not commit state: committing exactly the
checked content leaves the receipt valid. The first version hashed
`HEAD^{tree}` plus `git diff HEAD`, both of which move on commit, so the receipt
`/en-build` wrote before its final commit was refused by `/en-ship` on nearly
every ship. Untracked content matters most: a brand-new source file is exactly
where a stale receipt would be most wrong, because the tests that would cover it
do not exist in the committed tree at all. Ignored files are excluded, or every
build artifact would invalidate the receipt it was meant to preserve. Each
checked-out submodule is fingerprinted the same way and hashed in with the
parent tree, which records a submodule only as its HEAD commit and so missed
edits inside one.

The **TTL** is the one input not derivable from the tree. A toolchain can move
under an unchanged tree — someone upgrades a runtime, a service restarts — and no
fingerprint can see that. Age is the proxy. Default 24 hours (1440 minutes),
overridable with `--ttl <minutes>` or `ENSEMBLE_RECEIPT_TTL_MINUTES`. It was 120
minutes, which expired before the usual gap between a build and its ship; the
content, base and lockfile clauses already refuse on everything the tree can
show.

## Writes accumulate; a tree change resets

Layers prove different things about the same tree, so a write **merges** into an
existing receipt when the fingerprint and repo match. Without that, the second
writer erased the first's evidence: `/en-build` proved the full suite, `/en-ship`
wrote its own receipt seconds later on the identical tree, and the project's
pre-push hook then asked for `full_suite`, got `check-not-recorded`, and re-ran
the suite the build had just paid for.

When the fingerprint differs the prior checks describe code that is no longer
here, so the receipt is **replaced outright**. That fence is what makes merging
safe, and it is the half to preserve in any future change.

The merged receipt keeps the **oldest** `written_at` and names every writer
(`en-build+en-ship`). Refreshing the clock on each write would let a one-second
lint check renew an hour-old suite result indefinitely, which is the TTL defeated
by bookkeeping.

**Never record a check that was skipped.** A receipt claiming a check that never
ran is worse than no receipt, because the next layer skips on it too.

## Red records: the failing half of a fix

A fix's test has to fail before the fix and pass after. The passing half is an ordinary receipt check. The failing half happened on the pre-fix tree, which the receipt's fingerprint does not describe, so it lives beside it in `red-tests.json`.

- **`red --test <path> --since <sha> -- <cmd...>`** runs the command itself and records only a real failure. The command must name the test, so `-- false` cannot stand in. `--since` is the commit the fix starts from: `HEAD`, or an ancestor of it when the fix committed a standalone part first. Exit 126 or 127 means the command never ran the test and records nothing (`red-test-not-run`). A passing test records nothing (`red-test-passed`).
- **`verify --requires red_test --since <sha>`** accepts a record only when all of these hold: it is on this branch, it names this fix's start commit, its test is in this fix's diff, and the test's content is unchanged since it ran. Otherwise it refuses with `red-test-missing`, `red-test-stale` (a record from a different start commit) or `red-test-changed`.
- **What it proves, and what it does not.** It proves a command naming the test exited with a failure before the fix. It refuses the forms that name a test without running it (`false`, `true`, a shell `-c` wrapper), but it cannot prove the failure was the bug rather than, say, a syntax error. That is still `/en-fix`'s "fails for the right reason" check, in its test-first change step. The recorded `cmd` is kept for review to read.
- **Fails closed.** A red file or record that cannot be read refuses as `malformed`, never as an empty verdict that reads as not required.
- **When a review edits the test after its red run,** verify refuses with `red-test-changed`, and the fix is already in, so a new red run would pass. Re-record against the start commit. The fix is usually committed by then, so `git stash` finds nothing to set aside; check the sources out from the start commit instead, keeping the edited test: `git checkout <since> -- <source files>`, run `red` again, then `git checkout HEAD -- <source files>`. Never edit the test back to match the old record.
- **Paths are recorded from the repo root.** A test named `./t.sh` or run from a subdirectory is stored in the form `git diff --name-only` prints.
- **One record per test path.** A later red run replaces the earlier one, so a second fix on the same branch never inherits the first fix's evidence.

`/en-fix` writes the record in its test-first change step and requires it at its receipt gate, except for a behaviour-preserving change, where no test can fail first.

## Who writes and who reads

- **`/en-build`** writes it after its single full-suite run passes, recording
  `full_suite` plus one check per named suite in `AGENTS.md` (`unit`, `db`,
  `e2e` for a project that declares those commands).
- **`/en-review`** reads before its post-review check and skips it when the
  tree is already proved, which is only possible when it applied nothing. When
  the check runs and passes on the bare branch diff it writes `lint`,
  `typecheck` and `targeted_tests`, so a standalone review hands `/en-ship`
  something it can honour.
- **`/en-ship`** reads in preflight, and skips only what a valid receipt covers:
  `full_suite` first, then `targeted_tests`, which is the set it would run itself.
  When it skips, it writes nothing: there is nothing new to record, and the
  stronger evidence stays where the layer that earned it put it.
- **A project's pre-push hook** may read it, to avoid repeating what `/en-ship`
  just ran seconds earlier on the identical tree.
- **CI never reads one.** It is the independent authority, and a receipt is a
  local optimisation worthless to anyone but this checkout.

## Using it from a pre-push hook

**Ensemble does not install a hook, and never edits one.** A hook is where a
project encodes its own policy, and silently rewriting that is help nobody asked
for. `/en-ship` also never bypasses hooks — so the receipt is offered to your
hook, and your hook decides.

Add this to `.git/hooks/pre-push` yourself if you want it:

```bash
# Skip the local suite when a verification receipt already covers this exact tree.
RECEIPT=path/to/skills/en-ship/scripts/ensemble-verification-receipt
if bash "$RECEIPT" verify --requires full_suite,lint >/dev/null 2>&1; then
  echo "pre-push: verification receipt covers this tree; skipping local suite"
else
  echo "pre-push: $(bash "$RECEIPT" verify 2>&1 | head -1) — running the suite"
  ./run-tests || exit 1
fi
```

Two properties worth keeping if you adapt it. Print the refusal reason rather
than a bare "no receipt": a hook that re-runs silently teaches nobody why. And
keep the failure direction — an unusable receipt means *run the checks*, never
skip them.

## Reading a receipt by hand

```bash
bash scripts/ensemble-verification-receipt show
bash scripts/ensemble-verification-receipt verify --json
```

`verify --json` emits `{valid, reason, checks, age_seconds, written_by}`. Exit
codes are `0` valid, `1` invalid (with a reason), `2` no receipt, `3` usage error.
`2` is kept distinct from `1` so a caller can tell "nobody has checked this tree"
from "somebody did, and it no longer holds".
