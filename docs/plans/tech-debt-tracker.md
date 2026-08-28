---
type: tech-debt-tracker
generated: false
created: 2026-08-26
updated: 2026-08-26
---

# Tech debt tracker

> Noticed-but-deferred items. Append-only; do not renumber TD-IDs.
> `/en-plan` reads this when planning new work and may cite items
> via `Resolves: TD<n>` in unit metadata.

## Open

### TD1. Peer review blocks one tool call, so a killed or truncated call reads as success

- **Source:** review of the Compound Engineering plugin's cross-agent design, during EN12 planning
- **Severity:** P1
- **Confidence:** 9/10
- **Location:** `bin/ensemble-peer-invoke:104` (`timeout_secs`), `references/build-handoff.md:106`
- **Why it matters:** `ensemble_peer_invoke` wraps the peer in `timeout ${peer_timeout_seconds:-600}` and holds a single tool call open for up to ten minutes. A harness that caps tool-call duration kills the supervising shell mid-run and the peer dies with it. Worse, the failure is not always classified: observed on 2026-08-26 during EN12's own peer review, the helper exited 0 with `{"peer":"on","reason":"default-on"}` and an output file containing only `{"type":"thread.started",...}`. The identical prompt piped straight into `codex exec --json` returned the full five-finding review. A truncated stream read as a completed peer pass, which is exactly the "a degraded peer must never read as a normal one" invariant EN11 exists to protect.
- **Suggested fix:** Adopt the detached-job lifecycle the Compound Engineering plugin uses (`skills/*/scripts/peer-job-runner.py`, 2250 lines, byte-duplicated into six skills and pinned by `tests/peer-job-runner-parity.test.ts`). Split the peer call into `start` / `status` / `wait` / `result` / `reap`, where `start` double-forks with `setsid`, prints a job id and returns immediately, and every durable fact lives on disk. Specific mechanics worth taking: liveness measured as output byte growth rather than process existence; the status file written last so it is always the final record; atomic publish via tmp plus rename; idle window and hard cap as separate limits; byte caps that classify as failed with a recorded reason; and an explicit `died-without-result` state instead of folding that into `failed`. Do not take CE's routing apparatus (route tokens, recipient sanctioning, egress disclosure, config layers) — Ensemble's single `peer_decision` object with a closed reason enum is tighter than CE's receipts, and the fix should preserve it. Two design notes: CE's duplicated assets are deliberately dependency-free (`peer-job-runner.py` imports stdlib only, `cross-model-adversarial-review.sh` sources nothing local), which is what makes byte-duplication tractable; and EN12's U5 closure walker follows bash `. "$_dir/sibling"` lines only, so a Python runner would need either the same single-file discipline or an extended walker.
- **Sequencing:** deliberately deferred until EN12 ships. Building this first means building it against the current root layout and migrating it afterwards; building it second lands it directly in the target shape as one more `shared/manifest.json` entry. Decided with the user on 2026-08-26.
- **Logged:** 2026-08-26

### TD2. Most SKILL.md bodies exceed the Codex 8000-byte injection limit

- **Source:** EN12 U12, measured during the build
- **Severity:** P1
- **Confidence:** 8/10
- **Location:** `skills/*/SKILL.md` — 15 of 17 skills
- **Why it matters:** Codex injects only the first 8000 bytes of a SKILL.md. Everything past that is invisible to that host, so a rule placed deep in a long body silently does not apply there — the skill appears to load and then behaves differently on Codex than on Claude Code, with no error. This is a cross-host correctness gap (G9), not a tidiness concern. EN12's plan named three skills from an earlier spot-check; the measured picture is worse:

  | `en-build` | 49,768 | 6.2x |
  | `en-plan` | 32,805 | 4.1x |
  | `en-setup` | 27,656 | 3.5x |
  | `en-review` | 25,527 | 3.2x |
  | `en-ship` | 21,185 | 2.6x |
  | `en-learn` | 16,213 | 2.0x |
  | `en-loop` | 15,650 | 2.0x |
  | `en-brainstorm` | 15,601 | 2.0x |
  | `en-resolve-pr` | 15,169 | 1.9x |
  | `en-debug` | 14,001 | 1.8x |
  | `en-sweep` | 13,569 | 1.7x |
  | `en-foundation` | 11,618 | 1.5x |
  | `en-guardrail` | 11,012 | 1.4x |
  | `en-qa` | 10,089 | 1.3x |
  | `en-cross-review` | 8,188 | 1.0x |

  `en-cross-review` at 8,188 bytes is only just over, so it loses a few lines; `en-build` loses roughly five sixths of its body, including the whole post-build phase, the evidence audit and the learning checkpoint.
