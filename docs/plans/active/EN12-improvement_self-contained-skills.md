---
type: plan
plan_type: improvement
plan_id: EN12
title: Self-contained skill directories with a synced shared tree
status: draft
location: active
created: 2026-08-26
shipped:
deepened:
covers_requirements: [G9, G10, G13]
requirements_pending: false
related_design: docs/reviews/self-contained-skills-refactor.md
peer_review_verdict: revise
peer_review_iterations: 2
peer_review_last_run: 2026-08-26
peer_review_plan_hash:
peer_review_resolutions:
  - finding_id: "1-1"
    iteration: 1
    severity: P1
    title: U2 breaks source-checkout skill resolution before consumers migrate
    status: applied
    rationale: Correct and load-bearing. Moving references/ and bin/ under shared/ deletes the exact paths unmigrated skills read, and the installer bridge copies $SOURCE_DIR/references, which would no longer exist. U2 now leaves root references and bin as symlinks to the shared tree for the U3-to-U8 window, U9 removes them in a named order, and U2 gained an integration scenario asserting an unmigrated skill still resolves from both a source checkout and a copied install.
    location: U2. Establish `shared/` as the canonical tree
  - finding_id: "1-2"
    iteration: 1
    severity: P1
    title: Bundled agents remain unusable from an isolated skill directory
    status: applied
    rationale: Independently confirms the constraint raised with the user before planning. Bundling copies alone leaves files present but unread, since hosts resolve subagent_type from a flat registry. U7 now changes where that registry is populated from: setup publishes the union of skills/*/agents/*.md rather than shared/agents/, so installing one skill publishes exactly its agents. Byte-identical copies make the union collision-free, with a same-name-different-bytes parity assertion and a single-skill install test that performs a real dispatch with no shared/ present.
    location: U7. Bundle agents into skills and publish them from there
  - finding_id: "1-3"
    iteration: 1
    severity: P1
    title: Cross-host path resolution assumption is not assigned a real verification scenario
    status: applied
    rationale: The assumption was stated with a falsification method but no unit owned it, so nothing would have run it. U4 gained an integration scenario that copies a migrated skill into an isolated directory with no shared/ or source checkout reachable, invokes it on both hosts, and requires content only the referenced file contains so an empty read cannot pass.
    location: U4. Sync shared references and templates into consuming skills
  - finding_id: "1-4"
    iteration: 1
    severity: P1
    title: Contract coverage and behavioral promises are not fully tested
    status: applied
    rationale: Applied with a stated scope boundary. Added a call-graph check that enumerates every inter-skill invocation, requires a contract for each target, and validates flags against the contract's accepted set, which turns the callee count from a hand-count into a derived fact. Added behavioral probes for report-only no-mutation and no-peer, headless envelope parse against the declared enum, and recursion suppression. The authority-envelope and cost-bound clauses stay prose: narrowing-not-widening is a property of every future change rather than of any single run, so a probe would assert less than it appears to.
    location: U10. `CONTRACT.md` for the six callable skills
  - finding_id: "1-5"
    iteration: 1
    severity: P2
    title: U3 is not an atomic implementation unit
    status: applied
    rationale: Agreed on both counts. U3 now migrates in bounded per-owning-skill batches with the suite green after each, rather than one 40-file unit. Zero-consumer validation and deletion moved to a new U11, because a bad move leaves a dangling path any assertion catches while a bad delete removes content nothing notices; different failure modes belong in different units.
    location: U3 and new U11
  - finding_id: "2-1"
    iteration: 2
    severity: P1
    title: Generated headers conflict with byte parity and executable scripts
    status: applied
    rationale: A real contradiction in the iteration-1 design. U1 injected a first-line generated header while later units required byte-identical copies; those cannot both hold, and for a script the header would sit above the shebang and stop direct execution, which U5's `bash script` invocation would not have caught. Generated copies are now byte-for-byte with mode bits preserved, generated-ness is derived from the manifest alone, and the do-not-edit warning lives inside the canonical source (below the shebang for scripts) so it travels as part of the bytes. Added cmp-based parity, mode-bit assertions, and a direct `./script` invocation.
    location: U1, Technical design key interfaces, U5
  - finding_id: "2-2"
    iteration: 2
    severity: P1
    title: The applied agent-publication resolution remains installer-specific
    status: applied
    rationale: The iteration-1 fix was genuinely incomplete. It taught repo-level `setup` to publish, but a lone skill directory contains no `setup`, and both plugin manifests still pointed `agents` at `shared/agents/`, a build input absent from an installed plugin. U7 now owns all three routes: `setup` publishes the union; the manifests repoint at a flat directory generated from the skills; and for a lone skill directory, where no host hook exists, the skill resolves its own agents by falling back to its bundled `agents/<name>.md` dispatched as a general-purpose agent prompt. Tested by a real dispatch on both hosts with no shared/, no setup and no checkout reachable.
    location: U7. Bundle agents into skills and publish them from there
  - finding_id: "2-3"
    iteration: 2
    severity: P1
    title: The model-filled SKILL_DIR anchor lacks live host verification
    status: applied
    rationale: Correct, and it is the part most likely to fail. A shell smoke test that sets SKILL_DIR itself proves the script runs while proving nothing about whether the host gives the model a correct absolute path to substitute. U6 gained a live scenario on both hosts, started from an unrelated working directory against an isolated install, where the script prints a distinctive marker and its own resolved path so a silent fallback to the source checkout is ruled out.
    location: U6. Convert every bundled-script call site to the `SKILL_DIR` anchor
  - finding_id: "2-4"
    iteration: 2
    severity: P2
    title: Out-of-scope truncation debt is fused into the anchor migration
    status: applied
    rationale: Agreed. A doc-only tracker edit riding inside the highest-risk unit in the plan weakens exactly the atomic review and rollback that unit needs most, and the item is already declared out of scope. Removed from U8 and given its own doc-only unit U12 with no dependencies.
    location: U8 and new U12
depth: deep
data_scale: small
---

# EN12 — Self-contained skill directories with a synced shared tree

## Context

Every skill resolves its helpers through `$ENSEMBLE_ROOT`, computed as `realpath(<skill dir>/../..)`, and then reads `$ENSEMBLE_ROOT/references/X` and `$ENSEMBLE_ROOT/bin/Y`. That is 382 paths across 17 skills, all climbing two levels out of the skill directory onto a specific root layout. The layout is not portable: a skill folder alone is not a working skill, so anything that moves or copies one (an installer, a marketplace cache, a cross-host converter) has to know to carry two sibling directories with it.

That already cost correctness. `setup` shipped skills and agents per unit and never carried `references/` or `bin/`, so copy-mode installs resolved `$ENSEMBLE_ROOT` to a directory holding neither and every skill failed its own fail-loudly probe at step 1. Commit `3ef2151` patched the installer as a bridge; U9 removes that bridge, because a self-contained skill has nothing left to install separately.

The analysis, measurements and roadmap this plan implements are in `docs/reviews/self-contained-skills-refactor.md`, written 2026-08-26 after studying the Compound Engineering plugin's closed-skill-directory design.

## Requirements covered

- **G9** — skills work identically across Claude Code and Codex. Removing the root-layout assumption is what makes a skill directory survive being copied by either host's install path.
- **G10** — token-efficient, on-demand reference loading. Unchanged in kind: skills still load references on demand, now from their own directory.
- **G13** — mechanical doc lints catch drift before it compounds. The parity guard and the inverted anchor guard are the mechanical enforcement.

## Out of scope for this plan

- Splitting oversized SKILL.md bodies. `en-build` is 49K and Codex injects only the first 8000 bytes of a SKILL.md, so load-bearing rules deep in a long body may never reach that host. Real, pre-existing, and orthogonal. U12 files it as tracked debt; fixing it is separate work.
- Replacing bundled scripts with a PATH-installed CLI. Considered and rejected in the design doc: it trades a build-time invariant for a runtime one (PATH ordering, version skew) and would force a rewrite of all 45 test files.
- The `setup` manifest-sweep mode bug (the sweep tests the current run's mode rather than what was previously installed). Separate concern, tracked outside this plan.
- Updating the user's `~/.ensemble-source` checkout, which currently sits at `a56a869` and predates this branch.

## Approach (high-level)

Each skill directory becomes closed: it holds every reference, template, script and agent it reads, and no path in it climbs above itself. Read-time references use bare relative paths (`references/severity.md`), which every target host resolves against the skill directory. Anything executed through the Bash tool uses a model-filled `SKILL_DIR` anchor, because the Bash tool's working directory is the user's project on Claude Code and Codex alike, so a bare `bash scripts/x` resolves against the project and exits 127.

Single-edit-point maintenance survives duplication through generation rather than reference. Canonical copies move to a new `shared/` tree that is a build input and is never installed and never read at runtime. `scripts/sync-shared` pushes declared files into each consuming skill, following `BASH_SOURCE` sourcing so a script's transitive closure travels with it. A byte-parity test fails CI when any generated copy drifts from its source, which gives duplication the same correctness guarantee as an import with none of the resolution risk.

Inter-skill calls do not change shape: `/en-plan` invokes `/en-review --peer --mode headless` by name, and never reads the callee's files. What is added is a `CONTRACT.md` per callable skill, stating accepted invocations, the non-interactive guarantee, the return schema with closed enums, the authority envelope a callee may narrow but never widen, and cost bounds. A caller depends on that stated promise instead of on the callee's internals.

Sequencing protects the half-migrated window. The parity guard is built before any content moves (U1), the anchor drift guard is inverted only after every skill has moved (U8), and the installer bridge is removed last (U9).

## Technical design

Architecture-complexity triggers fired: four new or changed components, a three-stage data flow, and a public contract format. Directional sketch follows.

**Component boundaries**

| Component | Responsibility | Never does |
|---|---|---|
| `shared/` | Canonical text for anything with 2+ consumers. Build input. | Get installed. Get read at runtime. |
| `shared/manifest.json` | Declares which skill receives which shared file, and the destination subdirectory. | Encode runtime behavior. |
| `scripts/sync-shared` | Copies declared files into skills, resolves script closures, stamps generated headers. | Edit skill-owned files. |
| `tests/parity/shared-parity.test.sh` | Fails when a generated copy drifts, or a skill reads a file the manifest does not grant it. | Modify anything. |
| `skills/<name>/CONTRACT.md` | Callee-owned promise to calling skills. Hand-written, never generated. | Get duplicated into callers. |

**Data flow**

```
author edits shared/references/host-detect.md
        │
        ▼
scripts/sync-shared   reads shared/manifest.json
        │             resolves BASH_SOURCE closure for scripts
        │             stamps "GENERATED - DO NOT EDIT" header
        ▼
skills/en-plan/references/host-detect.md      (17 destinations)
skills/en-plan/scripts/ensemble-peer-invoke   (+ closure: cli-smoke, extract-json)
        │
        ▼
setup  copies or symlinks skills/<name>/ as one closed unit
        │
        ▼
runtime: SKILL.md reads `references/host-detect.md`          (skill dir)
         SKILL.md runs  `"$SKILL_DIR/scripts/ensemble-lint"` (skill dir, anchored)
```

**Key interfaces**

- Manifest entry: `{ "source": "references/host-detect.md", "dest": "references/", "skills": ["en-plan", ...] }`. Script entries additionally carry `"closure": true`, which makes the tool walk `. "$_dir/sibling"` lines and copy the transitive set.
- Generated-file identity comes from `shared/manifest.json`, not from anything injected into the file. `sync-shared` copies bytes verbatim and preserves the mode bits, so a generated copy is a byte-for-byte match of its source and an executable stays executable. Injecting a header would break parity by construction, and for a script it would land above the shebang and stop the file executing directly. The do-not-edit warning still travels with the file, because it is written **into the canonical source** in `shared/` (below the shebang for scripts), which makes it part of the bytes rather than something added on top.
- Executed-script call form, used at every call site after U6:

  ```
  SKILL_DIR="<absolute path of the directory containing the SKILL.md you just read>";
  bash "$SKILL_DIR/scripts/ensemble-lint" --scope docs/
  ```

  The trailing semicolon on the assignment line is load-bearing, not style. Some hosts flatten a fenced multi-line block into one line before executing it; without the semicolon the assignment becomes an env-var prefix, `$SKILL_DIR` expands before it is set, and the path collapses to `/scripts/...`.

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. Sync tool, manifest, and parity guard

- **Goal:** A working generate-and-verify mechanism exists before any content depends on it.
- **Requirements covered:** G13
- **Dependencies:** none
- **Files:** `scripts/sync-shared`, `shared/manifest.json`, `shared/README.md`, `tests/parity/shared-parity.test.sh`
- **Approach:** Bash plus `jq`, matching the repo's existing toolchain and CI's declared tool requirements. No new dependencies. `sync-shared` reads the manifest, copies each source to each declared skill destination byte-for-byte with mode bits preserved, and for entries marked `closure: true` walks `. "$_dir/<sibling>"` lines to copy the transitive script set. It injects nothing: the manifest is the sole record of which files are generated, so parity is an exact comparison rather than a comparison modulo a header. `--check` mode diffs instead of writing, which is what the parity test calls. `shared/README.md` states plainly that the tree is a build input, is never installed, and is never read at runtime.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a manifest entry granting `references/host-detect.md` to two skills; `sync-shared` writes both copies with the generated header, and `--check` then exits 0.
  - *Happy path:* a script entry with `closure: true` for `ensemble-peer-invoke`; the tool also copies `ensemble-cli-smoke` and `ensemble-extract-json`, which it sources.
  - *Edge case:* a manifest entry naming a skill directory that does not exist. The tool exits non-zero naming the skill rather than creating the directory.
  - *Happy path:* every generated copy is byte-identical to its source under `cmp`, and generated scripts keep the source's mode bits.
  - *Happy path:* a generated script runs when executed **directly** (`./scripts/ensemble-lint`), not only via `bash scripts/ensemble-lint`. Invoking through `bash` masks both a lost executable bit and a shebang pushed off line 1, so the direct form is the one asserted.
  - *Edge case:* a skill directory holding both a generated file and a skill-owned file. `--check` consults the manifest to tell them apart and does not report the skill-owned file as drift.
  - *Error path:* a generated copy edited by hand. `--check` exits non-zero, names the file, and the message says to move the change to the source and re-run `scripts/sync-shared` rather than reporting a generic mismatch.
  - *Error path:* a skill reads a path the manifest does not grant it. The parity test exits non-zero naming skill and path.
  - *Negative control:* deliberately corrupt one generated copy and confirm the test goes red. A guard nobody has seen fail is decorative. Assert this in the test's own run, not only by hand.
- **Verification:** `./tests/run.sh -k parity` green; the negative control observed red before it is observed green; `./tests/run.sh` still 63/63 files passing.

### U2. Establish `shared/` as the canonical tree

- **Goal:** `references/`, `bin/` and `agents/` move under `shared/`, and every existing consumer follows.
- **Requirements covered:** G13
- **Dependencies:** U1
- **Files:** `shared/references/**` (from `references/`), `shared/bin/**` (from `bin/`), `shared/agents/**` (from `agents/`), `.github/workflows/ensemble-tests.yml`, `setup`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, ~45 files under `tests/`
- **Approach:** `git mv` the three directories, then a mechanical path update across their consumers. The 45 test files keep testing the canonical source, which is the reason the shared tree exists at all. `plugin.json`'s `agents` and `skills` keys point at the new paths. `bin/` scripts already self-locate via `BASH_SOURCE`, so they relocate as a unit without internal edits.

  **Compatibility shim, and why it is required.** No skill content changes in this unit, so all 17 skills still read `$ENSEMBLE_ROOT/references/X`. `$ENSEMBLE_ROOT` resolves to the source checkout under a symlink install and to the plugin cache under a marketplace install, and in both cases the move would delete the very paths those skills read. The installer bridge does not save this: it copies `$SOURCE_DIR/references`, which after the move no longer exists. So U2 leaves repo-root `references` and `bin` as symlinks to `shared/references` and `shared/bin`. They exist only to keep unmigrated skills resolving through the U3-to-U8 window, and U9 removes them once no skill reads them. Root symlinks also keep CI and any missed test path working while the mechanical update lands.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** characterization-first
- **Test scenarios:**
  - *Happy path:* `./tests/run.sh` passes 63/63 files after the move with no test logic changed, only paths.
  - *Happy path:* `bash shared/bin/ensemble-lint --scope docs/` exits 0, proving the sourcing graph survived relocation.
  - *Integration:* `./setup --verify-only --quiet` exits 0, and a copy-mode install into a temp HOME still satisfies `tests/install/setup-shared-helpers.test.sh` unchanged.
  - *Integration:* an **unmigrated** skill still resolves its helpers immediately after this unit, exercised from both live layouts: a source checkout (`$ENSEMBLE_ROOT` is the repo) and a copied install. Assert `$ENSEMBLE_ROOT/references/host-detect.md` and `$ENSEMBLE_ROOT/bin/ensemble-lint` both resolve through the root shims. This is the assertion that makes the green intermediate state real rather than assumed.
  - *Error path:* no reference to the old `references/` or `bin/` root paths remains in `tests/`, `.github/` or `setup` (skills are exempt until U8, and the two root shims are the only permitted survivors). A grep assertion fails if one does.
  - *Error path:* deleting either root shim before U9 breaks the unmigrated-skill assertion above, so the shim's removal cannot be done early by accident.
- **Verification:** full suite green; CI workflow green; `grep -rn 'ensemble-lint' .github/ tests/` shows only `shared/bin/` paths; unmigrated-skill resolution green from a source checkout and from a copied install.

### U3. Move single-consumer references into their owning skills

- **Goal:** The ~40 references with exactly one consumer live in that consumer, with no sync involved.
- **Requirements covered:** G9
- **Dependencies:** U2
- **Files:** `skills/*/references/*.md` (new), `shared/references/*.md` (removed), the owning `skills/*/SKILL.md`
- **Approach:** For each reference with fan-in 1, `git mv shared/references/X.md skills/<owner>/references/X.md` and rewrite that skill's `$ENSEMBLE_ROOT/references/X.md` to `references/X.md`. Migrate in **bounded batches of one owning skill each**, so a batch is reviewable, revertible and complete on its own; the unit is done when the last owner is migrated. Zero-consumer files are not touched here. They are a distinct concern with a different failure mode (deleting something still read) and live in U11.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* every moved reference resolves from its owning skill directory; a per-skill assertion walks each `references/X.md` mentioned in a SKILL.md and confirms the file exists relative to that skill.
  - *Happy path:* each batch is independently green, so the suite passes after every owning skill's migration rather than only at the end of the unit.
  - *Edge case:* a reference named by a `shared/bin/` script as well as by one skill (`architecture-fitness.md`, read by `ensemble-lint`). It is not single-consumer, stays in `shared/`, and is synced rather than moved.
  - *Error path:* a file is moved but its skill still names the `$ENSEMBLE_ROOT` path. The resolution assertion catches the dangling reference and fails.
  - *Error path:* a batch that moves a file two skills read. The fan-in check fails before the move, routing the file to U4's manifest instead.
- **Verification:** full suite green after every batch, not only at unit end; `bash shared/bin/ensemble-lint --scope docs/` exits 0; every skill's own references resolve relative to the skill directory.

### U4. Sync shared references and templates into consuming skills

- **Goal:** The ~20 multi-consumer references and templates are generated into every skill that reads them.
- **Requirements covered:** G9, G13
- **Dependencies:** U2
- **Files:** `shared/manifest.json`, `skills/*/references/*.md` (generated), `skills/*/templates/*.md` (generated), all 17 `skills/*/SKILL.md`
- **Approach:** Start with `host-detect.md`. Highest fan-in at 17 and the least interesting content, so it exercises the whole mechanism at the lowest blast radius. Then the peer-review cluster (`outside-voice.md`, `finding-schema.md`, `severity.md`, `peer-model-policy.md`, `single-agent-fallback.md`), then the remainder including `templates/plan-template.md`. Each batch is a manifest entry plus a `sync-shared` run plus the path rewrite in consuming skills.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* after syncing `host-detect.md`, all 17 skills hold a byte-identical copy and `sync-shared --check` exits 0.
  - *Happy path:* `/en-plan`'s copy of `severity.md` and `/en-review`'s copy are byte-identical, which is what lets the two skills share an understanding without sharing a file.
  - *Edge case:* a skill that reads a shared reference from within its own reference rather than from SKILL.md. The path rewrite covers nested reads, and the resolution assertion walks reference files too, not only SKILL.md.
  - *Error path:* a skill is granted a file in the manifest but never reads it. The parity test reports the unused grant so the manifest cannot accumulate dead entries.
  - *Integration:* `sync-shared` run twice in a row is a no-op; the second run writes nothing and `--check` stays green.
  - *Integration (live cross-host resolution):* file-existence assertions do not exercise either host's resolver, and G9 rests on that behavior. Copy one migrated skill into an isolated directory with no `shared/` and no source checkout beside it, install it into a clean host profile, and invoke it on **both** hosts with a prompt that forces the skill to read a bare relative reference. Expected: each host returns content that only the referenced file contains, so a silently empty read cannot pass. Record both invocations and both observed outputs as the unit's evidence.
- **Verification:** `sync-shared --check` exits 0; parity test green; every `references/X.md` named in any skill file resolves inside that skill; live relative-reference read observed on Claude Code and on Codex, with the distinguishing content quoted in the unit's evidence.

### U5. Sync shared scripts into per-skill `scripts/`

- **Goal:** Each skill carries the scripts it invokes, including their sourcing closures.
- **Requirements covered:** G9
- **Dependencies:** U2
- **Files:** `shared/manifest.json`, `skills/*/scripts/*` (generated)
- **Approach:** Declare each skill's directly invoked scripts; the closure walker adds what those source. `en-plan` declares `ensemble-build-peer-prompt` and `ensemble-peer-invoke`, and the tool pulls in `ensemble-cli-smoke` and `ensemble-extract-json` because `ensemble-peer-invoke` sources them. Copies keep the executable bit. Call sites are not rewritten in this unit; U6 owns that, so a bisect can separate a bad copy from a bad call form.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* `skills/en-plan/scripts/` contains all four scripts of the peer-invoke closure, each executable.
  - *Happy path:* running a skill-local copy directly (`bash skills/en-review/scripts/ensemble-lint --scope docs/`) produces the same exit code and output as the `shared/bin/` original.
  - *Edge case:* a script sourcing a sibling by a path built from `BASH_SOURCE` still resolves from its new location, since the sibling travelled with it.
  - *Edge case:* two skills declare overlapping closures. Both get complete, independent sets, and neither copy references the other skill.
  - *Error path:* a declared script sources a sibling that is not in `shared/bin/`. The tool exits non-zero naming both files rather than emitting a copy that would fail at runtime.
- **Verification:** parity test green; each skill-local script runs standalone from its own directory; closure completeness asserted per skill.

### U6. Convert every bundled-script call site to the `SKILL_DIR` anchor

- **Goal:** No executed-shell call in any skill depends on the Bash tool's working directory.
- **Requirements covered:** G9
- **Dependencies:** U5
- **Files:** all `skills/*/SKILL.md` with `bin/` or `scripts/` invocations, `tests/lint/skill-helper-anchor.test.sh`, `tests/install/` smoke test
- **Approach:** The highest-risk unit in the plan. Rewrite every fenced or inline shell invocation of a bundled script to the anchored form, keeping the trailing semicolon on the assignment line. Read-time reference mentions stay bare relative and are not touched here. Add a smoke test that runs each skill's bundled scripts with the working directory set to an unrelated project, which is the condition that turns a bare relative path into `exit 127`.
- **Risk:** high
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* every anchored call runs successfully with `cwd` set to a scratch directory outside the repo.
  - *Happy path:* the assignment line retains its trailing semicolon in every converted block; asserted by pattern, since flattening a block without it silently expands `$SKILL_DIR` to empty.
  - *Edge case:* an inline `bash …` invocation in prose rather than a fenced block. It gets the anchor too, since the failure mode is identical.
  - *Edge case:* a read-time reference mention such as "read `references/severity.md`" is left bare and is not wrongly anchored.
  - *Error path:* a bare `bash scripts/x` left anywhere in a skill. The lint asserts absence and fails naming the skill and line.
  - *Error path:* the anchored path points at a script the skill does not carry. The smoke test fails with the missing path rather than a generic non-zero exit.
  - *Integration (live, both hosts):* a shell smoke test sets `SKILL_DIR` itself, so it proves the script works while proving nothing about the part that can actually fail, which is whether the host gives the model a correct absolute path to substitute. Install one migrated skill in isolation, start each host from an unrelated working directory, and prompt it to run the skill's bundled script. The script prints a distinctive marker **and its own resolved path**. Expected: the marker appears and the printed path is inside the isolated skill directory, which rules out a silent fallback to the source checkout. Run on Claude Code and on Codex; record both transcripts as evidence.
- **Verification:** smoke test passes from an unrelated working directory for every skill that invokes a script; no bare executed-shell relative path remains; live anchored invocation observed on both hosts with the executed path proven to come from the isolated skill; full suite green.

### U7. Bundle agents into skills and publish them from there

- **Goal:** A skill folder carries the agents it dispatches, and installing that folder alone makes those agents dispatchable.
- **Requirements covered:** G9
- **Dependencies:** U2
- **Files:** `shared/manifest.json`, `skills/*/agents/*.md` (generated), `setup`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, consuming `skills/*/SKILL.md`, `tests/install/single-skill-install.test.sh`
- **Approach:** Bundling copies alone would leave the files present but unread: hosts resolve `subagent_type` from a flat registry, so a skill directory copied on its own dispatches an agent that is not installed anywhere. This unit therefore changes **where the flat registry is populated from**, not just where the files sit. `sync-shared` generates agent copies into each consuming skill, and `setup` publishes the union of `skills/*/agents/*.md` into `~/.<host>/agents/` instead of publishing from `shared/agents/`. Installing one skill then publishes exactly that skill's agents, which is what makes an isolated skill directory operationally complete rather than decoratively complete.

  The union is collision-free because the copies are byte-identical by construction and the parity test enforces it, so two skills publishing `repo-research.md` write the same bytes. `setup` gains a single-skill install path so this is exercisable, and the parity test gains a same-name-different-bytes assertion so a future divergence fails the build instead of producing a last-writer-wins registry.

  **Every install route, not just `setup`.** Teaching `setup` to publish is not sufficient, because a lone skill directory does not contain `setup`. The unit owns all three routes. (1) **Repo-level install** (`./setup`): publishes the union of `skills/*/agents/*.md`, as above. (2) **Plugin or marketplace install**: both manifests currently point `agents` at `shared/agents/`, which contradicts the shared tree being a build input, so U7 repoints them at a flat directory that `sync-shared` generates from the skills. The plugin route therefore publishes the same set from the same source of truth. (3) **A lone skill directory dropped into a host's skills folder**, which is the route with no host hook to register an agent at all. For that route the skill resolves its own agents: a dispatch step first tries the registered agent by name, and when that name is not registered it reads its bundled `agents/<name>.md` and dispatches a general-purpose agent with that definition as the prompt. That path needs nothing outside the skill directory, which is what makes the bundled copies load-bearing rather than decorative. The fallback is written once and synced, not hand-copied into 11 dispatch sites.

  `en-review` receives its seven reviewer agents; `repo-research` goes to five skills, `learnings-research` to four, `web-research` to three, `code-simplifier` to two. Twenty-one copies of eleven files, about 120K.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* each consuming skill holds a byte-identical copy of every agent it names, and `sync-shared --check` exits 0.
  - *Happy path:* a full install publishes the same eleven agents, by name and by content, as the pre-change `shared/agents/` publish. Asserted as a set comparison so the change is provably non-regressive.
  - *Integration (the finding's real test):* copy **one** skill directory into a clean host profile, with no `shared/`, no other skill, no `setup` and no source checkout reachable. Perform an **actual dispatch** of an agent that skill names, on **both** hosts. Expected: the dispatch resolves and returns, via the in-skill fallback rather than the registry. This is the assertion that separates bundling that works from bundling that only looks tidy.
  - *Happy path:* a plugin-route install publishes the same eleven agents as `./setup`, from the generated flat directory rather than from `shared/agents/`; asserted as a set comparison against the repo-level route.
  - *Edge case:* the named agent **is** registered. The dispatch uses the registry and never reads the bundled copy, so the fallback cannot mask a broken registry publish.
  - *Error path:* a manifest still pointing `agents` at `shared/agents/` after this unit. A check fails, since that path is a build input and is absent from an installed plugin.
  - *Edge case:* two skills that both carry `repo-research.md` installed into the same profile. The registry ends with one copy, byte-identical to both sources, and the install is order-independent.
  - *Error path:* two skills carrying the same agent filename with different bytes. The parity test fails naming both skills, rather than the installer silently resolving it last-writer-wins.
  - *Error path:* an agent removed from `shared/agents/` while a skill still names it. The parity test fails naming both.
- **Verification:** parity test green; full-install agent set identical to the pre-change publish; the single-skill install test performs a real agent dispatch with no `shared/` present and passes.

### U8. Invert the anchor drift guard and strip the `$ENSEMBLE_ROOT` preamble

- **Goal:** The convention that is enforced becomes the new one, and the old preamble is gone.
- **Requirements covered:** G9, G13
- **Dependencies:** U3, U4, U6, U7, U11
- **Files:** `tests/lint/skill-helper-anchor.test.sh`, all 17 `skills/*/SKILL.md`
- **Approach:** `tests/lint/skill-helper-anchor.test.sh` currently enforces the opposite of the target state: 124 assertions requiring `$ENSEMBLE_ROOT` anchoring across 15 skills, plus a `**Helper resolution.**` preamble sentinel. Rewrite it to forbid `$ENSEMBLE_ROOT`, `../` traversal and absolute paths in skill files, and to require that every `references/X` and `scripts/Y` a skill names resolves inside that skill. Keep it warn-only through U3 to U7 so intermediate commits are not red, and flip it to fail here, once every skill has actually moved. Delete the preamble from all 17 skills. Nothing else: the SKILL.md truncation debt is out of scope for this plan and is filed by U12, so this high-risk unit stays reviewable and revertible on its own.
- **Risk:** high
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* the inverted guard passes against the migrated tree, with the same coverage breadth it had before (every skill, not a subset).
  - *Happy path:* no `**Helper resolution.**` preamble remains in any skill.
  - *Edge case:* a legitimate `../` inside skill prose that is not a helper path, such as `/en-build`'s worktree path `../<repo>-<id>/` or `en-guardrail`'s documented `../dist` counter-example. The guard matches helper-path context, not every occurrence of `../`, and both are asserted as allowed.
  - *Error path:* reintroducing a `$ENSEMBLE_ROOT/references/X` path into any skill. The guard fails naming skill and line.
  - *Error path:* a skill naming a reference it does not carry. The guard fails, which is the case the old preamble's fail-loudly probe used to catch at runtime.
  - *Negative control:* add a `$ENSEMBLE_ROOT` path to one skill on purpose, confirm red, then remove it.
- **Verification:** inverted guard green against the migrated tree and red against a deliberate reintroduction; zero `$ENSEMBLE_ROOT` occurrences under `skills/`; full suite green.

### U9. Remove the installer bridge

- **Goal:** `setup` stops installing shared helpers and the root shims come out, because nothing reads either any more.
- **Requirements covered:** G9
- **Dependencies:** U8
- **Files:** `setup`, `references` and `bin` root symlinks (removed), `tests/install/setup-shared-helpers.test.sh`
- **Approach:** Commit `3ef2151` added the shared-helper install and its probe as a bridge for the window in which skills still resolved `$ENSEMBLE_ROOT`. U2 added root `references` and `bin` symlinks for the same window. U8 closed it. Remove the shared-helper install loop, the `host-detect.md` probe, and both root symlinks, in that order, re-running the suite after each so a failure names which shim was still load-bearing. Do not simply delete the test: repoint it at the property that now matters, which is that a copied skill directory is self-sufficient on its own, with no sibling directory required. That keeps the regression coverage aimed at the same class of bug.
- **Risk:** high
- **Category:** removal
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** characterization-first
- **Test scenarios:**
  - *Happy path:* a copy-mode install into a temp HOME yields skill directories that resolve every reference and script they name, with no `references/` or `bin/` beside them.
  - *Happy path:* a symlink-mode install behaves the same, and the source checkout is no longer a runtime dependency: moving or renaming the checkout after a copy-mode install leaves the install working.
  - *Edge case:* a single skill directory copied on its own to an unrelated location still resolves everything it names. This is the property the whole plan exists to produce, so it is asserted directly.
  - *Error path:* `setup` still exits non-zero on a genuinely broken install rather than losing that signal along with the bridge.
  - *Negative control:* remove one generated reference from a skill copy and confirm the self-sufficiency assertion goes red.
- **Verification:** copy-mode and symlink-mode installs both self-sufficient; the single-skill copy test passes; `./setup --verify-only --quiet` exits 0; full suite green.

### U10. `CONTRACT.md` for the six callable skills

- **Goal:** A caller depends on a stated promise instead of on the callee's internals.
- **Requirements covered:** G9
- **Dependencies:** none
- **Files:** `skills/en-review/CONTRACT.md`, `skills/en-cross-review/CONTRACT.md`, `skills/en-plan/CONTRACT.md`, `skills/en-build/CONTRACT.md`, `skills/en-learn/CONTRACT.md`, `skills/en-simplify/CONTRACT.md`, `tests/lint/contract-shape.test.sh`
- **Approach:** One page per callee, hand-written and never generated, holding six things: accepted invocations with exact flag spellings; the non-interactive guarantee for `headless` and `report-only`; the return schema with closed enums and an explicit instruction that callers branch on those exact spellings; the authority envelope, which a callee may narrow but never widen; cost bounds, such as `report-only` never running a peer; and recursion posture under `ENSEMBLE_PEER_REVIEW=true`. `en-review` already behaves this way across all six; this unit turns internal notes into promises.

  A shape lint alone would prove only that six headings exist. Coverage and truthfulness need two more checks. **Coverage:** a call-graph check enumerates every `/en-*` invocation appearing in any skill, resolves each to its target skill, requires that target to carry a `CONTRACT.md`, and validates the invocation's flags against the contract's accepted set. That is what turns "six skills are callable" from a hand-count into a derived fact, and it fails when a seventh callee appears. **Truthfulness:** behavioral probes for the promises that are mechanically checkable from the existing suite, namely that `report-only` performs no mutation and starts no peer, that `headless` returns a parseable envelope whose status values are inside the contract's declared enum, and that `ENSEMBLE_PEER_REVIEW=true` suppresses the peer call. The authority-envelope and cost-bound clauses stay prose, since narrowing-not-widening is a property of every future change rather than of one run, and the enum cross-check plus the mutation probe already cover the parts that can go silently wrong.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* each of the six contracts carries all six required sections; the shape lint passes.
  - *Happy path:* the call-graph check enumerates every inter-skill invocation across all 17 skills and finds a contract for each target. The derived callee set equals the six named here, which is what confirms the hand-count.
  - *Happy path:* every status enum named in a contract matches the enum the skill actually emits, asserted against the skill body so the two cannot drift apart silently.
  - *Edge case:* a callable skill with a single mode still gets a contract, since the value is the promise, not the branching.
  - *Edge case:* a self-invocation such as `/en-build --from` is not treated as an inter-skill edge and does not demand a contract of itself.
  - *Error path:* a new invocation added to a skill whose target has no contract. The call-graph check fails naming caller, callee and line.
  - *Error path:* a caller passing a flag the callee's contract does not accept. The invocation check fails, which is the drift the closed-enum instruction exists to prevent.
  - *Error path:* `/en-review --mode report-only` mutating the tree or starting a peer. The behavioral probe fails, so the contract cannot promise something the skill does not do.
  - *Error path:* a contract missing the authority-envelope section. The shape lint fails naming the skill and the section.
- **Verification:** shape lint green for all six; call-graph check green with the derived callee set matching; enum cross-check green; `report-only` no-mutation, `headless` envelope-parse and recursion-suppression probes all green.

### U11. Validate and retire the zero-consumer references

- **Goal:** The three references nothing appears to read are each proven dead or given a home, with the evidence recorded.
- **Requirements covered:** G13
- **Dependencies:** U2
- **Files:** `shared/references/architecture-fitness.md`, `shared/references/core-beliefs-starter.md`, `shared/references/cli-wrappers.md`, `shared/manifest.json`
- **Approach:** Split out of U3 because the failure mode is different. A move that goes wrong leaves a dangling path that any resolution assertion catches; a deletion that goes wrong removes content with no way to notice until something reads it. Measured fan-in across `skills/` is zero for all three, but that count only sees skill files. Search the full tree, including `shared/bin/`, `tests/`, `.github/` and `docs/`, before touching any of them. `architecture-fitness.md` is already known to be read by `ensemble-lint`, so it is not dead: it stays in `shared/` and joins the manifest beside its reader. `core-beliefs-starter.md` and `cli-wrappers.md` are deleted only if the full-tree search is clean, and each deletion commit quotes the search that justified it.
- **Risk:** medium
- **Category:** removal
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** characterization-first
- **Test scenarios:**
  - *Happy path:* a full-tree consumer search runs for each of the three files and its result is recorded in the commit message, so a later reader can audit the deletion without re-deriving it.
  - *Happy path:* `architecture-fitness.md` stays reachable and `bash shared/bin/ensemble-lint --scope docs/` still exercises the fitness path.
  - *Edge case:* a file referenced only from a comment or a doc rather than executed. It counts as a consumer, so the file is kept and the reference is recorded rather than silently deleted.
  - *Error path:* deleting a file something still reads. The full suite plus the lint run catch it in the same commit, and the deletion is reverted rather than patched forward.
  - *Error path:* the search is skipped for one of the three. The unit is incomplete without a recorded search per file, which the commit-message check makes visible.
- **Verification:** full suite green; lint clean; one recorded consumer search per file; `architecture-fitness.md` still read by its reader.

### U12. File the SKILL.md truncation debt

- **Goal:** The Codex 8000-byte SKILL.md limit is recorded where it will be acted on, without riding along inside a high-risk migration unit.
- **Requirements covered:** G13
- **Dependencies:** none
- **Files:** `docs/plans/tech-debt-tracker.md`
- **Approach:** Codex injects only the first 8000 bytes of a SKILL.md, so a rule placed deep in a long body may never reach that host. `en-build` is 49K, `en-plan` 32K, `en-setup` 27K. Pre-existing and unrelated to path resolution, so it is declared out of scope above and gets its own doc-only unit rather than being fused into U8, where it would weaken atomic review and rollback of the riskiest change in the plan. Record the measured sizes and the mitigation shape (load-bearing rules move into an early-read reference, the way Compound Engineering routes `lfg` to `references/plan-brief.md` for exactly this reason).
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test expectation:** none — documentation-only; the entry's correctness is the measured byte counts, which the unit records at write time.
- **Verification:** a tracker entry exists naming the limit, the three oversized skills with current byte counts, and the mitigation shape; lint clean.

## Decisions, assumptions & risks

- **Decision:** duplicate scripts into skills rather than installing `bin/` as a PATH CLI. Duplication with a byte-parity test is a build-time invariant; a PATH install is a runtime one, exposed to PATH ordering, shadowing by an older copy, and version skew between an installed CLI and a skill expecting newer flags. It also keeps all 45 existing test files pointed at one canonical target. About 700K of repo growth is cheaper than that class of install bug.
- **Decision:** `shared/` is a rename, not just a marker. Leaving the canonical copies at `references/` and `bin/` would have avoided churn in 45 test files, but two root directories that look like runtime dependencies and are not is exactly the confusion that produced the original bug.
- **Decision:** agents are bundled additively, not moved. Host agent dispatch resolves `subagent_type` from a flat registry, so a move would break every dispatch. Bundling buys folder portability; the flat publish keeps dispatch working.
- **Alternative:** a shared `en-kit` skill that other skills read from. Rejected: it is a cross-skill file reference, which is the pattern this plan removes.
- **Alternative:** splitting this into two plans, mechanism then migration. Rejected: the half-migrated window is the main hazard, and one plan with a warn-only guard through U3 to U7 controls it better than a plan boundary would.
- **Assumption:** every target host resolves a bare relative read-time reference against the skill directory. Falsified cheaply by U4's resolution assertion plus one live invocation on each host; the Compound Engineering plugin relies on the same behavior across 33 skills, which is the strongest available evidence.
- **Assumption:** the three zero-consumer references are genuinely dead. U3 checks each before deleting and records the check.
- **Risk:** generated copies drift. **Mitigation:** the parity test exists before any content moves (U1), every generated file carries a do-not-edit header, and the failure message routes the author to the source rather than reporting a bare mismatch.
- **Risk:** the anchor conversion in U6 is where Compound Engineering logged three separate path bugs. **Mitigation:** its own unit, a smoke test run from an unrelated working directory, and a pattern assertion on the load-bearing trailing semicolon.
- **Risk:** a red intermediate commit while 17 skills migrate across five units. **Mitigation:** the anchor guard stays warn-only until U8 and flips only after every skill has moved.
- **Risk:** this plan touches well over 30 files, which normally triggers a split. **Mitigation:** the file count is concentrated in mechanical path rewrites across `tests/` and `skills/`, and the sequencing above is what makes it safe. Split by unit at review time, not by plan.
- **Risk:** merge conflicts against in-flight skill work, since the plan touches all 17 skills. **Mitigation:** `docs/plans/active/` is otherwise empty after EN01 and EN03 were closed, so schedule U3 to U8 when no large skill rewrite is open.

## Tracked debt

Filed by this plan, not resolved by it:

- SKILL.md bodies exceed the Codex 8000-byte injection limit (`en-build` 49K, `en-plan` 32K, `en-setup` 27K), so load-bearing rules deep in a body may never reach that host. Filed by U12.

## Iteration log

> - 2026-08-26 (initial): plan v0 from `docs/reviews/self-contained-skills-refactor.md`.
> - 2026-08-26 (iteration 2): cross-agent peer review (Codex). Verdict `revise`, three P1 and one P2;
>   all four applied, iteration cap reached. The sharpest was a contradiction inside iteration 1's own
>   fix: generated copies cannot both carry an injected header and be byte-identical to their source,
>   and for scripts that header would sit above the shebang. Generated-ness now comes from the manifest
>   and the warning lives in the canonical source. The agent fix from iteration 1 was also incomplete,
>   since a lone skill directory has no `setup` and the plugin manifests still pointed at `shared/`.
> - 2026-08-26 (iteration 1): cross-agent peer review (Codex). Verdict `revise`, four P1 and one P2.
>   All five applied. The two that changed the plan's shape: U2 gained a root-symlink
>   compatibility shim, because moving `references/` and `bin/` would otherwise delete the paths
>   unmigrated skills read; and U7 now publishes the flat agent registry from the skills
>   themselves, so bundled agents are actually dispatchable from a lone skill directory rather
>   than present but unread. U3 split, with zero-consumer deletion moved to a new U11.
