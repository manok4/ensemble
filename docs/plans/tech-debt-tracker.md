---
type: tech-debt-tracker
generated: false
created: 2026-08-26
updated: 2026-09-08
---

# Tech debt tracker

> Noticed-but-deferred items. Append-only; do not renumber TD-IDs.
> `/en-plan` reads this when planning new work and may cite items
> via `Resolves: TD<n>` in unit metadata.

## Open

### TD12. Remove the one-release `review_peer_*` legacy read and the `--legacy` call sites

Filed 2026-09-08 from the EN16 branch review (migrations dimension): the policy promises the old spellings are read "for one release and then dropped", and nothing enforced either end.

`ensemble-config-get --legacy <old-key>...` (all eight copies) reads two retired generations as fallbacks: `review_peer_model_alias` and `peer_model_alias` (now `peer_model_claude`), `review_peer_codex_model` and `peer_codex_model` (now `peer_model_codex`), `review_peer_effort_override` and `peer_effort_override` (now `peer_effort_claude` / `peer_effort_codex`), and `review_host_model_alias` (now `agent_model_claude_ceiling`, read inside `ensemble-agent-model`), per D104. The call sites carrying `--legacy` are `skills/en-review/SKILL.md` step 2b, `skills/en-plan/SKILL.md` step 16 and `skills/en-foundation/SKILL.md` step 11 (`each with --legacy review_<key>`). `setup` now logs each legacy key it finds after the config merge, so operators are nudged on the path they already run.

- **Source:** en-review --cross on EN16 (migrations persona), applied as a filed item
- **Severity:** P2
- **Confidence:** 8/10
- **Location:** the three call sites above; `skills/en-review/references/peer-model-policy.md` (b), "Deprecated spellings"
- **Why it matters:** an unremoved fallback makes the second spelling permanent; a removal nobody was reminded of silently drops an operator's setting, and the reader is fail-soft so the loss surfaces as a peer running on a different model.
- **Suggested fix:** in the release after D104 ships, delete every `--legacy` clause at the three call sites and in `ensemble-agent-model`, the policy's deprecation paragraph and `setup`'s retired-key notice, keep `--legacy` in the reader (it is generic), and add a lint assertion that none of the retired spellings remains in skills/ or setup.
- **Logged:** 2026-09-08

**Re-checked 2026-09-10: still applies, and still not due.**

The trigger is "the release after D104 ships". **No release has ever shipped** —
`package.json` is at `0.1.0`, there are no git tags, and the CHANGELOG has only
an `[Unreleased]` section. Removing the fallbacks now would do the exact harm the
item warns about: an operator whose `~/.ensemble/config.json` still holds an old
spelling would silently get a peer on a different model, with no release note to
connect it to.

What is already done, verified today: `setup` logs every deprecated key it finds
after the config merge, names its replacement, and says the old name stops being
read next release. The operator nudge is on the path they already run.

What is left is mechanical and belongs to the release, not to today: delete the
`--legacy` clauses at the three call sites (`en-review` step 2b, `en-plan` step
16, `en-foundation` step 11) and in `ensemble-agent-model`, drop the policy's
deprecation paragraph and `setup`'s notice, keep `--legacy` in the reader since
it is generic, and add the assertion that no retired spelling remains.

**Release checklist entry**, so this is an action rather than a memory:

> Before tagging the first release after D104: run `grep -rn -- '--legacy' skills/ setup`.
> Every hit is a deprecated-spelling fallback that this release drops. Remove
> them, then add the lint that keeps them gone.


## Resolved

### TD1. ~~Peer review blocks one tool call, so a killed or truncated call reads as success~~ RESOLVED 2026-08-29

*Filed under `## Open` by mistake; the body said Resolved from the day it was fixed. Moved 2026-09-10 after re-verifying: `tests/lint/peer-run-marker.test.sh` passes 17/17 and `ensemble_peer_orphaned_run` is present in the helper.*

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

### TD2. ~~Skill descriptions exceed Codex's initial-list context budget~~ NO LONGER APPLIES 2026-09-10

**Re-measured today: 4,657 characters of name + description across 16 skills, against the 8,000 budget. 0.58x, not 1.2x.**

