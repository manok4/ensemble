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
still apply. **Every clever invalidation rule is a way to ship untested code**,
and the cost of being wrong is asymmetric: a needless re-run costs minutes, a
wrongly-skipped run costs a broken main branch. When anything is unclear the
command exits non-zero and the caller runs the checks.

The **fingerprint** covers the committed tree, every tracked modification staged
or unstaged, and the *content* of untracked non-ignored files. That last part
matters most: a brand-new source file is exactly where a stale receipt would be
most wrong, because the tests that would cover it do not exist in the committed
tree at all. Ignored files are excluded, or every build artifact would invalidate
the receipt it was meant to preserve.

The **TTL** is the one input not derivable from the tree. A toolchain can move
under an unchanged tree — someone upgrades a runtime, a service restarts — and no
fingerprint can see that. Age is the proxy. Default 120 minutes, overridable with
`--ttl <minutes>` or `ENSEMBLE_RECEIPT_TTL_MINUTES`.

## Who writes and who reads

- **`/en-build`** writes it after its single full-suite run passes.
- **`/en-ship`** reads in preflight, and skips only what a valid receipt covers.
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
