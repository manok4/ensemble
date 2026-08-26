# Making Ensemble skills self-contained

Review date: 2026-08-25
Reference implementation studied: `compound-engineering-plugin` v3.23.3 (`/Users/mano.kulasingam/CodeRepo/agent-skills/compound-engineering-plugin`)
Ensemble revision: branch `skill-review-d47-d51` @ `7040819`

---

## 1. What Compound Engineering does

CE ships 33 skills. Every one of them is a closed directory. No skill file points outside its own folder, by relative traversal or absolute path.

### The rule, and where it is written down

`AGENTS.md:283-301` states it directly: a SKILL.md may only reference files inside its own tree, and "If two skills need the same supporting file, duplicate it into each skill's directory." Three reasons are given, and all three apply to Ensemble:

- Skills execute from the user's working directory, not the skill directory.
- Marketplace installs land at versioned cache paths that change every release.
- The converter that emits Codex/Cursor/Gemini variants copies each skill directory as an isolated unit, so sibling directories are not in the copy.

The note dates the constraint (March 2026) and cites three open Claude Code path-resolution bugs. It is a deliberate, documented bet, not an accident.

### Three path tiers, not one

`AGENTS.md:311-341` splits bundled-file references by who resolves them:

| Tier | Case | Form |
|---|---|---|
| 1 | Model reads a co-located file | bare relative: `references/scope.md` |
| 2 | Prose names a bundled file the agent acts on | relative plus an explicit "from this skill's directory" cue |
| 3 | A bundled script runs through the Bash tool | `SKILL_DIR="<abs path of the dir holding the SKILL.md you just read>"; bash "$SKILL_DIR/scripts/x.sh"` |

