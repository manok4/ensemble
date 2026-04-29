# Ensemble tests

Hermetic test suite for Ensemble's bash tooling and doc-shape contracts. No live LLM calls; everything runs locally in a few seconds.

## Running

```bash
./tests/run.sh             # all tests
./tests/run.sh -k frontmatter   # only frontmatter
./tests/run.sh -v          # show every assertion line
```

Exits 0 if all pass, non-zero otherwise.

## Layout

```
tests/
├── lib/
│   ├── assert.sh           # tiny assertion library (assert_eq, assert_contains, ...)
│   └── mock-peer.sh        # PATH-shadow installer for mocked claude/codex CLIs
├── run.sh                  # discovers + runs every *.test.sh
│
├── golden/frontmatter/     # known-good and known-bad frontmatter fixtures per artifact type
│   ├── foundation/         # valid + invalid-{status,depth,date}
│   ├── architecture/       # valid + invalid-status
│   ├── plan-active/        # valid + invalid-{missing-required,status-mismatch}
│   ├── plan-completed/     # valid
│   ├── learning/           # valid + invalid-{category,confidence}
│   ├── design/             # valid + invalid-status
│   ├── agents-md/          # valid
│   ├── claude-md/          # valid + invalid-no-cross-ref
│   └── frontmatter.test.sh # runs every fixture against bin/ensemble-lint
│
├── lint/                   # one-fixture-per-rule for rules not already covered above
│   └── lint-rules.test.sh  # path.absolute, cross-link.broken-{r,u,fr,td},
│                           # id-stability.fr-{collision,format}, index-coverage.{plan,learning}-missing,
│                           # generated.missing-marker, freshness.architecture-{30,90}, length budgets
│
├── host-detect/
│   └── host-detect.test.sh # mocks env vars + PATH; asserts HOST/PEER/PEER_MODE/PEER_CMD across
│                           # all combinations (cross-agent, single-agent fallback, override=off, etc).
│                           # Includes shell-escape round-trip test (regression for the Codex P1 fix).
│
├── cross-review/
│   ├── fixtures/           # record/replay JSON for the host's cross-review parser
│   │   ├── clean-approve.json
│   │   ├── revise-with-findings.json
│   │   ├── reject.json
│   │   ├── single-agent-fallback.json
│   │   ├── malformed-json.json
│   │   ├── timeout.json
│   │   └── d30-violation.json
│   └── cross-review.test.sh # validates fixture envelopes + schema conformance
│
├── en-setup/
│   ├── sample-repos/       # fixture repos representing each detection state
│   │   ├── state-1-greenfield/
│   │   ├── state-2a-no-maps/
│   │   ├── state-2b-claude-only/
│   │   ├── state-2c-agents-only/
│   │   ├── state-2d-both-maps/
│   │   ├── state-3-fully-set-up/
│   │   └── state-3-partial/
│   └── state-detection.test.sh # implements the heuristic from references/setup-state-detection.md
│                               # in bash; asserts each fixture maps to the expected state + sub-variant.
│
├── en-garden/
│   └── doc-only-enforcement/
│       └── doc-only.test.sh    # adversarial: stages doc paths, source files, configs, tests;
│                               # asserts bin/ensemble-doc-only-check accepts the allowlist
│                               # and rejects everything else (P0 regression test).
│
└── stable-ids/
    └── stable-ids.test.sh      # adding a unit doesn't renumber; FR collision caught;
                                # FR format enforced; renumbered R-IDs surface broken-r.
```

## What's covered

| Foundation §20 category | Status |
|---|---|
| Frontmatter golden tests | ✅ 18 fixtures |
| Doc-lint rule tests | ✅ 13 rules (one fixture per rule, plus regression for backtick-aware path detection) |
| Host-detection tests | ✅ 25 assertions across 7 scenarios |
| Cross-review parsing tests | ✅ 7 fixtures + 21 assertions |
| `en-setup` state-detection tests | ✅ 7 sample repos + 20 assertions |
| `en-garden` doc-only enforcement | ✅ 16 adversarial assertions |
| Stable-ID invariants | ✅ 6 scenarios (U-ID append, FR collision, FR format, broken-U, broken-R) |
| `en-garden` dry-run batching | ⏭ Deferred — needs live CLI to exercise the skill |
| Auto-merge security | ⏭ Deferred — workflow-level integration test, not unit-testable |
| Cross-ref reciprocity | ⏭ Deferred — needs `/en-learn` execution |

The deferred items live as fixtures or skill specs that an integration test (with a real CLI) can exercise; we'll add executable harnesses for them once a per-skill harness exists.

## Adding a test

1. Create `tests/<category>/<name>.test.sh`.
2. Source `tests/lib/assert.sh` (sets `TEST_NAME`, exposes `pass`, `fail`, `assert_eq`, etc.).
3. Run your assertions; call `report` at the end (it exits with the right code).
4. `chmod +x` the file.
5. The runner picks it up automatically.

Skeleton:

```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="my new test"

# ... your assertions ...
assert_eq "expected" "$actual" "label"

report
```

## Adding a frontmatter fixture

1. Drop the `.md` file into `tests/golden/frontmatter/<artifact-type>/`.
2. Add an entry to the `fixtures=()` array in `frontmatter.test.sh`:
   - `<fixture-relative-path>|<staged-path-in-tempdir>|<expected-rule-or-empty>`
3. Empty expected-rule means "should lint clean"; otherwise the lint must produce at least one P1 finding mentioning the rule.

## Adding a lint rule fixture

Add a new section in `tests/lint/lint-rules.test.sh` following the pattern:

```bash
setup_minimum
cat > "$TMP/<staged-path>" <<EOF
... fixture content ...
EOF
assert_rule_fires "<rule-name>" "<human description>"
```

## Running under CI

`.github/workflows/ensemble-tests.yml` runs the full suite on every push and PR. Failures block merge.

## Mock-peer harness

`tests/lib/mock-peer.sh` installs PATH-shadow `claude` and `codex` shims that replay JSON fixtures from `tests/cross-review/fixtures/`. Used by future skill-execution tests; currently only exercised by `cross-review.test.sh`'s harness sanity check.

Usage:

```bash
. tests/lib/mock-peer.sh
SHIM_DIR=$(mktemp -d)
mock_peer_install "$SHIM_DIR" "tests/cross-review/fixtures/clean-approve.json"
PATH="$SHIM_DIR:$PATH" claude -p "review this"
mock_peer_uninstall "$SHIM_DIR"
```

## Why bash (not bun/node)?

The system under test is bash scripts (`bin/ensemble-*`, `setup`, `scripts/*`) plus markdown SKILL.md specs. Bash tests sit one abstraction layer below the system; no language-bridge overhead. Foundation §20.5 mentions `bun test` for the future when the lint runner ports to TypeScript; for now, bash assertions and `jq` cover everything we need.
