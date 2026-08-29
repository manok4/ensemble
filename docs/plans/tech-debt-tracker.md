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

**Resolved 2026-08-29**, and narrower than it was written.

Part of the premise was already handled: `timeout` bounds a peer that runs too
long, exit 124 maps to `peer-failed:timeout`, and `auth` / `unknown` have their
own reasons. A peer that overruns has never read as success.

The real gap was the **host's** call dying — context exhaustion, Ctrl-C, a
truncated call. The subprocess dies with it and nothing is written, so the next
step cannot tell "the peer was never asked" from "the peer answered nothing".

Closed with a run marker rather than a job runner. A marker is written before the
call and cleared when a decision is emitted; a killed call leaves it behind, and
`ensemble_peer_orphaned_run` reports it to the next invocation with the start
time, peer command and mode. Roughly 40 lines.

**Why not the detached runner.** Polling was considered and rejected on the
evidence. `timeout N` is a ceiling, not a fixed wait — the call already returns
the moment the peer finishes, so polling buys no latency. It does not remove the
need for a deadline either; it moves where the deadline lives. The reference
implementation is 2,250 lines across 61 functions, and it brings failure modes
this path does not have today: orphaned processes, stale job directories, partial
files read as complete. That is the wrong trade for a rare failure in a path that
otherwise works. The marker is the foundation a full runner would need anyway, so
it is not throwaway if the evidence later changes.

**The 600s ceiling is left alone, deliberately.** It was never measured against
anything. Four real calls in one session ran 141s, 166s, 231s and 242s, and
prompt size did not predict duration — a 138KB prompt finished faster than a 29KB
one. Four samples on one machine is not enough to tighten a safety ceiling, so
every decision now reports `elapsed_s` and the next tuning can be made on data
rather than on this note.

The clear lives inside `_epi_decision` rather than at each exit path, because a
path added later would otherwise leave a false orphan — and a false orphan is
worse than none: it reports an interruption that never happened.

Guarded by `tests/lint/peer-run-marker.test.sh`, 17 assertions, five controls
verified.

- **Source:** review of the Compound Engineering plugin's cross-agent design, during EN12 planning
- **Severity:** P1
- **Confidence:** 9/10
- **Location:** `bin/ensemble-peer-invoke:104` (`timeout_secs`), `references/build-handoff.md:106`
- **Why it matters:** `ensemble_peer_invoke` wraps the peer in `timeout ${peer_timeout_seconds:-600}` and holds a single tool call open for up to ten minutes. A harness that caps tool-call duration kills the supervising shell mid-run and the peer dies with it. Worse, the failure is not always classified: observed on 2026-08-26 during EN12's own peer review, the helper exited 0 with `{"peer":"on","reason":"default-on"}` and an output file containing only `{"type":"thread.started",...}`. The identical prompt piped straight into `codex exec --json` returned the full five-finding review. A truncated stream read as a completed peer pass, which is exactly the "a degraded peer must never read as a normal one" invariant EN11 exists to protect.
- **Suggested fix:** Adopt the detached-job lifecycle the Compound Engineering plugin uses (`skills/*/scripts/peer-job-runner.py`, 2250 lines, byte-duplicated into six skills and pinned by `tests/peer-job-runner-parity.test.ts`). Split the peer call into `start` / `status` / `wait` / `result` / `reap`, where `start` double-forks with `setsid`, prints a job id and returns immediately, and every durable fact lives on disk. Specific mechanics worth taking: liveness measured as output byte growth rather than process existence; the status file written last so it is always the final record; atomic publish via tmp plus rename; idle window and hard cap as separate limits; byte caps that classify as failed with a recorded reason; and an explicit `died-without-result` state instead of folding that into `failed`. Do not take CE's routing apparatus (route tokens, recipient sanctioning, egress disclosure, config layers) — Ensemble's single `peer_decision` object with a closed reason enum is tighter than CE's receipts, and the fix should preserve it. Two design notes: CE's duplicated assets are deliberately dependency-free (`peer-job-runner.py` imports stdlib only, `cross-model-adversarial-review.sh` sources nothing local), which is what makes byte-duplication tractable; and EN12's U5 closure walker follows bash `. "$_dir/sibling"` lines only, so a Python runner would need either the same single-file discipline or an extended walker.
- **Sequencing:** deliberately deferred until EN12 ships. Building this first means building it against the current root layout and migrating it afterwards; building it second lands it directly in the target shape as one more `shared/manifest.json` entry. Decided with the user on 2026-08-26.
- **Logged:** 2026-08-26

### TD2. Skill descriptions exceed Codex's initial-list context budget

- **Source:** EN12 U12 (original, wrong premise); corrected 2026-08-29 against OpenAI's published Codex documentation
- **Severity:** P2
- **Confidence:** 9/10 — documented behaviour plus a runtime message observed from `codex exec`
- **Location:** the `description:` frontmatter of all 17 `skills/*/SKILL.md`

**This entry previously claimed the wrong thing.** It said Codex injects only the
first 8,000 bytes of a `SKILL.md`, so rules deep in a long body silently do not
apply on that host, and it listed 15 skills as "over" by up to 6.2x. That premise
is false and the remediation it implied — restructuring five large skills to move
content out of their bodies — would have been wasted work.