Tier 3 matters. The Bash tool's cwd is the user's project on Claude Code, Codex, and Cursor alike, so a bare `bash scripts/x.sh` resolves against the project and exits 127. `SKILL_DIR` is model-filled, not a harness variable, which is exactly why it works on every host. CE records three bug numbers from getting this wrong (#764, #811, #898). It also bans `${CLAUDE_SKILL_DIR}` outright: it is a Claude-Code-only content substitution that expands to empty everywhere else, so a guarded call silently never fires off-Claude.

Grep confirms the discipline holds. Zero occurrences of `CLAUDE_PLUGIN_ROOT` anywhere under `skills/`.

### Duplication is managed, not tolerated

CE duplicates and then pins the copies. The `docs_root` resolution rule is byte-identical in 18 files. Each copy sits between `<!-- ce-docs-root:start -->` and `<!-- ce-docs-root:end -->`. The canonical text lives once, in `tests/fixtures/docs-root-rule.md`. `tests/docs-root-rule-parity.test.ts` asserts every listed consumer contains the block verbatim, and it carries a `CONSUMER_FILES` map recording the skills that relocated the block to a reference plus the step that guarantees it gets read.

Same pattern for `ce-config-layers` (10 copies), settled decisions, and cross-model receipts. Adding a consumer is one line in the test plus the pasted block.

I like this more than I expected to. Duplication with a machine-checked canonical source has the same correctness guarantee as an import, and none of the resolution risk.

### Inter-skill calls go by name, never by path

CE skills call each other with a bare skill name and a token argument. `ce-babysit-pr` invokes `ce-resolve-pr-feedback mode:pipeline`, `ce-debug mode:pipeline`, `ce-commit-push-pr mode:pipeline`. `lfg` invokes `ce-test-browser`, `ce-commit-push-pr`, `ce-babysit-pr` the same way.

`mode:pipeline` is a real contract, owned by the callee. `skills/ce-debug/references/pipeline-mode.md` defines it in about 40 lines:

- Never call a blocking-question tool.
- An **inherited authority envelope**: the callee mutates only under the scope the orchestrator already holds. It may narrow that envelope (defer, return `needs-human`) and may never widen it. A rebase or force-push is out of envelope even when it is the only way to green CI.
- A structured JSON return whose `status` is one of exactly five spellings, with the instruction "The caller branches on those exact spellings, so never rename, abbreviate, or add to them."
- Cost bounding: the quality tail (simplify/review) is skipped in pipeline mode because the orchestrator scopes review at its own level.

The caller never reads the callee's files. It reads the callee's contract.

---

## 2. Where Ensemble stands

### The current shape

```
ensemble/
  skills/en-*/SKILL.md      17 skills, only en-guardrail and en-resolve-pr/en-sweep ship a subdir
  references/               60 files, 516K
  bin/                      13 scripts, 136K
  agents/                   11 agents, 88K
```

Every skill opens with the same preamble, byte-identical across all 17:

> All `references/X` and `bin/Y` paths in this skill resolve relative to `$ENSEMBLE_ROOT`. Compute once at start: `$ENSEMBLE_ROOT` env var if set; otherwise `$(realpath "$(dirname <this-SKILL.md>)/../..")`.

That is 382 `$ENSEMBLE_ROOT` references across the skill set. Each one is a path that climbs two levels out of the skill directory and lands on a specific root layout.

### The install is already broken in copy mode

This is not a theoretical maintenance concern. I ran it.

`setup` symlinks or copies `skills/*/` into `~/.claude/skills/<name>/` and `agents/*.md` into `~/.claude/agents/`. It never installs `references/` or `bin/`. Grep for install steps touching those directories returns zero.

In symlink mode this happens to work: `realpath` resolves the symlink back into the source repo, and `../..` finds the real root. In copy mode it does not:

```
$ HOME=$T/home ./setup --host claude --copy
$ realpath ~/.claude/skills/en-plan/../..
$T/home/.claude
$ ls $T/home/.claude/references/host-detect.md
No such file or directory
$ ls $T/home/.claude/bin/ensemble-lint
No such file or directory
```

Every skill's own preamble says "Fail loudly if `$ENSEMBLE_ROOT/references/host-detect.md` does not resolve." So a copy-mode install fails all 17 skills at step 1. `setup:50` forces copy mode on MinGW/MSYS/Cygwin, which makes Windows the default-broken platform. The `--copy` flag is broken on macOS and Linux too.

Symlink mode also drags a hidden constraint: the source checkout must stay where it was when `setup` ran, at that path, forever.

### Dependency shape

Reference fan-in, measured:

| Users | Files | Notes |
|---|---|---|
| 17 | `host-detect.md` | every skill, 9K |
| 4-5 | `outside-voice.md` (17K), `finding-schema.md`, `severity.md`, `single-agent-fallback.md`, `peer-model-policy.md` | the peer-review cluster |
| 3 | `research-dispatch.md`, `stable-ids.md`, `recursion-guard.md`, `templates/plan-template.md` | |
| 2 | 11 files | |
| 1 | ~40 files | move with no thought required |
| 0 | `architecture-fitness.md`, `core-beliefs-starter.md`, `cli-wrappers.md` | orphans; `architecture-fitness.md` is referenced by `bin/ensemble-lint`, the other two look dead |

So the shared surface is small. Roughly 40 of 60 references have exactly one consumer and just move.

`bin/` is different. It is a coupled program, not a bag of files:

```
ensemble-peer-invoke  -> ensemble-cli-smoke, ensemble-extract-json   (sourced via BASH_SOURCE)
ensemble-config-get   -> ensemble-detect-host
ensemble-peer-flags   -> ensemble-detect-host
ensemble-classify-plans -> ensemble-lint
```

`ensemble-lint` alone is 44K and has 5 consumer skills. 45 test files reference `bin/` or `references/` paths from the repo root, and `.github/workflows/ensemble-tests.yml` calls `bin/ensemble-lint` directly.

Naive duplication of everything currently reachable costs 505K -> 1186K, a 2.35x increase.

### What is already right

Do not throw these away:

- Inter-skill calls already go by name with flags: `/en-review --peer --mode headless`, `/en-plan --resume`. No cross-skill file paths anywhere.
- `en-review` already has a three-mode matrix (`interactive` / `headless` / `report-only`) with a documented JSON envelope, a mandatory `peer_decision:` outcome line, and a closed reason enum. That is a better-specified callee contract than CE's.
- `references/recursion-guard.md` gives defense-in-depth against peer-review recursion.
- `en-guardrail` already ships `skills/en-guardrail/bin/`. The pattern exists in-tree.
- The bin scripts already self-locate via `BASH_SOURCE`, so they relocate as a unit without edits.

The problem is narrow: 382 paths that climb out of the skill directory into a root layout that the installer does not install.

---

## 3. Refactor roadmap

### Target layout

```
ensemble/
  shared/                          # build input. Never installed. Never read at runtime.
    references/
      host-detect.md
      outside-voice.md
      finding-schema.md
      severity.md
      single-agent-fallback.md
      peer-model-policy.md
      recursion-guard.md
      stable-ids.md
      research-dispatch.md
      templates/plan-template.md
    bin/
      ensemble-lint
      ensemble-peer-invoke
      ensemble-build-peer-prompt
      ensemble-cli-smoke
      ensemble-extract-json
      ensemble-detect-host
      ...
    manifest.yaml                  # which skill gets which shared file

  skills/
    en-plan/
      SKILL.md
      references/
        host-detect.md             # GENERATED from shared/, byte-identical
        outside-voice.md           # GENERATED
        severity.md                # GENERATED
        finding-schema.md          # GENERATED
        peer-model-policy.md       # GENERATED
        single-agent-fallback.md   # GENERATED
        stable-ids.md              # GENERATED
        research-dispatch.md       # GENERATED
        recursion-guard.md         # GENERATED
        plan-default-branch-checkpoint.md   # OWNED by en-plan
      templates/
        plan-template.md           # GENERATED
      scripts/
        ensemble-build-peer-prompt # GENERATED (closure)
        ensemble-peer-invoke       # GENERATED (closure)
        ensemble-cli-smoke         # GENERATED (pulled in by the closure)
        ensemble-extract-json      # GENERATED (pulled in by the closure)
        ensemble-lint              # GENERATED
      CONTRACT.md                  # what /en-plan accepts and returns to callers

    en-review/
      SKILL.md
      references/
        host-detect.md             # GENERATED, same bytes as en-plan's copy
        finding-schema.md          # GENERATED
        severity.md                # GENERATED
        persona-dispatch.md        # OWNED
        review-confidence-gating.md# OWNED
        diff-signal-detection.md   # GENERATED (2 consumers)
      scripts/
        ensemble-lint              # GENERATED
        ensemble-verify-peer-evidence  # GENERATED
      CONTRACT.md

  scripts/sync-shared              # regenerates every GENERATED file
  tests/parity/shared-parity.test.sh
```

A skill directory is now portable on its own. Copy `skills/en-plan/` anywhere and it runs.

`shared/` still exists but nothing reads it at runtime. It is a build input, the way a `src/` is. That satisfies the requirement, which was about runtime coupling to a root layout, not about having one edit point in the repo.

### Path forms after the refactor

| What | Form | Example |
|---|---|---|
| Model reads a bundled file | bare relative | ``read `references/severity.md` `` |
| Prose names a bundled script | relative plus a cue | ``run `scripts/ensemble-lint` from this skill's directory`` |
| A script runs through Bash | `SKILL_DIR` anchor | see below |

```bash
SKILL_DIR="<absolute path of the directory containing the SKILL.md you just read>";
bash "$SKILL_DIR/scripts/ensemble-lint" --scope docs/
```

Keep the trailing `;` on the assignment line. CE documents a real Codex failure where a fenced block is flattened to one line, the assignment becomes an env-var prefix, `$SKILL_DIR` expands before it is set, and the path becomes `/scripts/...`. That semicolon is load-bearing.

Do not introduce `${CLAUDE_SKILL_DIR}`. Ensemble ships to Claude Code and Codex, and that substitution is empty on Codex, which turns any guarded call into a silent skip.

### Steps

**Step 1. Fix the install first, before touching any skill.**

Make `setup` install `references/` and `bin/` alongside `skills/` in copy mode, or make copy mode refuse to run. Add a test that runs `setup --copy` into a temp HOME and asserts that `$ENSEMBLE_ROOT/references/host-detect.md` resolves. This is a one-commit bug fix and it is independently worth doing. It also gives the refactor a green baseline to regress against, and it means an abandoned refactor still leaves users better off.

**Step 2. Build the sync tool and the parity test before moving anything.**

`scripts/sync-shared` reads `shared/manifest.yaml`, copies each declared file into each declared skill, and for `bin/` follows `BASH_SOURCE` sourcing to pull in the transitive closure automatically. It prepends a `GENERATED FROM shared/... - DO NOT EDIT - run scripts/sync-shared` header to markdown copies and a comment line to scripts.

`tests/parity/shared-parity.test.sh` fails when any generated copy differs from its source, and fails when a skill references a file that the manifest does not give it. Run it in `.github/workflows/ensemble-tests.yml`.

Order matters. Build the guard first, then move code under it. A copy-based refactor without a parity gate silently rots within weeks.

Watch out for a known trap here. `tests/lint/*.test.sh` in this repo can pass silently when the final `report` call is missing, so assert that the new parity test actually goes red: break one copy on purpose and confirm the failure before trusting it.

**Step 3. Move the 40 single-consumer references. No sync involved.**

`git mv references/qa-flows.md skills/en-qa/references/qa-flows.md`, then rewrite `$ENSEMBLE_ROOT/references/qa-flows.md` to `references/qa-flows.md` in that skill. Delete the three orphans after confirming nothing needs them, and keep `architecture-fitness.md` with `ensemble-lint`.

Per-skill commits. Seventeen small reviewable changes.

**Step 4. Move the shared references under the sync tool.**

Start with `host-detect.md`, the 17-consumer case. It is the highest fan-in and the least interesting content, so it exercises the whole mechanism with the lowest blast radius. Then the peer-review cluster: `outside-voice.md`, `finding-schema.md`, `severity.md`, `peer-model-policy.md`, `single-agent-fallback.md`.

**Step 5. Move `bin/` into per-skill `scripts/`.**

The closure logic earns its keep here. `en-plan` declares `ensemble-build-peer-prompt` and `ensemble-peer-invoke`; the tool notices `ensemble-peer-invoke` sources `ensemble-cli-smoke` and `ensemble-extract-json` and copies those too.

The 45 test files keep running against `shared/bin/`, unchanged. Tests test the source of truth. The parity test covers the copies. That is the whole reason the shared tree stays.

Repo grows to roughly 1.2MB. That is not a real cost.

**Step 6. Delete the `$ENSEMBLE_ROOT` preamble from all 17 skills, and add a lint rule that fails on any `$ENSEMBLE_ROOT`, `../`, or absolute path in a skill file.**

The lint rule is the point of the step. Without it the pattern comes back the first time someone adds a skill by copying an old one.

**Step 7. Write `CONTRACT.md` for the six skills that are called by other skills.**

See section 4.

### If you would rather not duplicate the scripts

The alternative is installing `bin/` as a real CLI on PATH and having skills call `ensemble-lint` by bare command name. One copy, one test target, no diff noise.

I did not pick it. It trades a build-time invariant for a runtime one: PATH may be missing the directory, an old copy may shadow a new one, and version skew between an installed CLI and a skill that expects newer flags becomes possible. Duplication with a byte-parity test has none of those failure modes, and 700K of repo is cheaper than a class of install bugs. If you disagree, the tell is Step 5 and only Step 5. Everything else in this plan is unchanged either way.

---

## 4. Inter-skill calls

Self-containment is about **files**, not about **behavior**. A skill calls another skill by name. It never reads the callee's files, never reaches into the callee's `references/`, and never assumes anything about the callee's directory.

Ensemble already does the calling part right. What is missing is a callee-owned, versioned contract that the caller can depend on.

### Rule 1: invoke by name, pass tokens

```
/en-review --peer --mode headless
```

Never:

```
read ../en-review/references/persona-dispatch.md      # cross-skill file read
$ENSEMBLE_ROOT/skills/en-review/scripts/...           # root-relative path
```

If `/en-plan` needs to know how `/en-review` scores severity, it does not read `en-review`'s copy. It gets its own generated copy of `severity.md` from `shared/`, and the parity test guarantees the two copies match. Shared understanding without shared files.

### Rule 2: every callable skill owns a `CONTRACT.md`

One page, in the callee's own directory, at `skills/<name>/CONTRACT.md`. Six skills need one today: `en-review`, `en-cross-review`, `en-plan`, `en-build`, `en-learn`, `en-simplify`.

It states:

1. **Accepted invocations.** The exact flag spellings a caller may pass.
2. **Non-interactive guarantee.** In `headless` and `report-only`, never call a blocking-question tool. Ensemble has this; write it down as a promise to callers, not as an internal note.
3. **Return schema.** The JSON envelope, with a closed enum for any status field, and the CE line spelled out: the caller branches on these exact spellings, so never rename, abbreviate, or add to them.
4. **Authority envelope.** Borrow CE's framing directly. Being invoked by an orchestrator is not itself authorization. The callee mutates only within the scope the caller already holds, and may narrow that scope but never widen it. `/en-review --mode headless` applies `safe_auto` only. `/en-review --mode report-only` mutates nothing. Both already behave this way; the contract makes it a promise instead of an implementation detail.
5. **Cost bounds.** What the callee skips when called by a skill rather than a human. `en-review` in `report-only` never runs a peer. State it here so a caller can reason about cost without reading `SKILL.md`.
6. **Recursion posture.** How the callee behaves under `ENSEMBLE_PEER_REVIEW=true`.

`CONTRACT.md` is owned by the callee, not generated, and not duplicated. A caller cites it by name in prose ("per `/en-review`'s contract") and never by path. Changing a status enum is then a visible edit to a file whose whole purpose is to be a contract, which is exactly the review signal you want.

### Rule 3: recursion guard stays, and each skill carries its own copy

`recursion-guard.md` gets synced into every skill that can invoke cross-review, same as `host-detect.md`. The env var is the coordination mechanism, and an env var is not a file dependency.

### Rule 4: no skill may be a library

If two skills need the same logic, it goes in `shared/` and both get a copy. It never lives in one skill that the other calls purely to read. `/en-plan` calling `/en-review` is fine because it wants the review performed. Calling a skill to borrow its files is the pattern this refactor removes.

---

## 5. What will go wrong

**Copies drift.** The whole bet. Mitigated by the parity test in CI, the `GENERATED - DO NOT EDIT` header, and building the gate in Step 2 before any content moves. Verify the gate fails when you break a copy on purpose; a guard that cannot fail is decorative.

**Someone edits a generated copy instead of the source.** The header says not to, and the parity test catches it, but the diff is confusing: you fixed a real bug and CI says you broke parity. Make the failure message say "you edited a generated file; move your change to `shared/references/X.md` and run `scripts/sync-shared`."

**Codex truncates SKILL.md.** CE's parity test notes that Codex injects only the first 8000 bytes of a SKILL.md. Ensemble's `en-build/SKILL.md` is 49K, `en-plan` 32K, `en-setup` 27K. This is already true today and is not caused by the refactor, but it changes where you put things: a rule that must be honored belongs in a reference the skill reads early, not deep in a long body. CE handles this explicitly, mapping `lfg` to `references/plan-brief.md` for exactly this reason. Worth a separate look after this work lands.

**Tier 3 path bugs.** Every `bin/` call becomes a `SKILL_DIR`-anchored call, and CE logged three bugs learning this. Mitigation: one worked example in the contributor docs, the lint rule from Step 6, and a smoke test that runs each skill's bundled scripts from a copied install with cwd set to an unrelated project directory.

**45 test files and one CI workflow.** They keep pointing at `shared/bin/`. This is only a problem if you take the PATH-install alternative, where every one of them needs rewriting. Another reason I did not pick it.

**Half-migrated state.** Steps 3 through 5 span many commits, and during that window some skills are self-contained and some are not. Keep the Step 6 lint rule in warn-only mode until Step 5 finishes, then flip it to fail. Do not flip early, or every intermediate commit is red.

**Merge conflicts against in-flight work.** The branch touches all 17 skills. Land Step 1 immediately as its own commit, then sequence the rest when no large skill rewrite is open.

---

## Summary

The Compound Engineering plugin proves the design works at 33 skills: no cross-skill references, three explicit path tiers, duplicated shared blocks pinned by byte-parity tests, and inter-skill calls by name with a callee-owned pipeline contract.

Ensemble's coupling is narrow: 382 `$ENSEMBLE_ROOT` paths, about 20 genuinely shared reference files, and one coupled `bin/` package. Roughly two thirds of the references have a single consumer and just move.

The urgent finding is separate from the refactor. `setup` never installs `references/` or `bin/`, so copy-mode installs, the default on Windows, fail every skill at its own first step. Fix that this week whether or not the rest of this plan goes ahead.