TD2 measured 9,705 across 17 on 2026-08-29. Nothing was done to the descriptions
deliberately; a skill was retired and the rest were tightened during the per-skill
trims, and the number came down as a side effect. Which is the problem with
closing it here and walking away: it drifted down unwatched and can drift back up
the same way, and the failure is silent on the host that has it. Codex reports
"descriptions were shortened", never "en-plan will not trigger".

So it closes with a guard rather than a note. `tests/lint/skill-description-budget.test.sh`
fails over 8,000 and warns at 6,400, so the description that would cross the
budget fails in this repo instead of degrading discoverability on someone's
machine. The original analysis below is kept because its correction is the
useful part.

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

### TD3. ~~`doc-lints.md` pointed at a CI template this repo never shipped~~ RESOLVED 2026-08-29

*Filed under `## Open` by mistake; the body said Resolved. Moved 2026-09-10 after verifying `references/templates/github-workflow-ensemble-lint.yml` exists and `/en-setup`'s step 1a round offers it.*

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

### TD4. ~~`core-beliefs-starter.md` ships as a template no skill ever uses~~ RESOLVED 2026-09-10

**Settled the way the item asked: dropped, not wired.**

Half of it had already happened without being recorded. `core-beliefs-starter.md`
does not exist anywhere in the tree, and no skill mentions `core-beliefs` at all.
But `docs/foundation.md` still promised the artifact in four places, including
Q11's answer describing a starter path that had ceased to exist, so the docs went
on promising something nothing delivered. That is the exact failure the item
described, surviving the deletion of the file it was about.

Removed from the directory tree, the optional-artifacts list and the
lint-exemption list. Q11's answer is struck through rather than deleted, because
an answer that quietly disappears reads as one nobody asked.

- **Source:** EN12 U11, full-tree consumer search
- **Severity:** P3
- **Confidence:** 8/10
- **Location:** `shared/references/core-beliefs-starter.md`
- **Why it matters:** `docs/foundation.md:1119` lists `docs/core-beliefs.md` as an optional artifact for Standard and Deep projects, and the CHANGELOG ships `core-beliefs-starter` as a cross-cutting reference. But no skill reads the starter and no skill creates the artifact, so the capability is documented, shipped and unreachable. U11 kept the file rather than deleting it: deleting would have quietly removed a documented capability, and the measured fact is that it is unwired, not that it is unwanted.
- **Suggested fix:** Decide the question the file cannot answer on its own. Either wire it up — `/en-foundation` offers `docs/core-beliefs.md` from this starter at Standard/Deep depth, the way it already seeds other optional artifacts — or drop both the starter and the foundation line, so the docs stop promising something nothing delivers. `scripts/sync-shared --check` now lists ungranted shared files as a note, so this stays visible until it is settled.
- **Logged:** 2026-08-26

### TD11. ~~Four skills name their own files by repo-rooted path~~ RESOLVED 2026-09-10

**The four named skills were already clean, and the guard the item asked for
already existed. What was left was one instance three days old, and a hole in
the guard that let it through.**

Checked every skill for `skills/<self>/(scripts|references|agents)/`: en-sweep,
en-guardrail, en-build and en-brainstorm had none. `tests/lint/skill-self-path.test.sh`
was written 2026-09-03 and covers the self-reference case, including a deliberate
allowance for `path/to/` as an illustrative prefix and for an env-anchored
install path. I briefly "fixed" one of those allowed lines before reading the
guard that permits it, and reverted.

The live instance was mine. `references/script-invocation.md` line 42 named
`skills/en-ship/scripts/<name>` in an example, in a file carried by **13 skills**,
so twelve copies pointed a reader at another skill's directory. Added 2026-09-09
by the change that permitted a plain absolute path, which is this item's defect
reintroduced in the file documenting the rule against it.

**Why nothing caught it, which is the part worth keeping.** The cross-skill
clause in `skill-helper-anchor.test.sh` matched
`skills/en-[a-z-]+/(scripts|…)/[A-Za-z0-9._/-]+` — and the character class has no
`<`. So `skills/en-ship/scripts/<name>` matched the prefix, needed one more
character it could not find, and did not register. **A path ending in a
placeholder was invisible to the guard**, which is the shape an example takes
almost by definition. The class now includes `<>`, and reintroducing yesterday's
line turns the clause red.