Codex uses **progressive disclosure**. Per
[Build skills](https://learn.chatgpt.com/docs/build-skills.md): "ChatGPT and Codex
start with each skill's name and description, then load the full `SKILL.md`
instructions when they decide to use that skill." And explicitly: "This budget
applies only to the initial skills list. When Codex selects a skill, it still
reads the full SKILL.md instructions for that skill."

**Skill bodies are not truncated.** `en-build` at 51KB loads in full when selected.

**What the 8,000 actually bounds** is the initial skills list — the name and
description of every installed skill together: "at most 2% of the model's context
window, or 8,000 characters when the context window is unknown." Under pressure
Codex shortens descriptions first, and may omit whole skills from the list with a
warning.

**The real problem, measured 2026-08-29:** the 17 descriptions total **9,705
characters against an 8,000 budget — 1.2x over**. `en-learn`'s is the largest at
1,135. So descriptions get shortened, and a shortened description may fail to
trigger its skill. The failure is discoverability, not truncated instructions.

Confirmed empirically: `codex exec` emitted this during EN14's peer review —
"Skill descriptions were shortened to fit the 2% skills context budget. Codex can
still see every skill, but some descriptions are shorter."

**Fix:** bring the combined descriptions under 8,000 characters, front-loading
trigger words so a shortened description still matches. The docs advise exactly
this: "Front-load the key use case and trigger words so a host can still match
the skill if descriptions are shortened." Bodies need no restructuring.

**How the error survived.** The original entry recorded confidence 8/10 and said
"measured during the build" — the byte counts were measured, the mechanism was
assumed. It even flagged its own gap: "byte count alone does not prove the rule
survived." Nobody ran that check for three days, and the claim was repeated as
fact in the interim. A number measured precisely against a mechanism nobody
verified reads as evidence.

- **Logged:** 2026-08-26. **Corrected:** 2026-08-29.

### TD3. `doc-lints.md` pointed at a CI template this repo never shipped

**Resolved 2026-08-29.** The workflow existed only as YAML inline in the doc, so
the recommendation could be read but not acted on. Extracted to
`references/templates/github-workflow-ensemble-lint.yml` and offered by
`/en-setup` as an opt-in, separate from the sweep: a PR check that reports is a
narrower thing than a scheduled job that opens pull requests.

The prose was also wrong in a second way. It said "this repo ships no lint CI
template", but Ensemble's own CI has been running the lint from its test workflow
all along — so the line understated what already worked while overstating what
was missing.

Reworded across all 7 carriers without naming a template path, because a relative
path in a carried file resolves against whichever skill carries it, and only
`en-setup` installs workflows. Naming it would have forced six pointless copies.

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

**Resolved 2026-08-28 by EN14**, which replaced the taxonomy rather than
collapsing it. `docs/learnings/<category>/` accepted `bugs | patterns | decisions
| sources`; captured knowledge is now three artifact types that differ in shape,
lifecycle, and write path — a term in `docs/CONTEXT.md`, a decision in
`docs/decisions/`, a solution flat in `docs/learnings/`, with ingested sources
keeping their own directory.

The original diagnosis held: under the capture gate almost nothing qualifying is
a "bug" entry, because the gate rejects what a reader recovers from the code and
a fixed bug usually is. What survived was a decision or a pattern, and that
boundary was not one a writer could apply twice the same way.

**Correcting the cost analysis this entry originally carried.** It claimed the
migration was cheap only while the wiki was empty. Half of that was wrong, and it
was the half the decision rested on. The two costs behave differently: the ~39
reference files are **time-invariant** and cost the same whenever the work is
done, while the entries are the cheap half and stay cheap — `git mv` plus a
frontmatter line, with `learn-lint`'s `broken-links` check watching the result.
Urgency was inferred from the half that was never expensive.

What actually settled it was not cost. Collapsing to captured-vs-ingested would
have kept one artifact shape and left the two highest-value gaps unaddressed:
nothing captured domain vocabulary, and decisions recorded what was chosen
without stating the rules that followed.

Migration for repos already holding entries is EN14's U13.

### TD6. `ensemble-extract-json` returned a transport frame instead of the reviewer payload

**Resolved 2026-08-28**, recorded because the failure shape is worth keeping.

`ensemble-extract-json` recovers "the first balanced JSON object" — correct for a
prose answer with an embedded envelope, wrong for a JSONL event stream.
`codex exec --json` emits one object per line and the first is
`{"type":"thread.started",...}`, so that is what came back.

The `jq -e .` guard could not catch it. The guard asks whether the recovered text
*parses*, and a transport frame parses perfectly. `ensemble-peer-invoke`'s
`_epi_normalize_out` then overwrote the response file with it, so findings were
destroyed rather than merely mis-read. `host-detect.md` resolves
`PEER_FORMAT=--json` for a codex peer, so this was the sanctioned path for all
five carriers.

Observed while peer-reviewing EN14: the extractor reported an empty verdict, and
reading the raw stream showed six findings sitting in an `agent_message` item.
Earlier runs parsed fine, so this regressed under a codex output-format change
rather than never having worked.

**Fix:** unwrap the stream to the last `agent_message` text before scanning, and
reject an object whose top-level `type` is a known codex event. The second half
is the durable part — a guard that only checks well-formedness cannot tell the
right object from the wrong one, which is why a valid-JSON frame survived a
validity check. Six cases in `tests/extract-json/extract-json.test.sh`, each
verified to fail against the pre-fix extractor.

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

### TD8. The phase-invariant lint compares risk only, so it cannot see a category-induced promotion

**Resolved 2026-08-29.** The lint now classifies each unit into a phase with the
same rule `/en-build` uses — risk as the primary axis, with `category:` carving
out the one case where `medium` plus a migration-shaped category lands in P3 — and
compares phases across dependency edges rather than risk.

Golden fixture `plan-active/invalid-category-phase-promotion.md`: every unit
`risk: medium`, so a risk-only comparison sees a flat plan, while U1 (P2) depends
on U2 (P3, `category: migration`). Verified to pass under phase comparison and
fail under the old risk-only one.

This was not hypothetical. EN14 linted clean through two peer iterations with
every unit at `medium`, then `/en-build` rejected it at preflight for exactly this
edge; the workaround is still visible in the shipped plan as U13's category note.

`ensemble-lint`'s `phase-invariant.dependency-vs-risk` rule builds a U-ID → risk
map and compares risk across every dependency edge. `/en-build` classifies phases
from **risk and category**: `risk: medium` plus `category: migration | backfill |
schema-evolution` lands in P3 while plain `risk: medium` lands in P2.

So a unit can be promoted across a phase boundary by its *category* while its
*risk* is unchanged, and the lint sees nothing. Every unit can be `medium`, the
lint passes, and `/en-build` still refuses the plan at preflight.

**Observed 2026-08-28** on EN14. All 13 units were `medium` or lower and the plan
linted clean through two peer-review iterations. `/en-build` then rejected it: U13
was `medium` + `migration` (P3) and U10 was `medium` + `other` (P2), with U10
depending on U13. Resolved by correcting U13's category, but the lint that exists
to catch this class had already passed the plan twice.

The rule's own comment says the check exists so a plan does not "force /en-build
to either reject the plan or violate phase purity" — which is precisely what
happened, because the rule asks a narrower question than the one it is standing
in for.

**Fix direction:** replicate `/en-build`'s full classifier in the rule — phase
from risk *and* category — and compare phases rather than risks. Rename to
`phase-invariant.dependency-vs-phase`, since risk is no longer what it compares.
Needs a negative control: a plan whose units are all `medium`, one of them
`category: migration` with a non-migration dependent, must go red.

### TD9. Five skills dispatch seven reviewer agents the repo no longer defines

**Resolved 2026-08-29.** One parameterized `dimension-reviewer` replaced the
seven: the dimension, its focus, and any matched heuristics arrive in the prompt,
so there is one definition rather than seven near-identical ones. This follows
EN13's own measurement — only 18-19% of each retired agent was unique — rather
than undoing it.

The audit widened the fault. TD9 described five skills and seven agents; the real
scope was **twelve** unbacked dispatches, including `en-brainstorm` naming
`learnings-research` and eight skills naming `repo-research` without carrying
either. A skill installs alone and cannot reach another skill's directory, so
dispatching an agent means carrying it. Carrying the agents then pulled a
transitive dependency (`references/research-dispatch.md`) into five more skills —
declaration closure, applied.

Guarded by `tests/lint/agent-dispatch-resolves.test.sh`: every dispatched
`subagent_type` has a definition, every skill carries what it dispatches, every
carried agent is declared, and the retired seven cannot return by name. Three
controls verified.

EN13 U11 deleted seven reviewer agent definitions (correctness, testing,
maintainability, standards, security, performance, migrations), absorbing their
scopes into the per-skill peer briefs. Its commit message says "en-review still
names every persona" — which was the intent: the personas survive as **review
dimensions** in the briefs, not as spawnable agents.

But `references/persona-dispatch.md`, carried by **five** skills — `en-review`,
`en-cross-review`, `en-build`, `en-plan`, `en-foundation` — still instructs:

```
Agent({ subagent_type: "correctness-reviewer", ... })
```

Those subagent types are not defined anywhere in the repo. The dispatch resolves
today only because the operator's install predates EN12 and still carries the old
agent files; a fresh install from `main` would fail every one of them.

**Observed 2026-08-28** while reconciling `docs/foundation.md`'s agent catalog
against the filesystem: the catalog listed 11 agents, the repo defines 4, and the
seven-row gap turned out to be live dispatch rather than stale documentation.

**Fix direction:** decide what the personas are now. If they are review dimensions
the host applies inline, `persona-dispatch.md` should stop naming `subagent_type`
and describe the dimensions instead. If they are still meant to be spawned, the
definitions have to come back. Either way the five carriers move together, and a
test should assert that every `subagent_type` a skill names resolves to an agent
the repo defines — the gap existed for a full release because nothing checked.