- **Suggested fix:** Move load-bearing rules out of long bodies and into references the skill reads at a named early step, so what must be honored arrives through a read the agent performs rather than through an injection that may be truncated. The Compound Engineering plugin routes `lfg` to `references/plan-brief.md` for exactly this reason, and its parity test records the constraint explicitly. Audit per skill in body order: anything past roughly 8,000 bytes that changes behavior (a gate, an enum, a refusal condition, a safety rule) moves; narrative and examples can stay. Verify by loading each skill on Codex and checking that a rule from the tail is actually honored — byte count alone does not prove the rule survived.
- **Not caused by EN12, and not fixed by it.** EN12 makes skills self-contained; it does not shorten them. Recorded here so the gap is tracked rather than absorbed into a migration unit, where it would weaken the atomic review of the riskiest change in that plan.
- **Logged:** 2026-08-26

### TD3. `doc-lints.md` pointed at a CI template this repo never shipped

- **Source:** EN12 U7, surfaced by the single-skill-install dangling check
- **Severity:** P3
- **Confidence:** 9/10
- **Location:** `shared/references/doc-lints.md:9`
- **Why it matters:** The file recommended running the doc lints in CI "via `references/ci-templates/lint.yml`", and no such file exists anywhere in the repo or its history. Harmless while nothing resolved relative paths; once every skill carries its own copies, a link to a file that cannot exist is a dangling reference in 7 skills at once. The pointer is now replaced with a note, so the recommendation survives without promising an artifact.
- **Suggested fix:** Either ship the template (a small workflow running `shared/bin/ensemble-lint --scope docs/`, which `.github/workflows/ensemble-tests.yml` already does for this repo and which a consuming project would want too), or drop the CI recommendation. Shipping it is the better answer, since `references/templates/` already carries `github-workflow-en-sweep.yml` and `github-workflow-claude-review.yml` for exactly this purpose.
- **Logged:** 2026-08-26

### TD4. `core-beliefs-starter.md` ships as a template no skill ever uses

- **Source:** EN12 U11, full-tree consumer search
- **Severity:** P3
- **Confidence:** 8/10
- **Location:** `shared/references/core-beliefs-starter.md`
- **Why it matters:** `docs/foundation.md:1119` lists `docs/core-beliefs.md` as an optional artifact for Standard and Deep projects, and the CHANGELOG ships `core-beliefs-starter` as a cross-cutting reference. But no skill reads the starter and no skill creates the artifact, so the capability is documented, shipped and unreachable. U11 kept the file rather than deleting it: deleting would have quietly removed a documented capability, and the measured fact is that it is unwired, not that it is unwanted.
- **Suggested fix:** Decide the question the file cannot answer on its own. Either wire it up — `/en-foundation` offers `docs/core-beliefs.md` from this starter at Standard/Deep depth, the way it already seeds other optional artifacts — or drop both the starter and the foundation line, so the docs stop promising something nothing delivers. `scripts/sync-shared --check` now lists ungranted shared files as a note, so this stays visible until it is settled.
- **Logged:** 2026-08-26

## Resolved

<!-- none yet -->

### TD5. The learning `category` taxonomy has four values and no reliable way to pick one

`docs/learnings/<category>/` accepts `bugs | patterns | decisions | sources`.
Under the capture gate (`skills/en-learn/references/capture-gate.md`) almost
nothing that qualifies is a "bug" entry, because the gate rejects what a reader
can recover from the code and a fixed bug usually is. What survives is a
decision or a pattern, and that boundary is not one a writer can apply
consistently: drafting a real entry, the same content was defensible under
either.