- **Source:** the cross-skill guard fix, 2026-08-31
- **Severity:** P2
- **Confidence:** 9/10 — the paths are literal and the install layout is known
- **Location:** `en-sweep` (2), `en-guardrail` (2), `en-build` (1). `en-brainstorm` was listed with one site; none remained when checked on 2026-09-03, and since that date the skill runs no bundled script at all.

- **What:** these skills instruct an agent to run a helper at
  `skills/<self>/scripts/<name>` — a path rooted at the Ensemble repo, not at the
  skill directory. `/en-sweep` says to run `skills/en-sweep/scripts/continuous-monitor`.

- **Why it matters:** the same failure the `$ENSEMBLE_ROOT` migration removed, in
  a new spelling. A skill installs alone, at `~/.claude/skills/<name>/`, where no
  `skills/` directory exists above it. The path resolves in this repo and nowhere
  a user actually runs the skill, so it is invisible here by construction.

- **Why the guards miss it:** the cross-skill clause excludes a skill's own name
  so it cannot flag self-references, and the anchored-invocation clause matches
  `bash scripts/x` rather than a repo-rooted path. Neither is wrong; the case
  falls between them.

- **Suggested fix:** the `$SKILL_DIR` anchor these skills already document for
  other calls — `SKILL_DIR="<dir of this SKILL.md>"; bash "$SKILL_DIR/scripts/x"`.
  Then extend the anchored-invocation clause to reject a repo-rooted self-path,
  with a negative control.

- **Logged:** 2026-08-31

## Resolved

### TD13. ~~A Codex session cannot dispatch a bundled agent by name, so the rendered TOML model does not bind~~ RESOLVED upstream 2026-09-10

Codex CLI gained the selector this item was waiting for. On 0.153.4 a session's
`spawn_agent` takes `agent_type`, `model` and `reasoning_effort` alongside
`task_name`, `fork_turns` and `message`, and `agent_type` loads the named
`~/.codex/agents/<name>.toml` as a high-precedence config layer on the child.

Reproduced 2026-09-10, two `codex exec` runs, read-only sandbox:

- The session listed its own `spawn_agent` parameters: `agent_type`, `fork_turns`,
  `message`, `model`, `reasoning_effort`, `task_name`. TD13 was filed when the
  first, fourth and fifth of those did not exist.
- Spawning with `agent_type: "repo-research"` produced a child whose rollout
  records `agent_role: repo-research` (this item was filed on `agent_role: null`)
  and `model = gpt-5.6-sol` at `medium`, the values `./setup` rendered into the
  TOML, against the parent's own `gpt-6-astra` at `low`.

`./setup`'s `render_codex_agent` needed no change: it already writes the `name`,
`model` and `model_reasoning_effort` fields `agent_type` resolves against.

**One thing the reproduction taught that the fix did not:** asked to name its own
model, the child answered with a model that was neither the parent's nor the
TOML's. A model's self-report is not evidence about its deployment; the rollout
is. That is now stated in `agent-dispatch.md` beside the dispatch instruction.

Resolved by updating the Codex half of `references/agent-dispatch.md` to dispatch
by `agent_type`, with the inline-body fallback kept for a CLI that predates the
parameter. See D115.

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
`en-build`, `en-plan`, `en-foundation` — still instructs:

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

### TD10. EN01 shipped with three units depending on a later-phase unit

Found 2026-08-29 by TD8's phase-aware lint, on its first run against history.

`EN01-improvement_skill-suite-optimization.md` declares U3 as `risk: medium`,
`category: schema-evolution`, which `/en-build` classifies as **P3**. U7, U8 and
U13 are `risk: medium`, `category: feature` — **P2** — and all three declare a
dependency on U3.

Three P2 units depending on a P3 unit is exactly the structural error the phase
invariant exists to reject. The risk-only check in force at the time saw a flat
plan of `medium` units and passed it.

**Not being fixed.** EN01 shipped. Rewriting a completed plan's metadata to
satisfy a rule added afterwards would be editing the record of what was actually
built, and the plan did build — most likely because phasing never engaged, or the
units happened to run in a workable order.

Recorded because it is a real fact about how that plan was structured, and
because it is the only empirical evidence so far that the risk-only check missed
things in practice rather than only in principle. The lint now scopes the rule to
`docs/plans/active/`, where it can still prevent a build-time rejection.

- **Severity:** P3 — historical record, no action.
- **Logged:** 2026-08-29.