`sources` is different in kind and does earn its own directory: it holds
ingested external material with `source_type` / `source_uri` / `fetched`, and it
is populated by a different command path.

The likely resolution is to collapse to captured-vs-ingested, but the cost is
not in the decision. **39 files** reference the category directories, including
four copies of `learnings-research`, `learn-index-format.md`, `learn-lint.md`,
`learn-cross-ref-maintenance.md`, and the enum validation plus required-field
list in `ensemble-lint`.

**Why now is the cheap moment:** this repo has zero learning entries. The
migration cost is entirely in references, not content. That gap closes the first
time the wiki is populated, so this is worth deciding before the first capture
run rather than after.

Deliberately excluded from the 2026-08-28 frontmatter reduction, which cut
`problem_type`, `component`, and `confidence` and left `category` untouched.

### TD6. `ensemble-extract-json` silently discards codex findings and returns the first event line

`ensemble-extract-json` recovers "the first balanced JSON object" from a peer
response — correct for a prose answer with an embedded envelope, wrong for a
JSONL event stream. `codex exec --json` emits one JSON object per line:

```
{"type":"thread.started","thread_id":"..."}      <- first balanced object
{"type":"item.completed","item":{"type":"agent_message","text":"{...findings...}"}}
{"type":"turn.completed",...}
```

The extractor returns line 1. Its `jq -e .` guard cannot catch this, because
`thread.started` **is** valid JSON — the guard checks that the output parses, not
that it is the right object.

`ensemble-peer-invoke`'s `_epi_normalize_out` then **overwrites the output file**
with that line, so the findings are destroyed rather than merely mis-read. The
comment there promises "on failure the file is left byte-for-byte untouched",
which holds only when extraction *fails*; here it succeeds on the wrong object.

`host-detect.md` resolves `PEER_FORMAT=--json` for a codex peer, so this is the
sanctioned path for all four peer-invoking skills, not a corner case.

**Observed 2026-08-28** while peer-reviewing EN14. The caller sees a well-formed
JSON object with no `verdict` and no `findings` — indistinguishable from a peer
that returned nothing, which is the same failure shape as the zsh `BASH_SOURCE`
bug: a broken helper returning a plausible answer instead of an error.

Likely a codex output-format change; earlier runs (EN13, 3 iterations, 11
findings) parsed fine, so this probably regressed under us rather than never
having worked.

**Resolved 2026-08-28.** The stream is unwrapped to the last `agent_message`
item's `text` before scanning, and a recovered object whose top-level `type` is a
known codex event is rejected outright rather than returned. The guard now asks
what the object *is*, not merely whether it parses — parseability could never
have caught this, since a transport frame is valid JSON.

Covered by six cases in `tests/extract-json/extract-json.test.sh`, each verified
to fail against the pre-fix extractor.

### TD7. No behavioural coverage for units whose logic is a model judgment

Ensemble's tests are shell scripts that grep specifications. That works for
structure (a file exists, two copies are byte-identical, a required field is
enforced) and is worthless for behaviour: `en-learn`'s artifact router and its
glossary writer are prose instructions executed by a model, and no shell
assertion can show that a given candidate produces the right artifact type or
that an amendment preserves unrelated glossary entries.

Raised twice by the peer during EN14 review (findings 2-3 and 2-5), correctly
both times. EN14 responds by **stating the limit** rather than claiming coverage
it does not have — its router and glossary units assert specification presence
and self-consistency, and say so.

The gap is real: a broken writer, a duplicate insertion, or a destructive rewrite
would satisfy every assertion those units make.

**Fix direction:** an eval suite that feeds fixture candidates through the skill
and asserts the emitted artifact type and path. `claude plugin eval` exists for
exactly this and would not require inventing a harness. EN14 leaves the fixture
corpus in place (`tests/fixtures/routing/`, and the worked examples in
`artifact-types.md`), so the inputs an eval suite needs are already written.

Until this lands, treat "the tests pass" on any model-behaviour unit as evidence
about the specification only.
