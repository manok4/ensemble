---
type: plan
plan_type: improvement
plan_id: EN09
title: en-guardrail hardening - close verified destructive-op gaps
status: completed
location: active
created: 2026-07-20
shipped: 2026-07-20
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: revise
peer_review_overridden: cap-hit-accepted-by-user
peer_review_iterations: 3
peer_review_last_run: 2026-07-20
peer_review_plan_hash: f1a30ee584b0e25d11693177e6b7ee21c221c46569cd5bb60c2630f3478ca517
peer_review_resolutions:
  - finding_id: EN09-F1
    iteration: 1
    severity: P1
    title: The filesystem marker is still a model-writable bypass
    status: applied
    location: bypass decision + Technical design + U3
  - finding_id: EN09-F2
    iteration: 1
    severity: P1
    title: MCP local-database exemption lacks trustworthy target context
    status: applied
    location: MCP matcher decision + Technical design + U4
  - finding_id: EN09-F3
    iteration: 1
    severity: P1
    title: U4 permits completion while the required MCP protection remains unsupported
    status: applied
    location: assumption + U4 acceptance criteria
  - finding_id: EN09-F4
    iteration: 1
    severity: P1
    title: SQL-from-file coverage omits common file and pipe forms
    status: applied
    location: Technical design SQL matrix + U2
  - finding_id: EN09-F5
    iteration: 2
    severity: P1
    title: Relative-path exemption still accepts shell-derived absolute targets
    status: applied
    location: Technical design safe-exception (positive allowlist) + U1
  - finding_id: EN09-F6
    iteration: 2
    severity: P1
    title: MCP target fields not proven to control the actual target
    status: applied
    location: MCP matcher per-tool adapters (controlling field) + U4
  - finding_id: EN09-F7
    iteration: 2
    severity: P1
    title: Global WHERE token check can allow mass UPDATE
    status: applied
    location: UPDATE check made statement-local + comment/literal-aware + U2
  - finding_id: EN09-F8
    iteration: 2
    severity: P1
    title: MCP matcher covers only a narrow subset of DB-writing tool names
    status: applied
    location: explicit maintained tool-family set + U4
  - finding_id: EN09-F9
    iteration: 2
    severity: P2
    title: Redirection handling does not specify existing-target check
    status: applied
    location: precise redirection contract (allow new / ask truncate) + U1
  - finding_id: EN09-F10
    iteration: 2
    severity: P3
    title: U3 goal still described the obsolete filesystem-marker mechanism
    status: applied
    location: U3 goal rewritten to hook-process env
  - finding_id: EN09-F11
    iteration: 3
    severity: P1
    title: Statement-local WHERE still accepts WHERE inside a subquery
    status: applied
    location: UPDATE check now requires a top-level (depth-0) WHERE + U2
  - finding_id: EN09-F12
    iteration: 3
    severity: P1
    title: Neon local-exemption test contradicted the controlling-field contract
    status: applied
    location: remote-only providers have no local exemption (Neon always ask) + U4
  - finding_id: EN09-F13
    iteration: 3
    severity: P1
    title: Host-support test could execute destructive SQL
    status: applied
    location: dispatch test uses a no-side-effect sentinel MCP tool + U4
  - finding_id: EN09-F14
    iteration: 3
    severity: P1
    title: Redirection contract did not define symlink handling
    status: applied
    location: symlink-aware canonicalization in the redirection contract + U1
  - finding_id: EN09-F15
    iteration: 3
    severity: P2
    title: Generic MCP tool-family names can prompt unrelated tools
    status: applied
    location: server-qualified adapter-backed exact identifiers + U4
depth: standard
data_scale: small
---

# EN09 - en-guardrail hardening: close verified destructive-op gaps

## Context

A review of Ensemble's destructive-operation guardrails (the `en-guardrail` PreToolUse hook, `skills/en-guardrail/bin/check-guardrail.sh`, plus the process-level gates) found real holes in the two threat classes the user cares about. The gaps were **empirically verified** by probing the live hook with crafted commands - each `GAP` below reproduced a silent pass where a prompt was expected.

**Threat A - deleting files outside the working folder / at root:**
- **A1 (sharpest):** the `rm -rf` safe-artifact exception whitelists **absolute** paths. `rm -rf /build` and `rm -rf ~/dist` pass **silently** because the case globs (`*/build|build|*/dist|dist|...`) match `/build` and `~/dist`. A "safe" exemption that greenlights filesystem-root and home-dir deletes.
- **A2:** only recursive `rm -r` is patterned. `rm /etc/hosts`, `find / -delete`, `rsync -a --delete`, `shred`, `truncate`, `> file` all pass silently.
- **A3:** the bypass prefix `ENSEMBLE_GUARDRAIL=off` is **model-writable** - an agent can prepend it to self-exempt (`ENSEMBLE_GUARDRAIL=off rm -rf /` passes silently).
- **A4:** no path-awareness - Ensemble never checks whether a target is inside the repo/allowed dirs. That boundary lives entirely in the host permission system; the hook is a pattern-based accident brake layered on top.

**Threat B - destructive ops on production DB/env:**
- **B1:** SQL routed through a file (`psql -f migrate.sql`) or stdin/heredoc is never scanned; a DROP inside the file sails through.
- **B2:** DB-writing MCP tools bypass the hook entirely - the matcher is `Bash`-only, so `mcp__Neon__run_sql` executing `DROP TABLE` never reaches the hook.
- **B3:** mass `UPDATE ... ` without `WHERE` is unpatterned; ORM/framework destroyers (`prisma migrate reset`, `rails db:drop`, `drizzle push`) are unpatterned.
- **B4:** "production" is inferred only by **exemption** (not-provably-local test/dev). There is no positive production detector, and `DELETE ... WHERE` on a prod host passes by design - so "always ask before ANY prod edit" is not the implemented behavior; "ask before pattern-matched catastrophic prod ops" is.

**What holds and must NOT regress** (also verified): `rm -rf /`, `DROP`/`TRUNCATE`/`DELETE`-without-`WHERE` on non-local DBs, `kubectl delete`, `terraform destroy`, `aws s3 rm --recursive`, `gcloud delete` all correctly prompt. The localhost+test/dev exemption requires BOTH signals (fails closed). The process-level gates (en-build `risk: destructive` typed-literal gate, `gated: true` prod-state prompt, en-ship safety floor) stay unchanged.

This follows the EN07/EN08 pattern (D41/D42): turn safety prose into mechanically-enforced, drift-tested behavior. Crucially, `check-guardrail.sh` **already has a real mechanical surface** with behavioral tests (`tests/en-guardrail/check-guardrail.test.sh`), so EN09 extends the matchers and the behavioral test suite - the tests ARE the guarantee - rather than adding prose.

## Decisions, assumptions & risks

- **Decision (user-confirmed intent, mechanism refined after peer review EN09-F1) - bypass is read from the hook's own process environment, not the command and not an agent-writable file (A3).** The user chose an "out-of-band token"; peer review proved a `~/.ensemble/` marker file is NOT out-of-band (the agent's Write/Edit tools can create it mid-session, so "instructed never to write it" is prose, not enforcement). The enforceable portable channel is a variable in the **hook process's own environment** (e.g. `$ENSEMBLE_GUARDRAIL_BYPASS`), which the human exports in their shell profile **before launching** Claude Code. The agent cannot mutate the already-running parent process's environment: setting `VAR=x` on a Bash command only affects that subprocess, and the hook reads its OWN `$ENSEMBLE_GUARDRAIL_BYPASS`, never the command text. The inline `ENSEMBLE_GUARDRAIL=off` prefix stops bypassing entirely. **Residual (documented, honest):** an agent could append an export to `~/.zshrc`, but that affects only *future* shells, not the running session's hook - so it cannot self-exempt within the session. A behavioral test proves an inline `ENSEMBLE_GUARDRAIL=off <cmd>` (and any command-level `VAR=` assignment) does NOT bypass. **Breaking change** to the inline-prefix bypass (acceptable pre-1.0; SKILL + en-setup document the new env-var mechanism). *(If you would rather remove the bypass entirely - the strictest option - say so; env-var-from-process is the strongest hatch-preserving choice.)*
- **Decision (user-confirmed) - add an MCP tool-name matcher for DB writes (B2); MCP local-exemption uses authoritative target metadata ONLY, never SQL text (refined after peer review EN09-F2).** A second `PreToolUse` matcher targets DB/infra-writing MCP tools (`mcp__*__run_sql*` and the like); the hook reads the SQL/statement from the tool's input schema and applies the destructive patterns. **The localhost+test/dev exemption is NOT applied from SQL text for MCP calls** (a SQL comment/literal could spoof `localhost`/`test`); it applies only when the tool's **authoritative target fields** (`project` / `branch` / `database` / `connection` / `environment`, per-tool) independently prove local test/dev. Default is `ask` for a destructive MCP statement whose target is not provably local. **B2 is a hard requirement, not best-effort (refined after peer review EN09-F3):** verified host support for the non-Bash MCP matcher AND an exercised matcher-dispatch test are U4 acceptance criteria - if the host cannot intercept these MCP tools, U4 (and EN09) is **blocked/incomplete**, not silently downgraded to Bash-only with a documented gap.
- **Decision - A1 fix anchors the safe-exception to relative, in-tree paths.** An absolute (`/...`), home (`~/...`, `$HOME/...`), or parent-escaping (`../`) target must NEVER hit the safe path; the artifact exemption applies only to a plain relative path whose final segment is a known build artifact (`node_modules`, `dist`, `.next`, ...). When in doubt, prompt (fail closed).
- **Decision - A4 and B4 are framed, not fully solved, in v1.** A4: the working-folder boundary is the **host permission system's** job; Ensemble's hook is an accident brake, documented as such (no path-sandbox reimplementation). B4: keep the fail-closed exemption model; the **optional positive production-marker** (a configurable `production_hosts` / `production_url_patterns` list that forces a prompt even for otherwise-unpatterned edits) is recorded as a **future extension**, not built in v1 (too project-specific to hardcode; the config surface is noted for discoverability).
- **Decision - all units `risk: low`.** Every change is additive matchers, a more-conservative exemption, a new opt-in MCP matcher, behavioral tests, and docs - reversible, no production/data impact. The mechanical safety guarantee is the behavioral test suite (a guardrail regression is caught there). Keeping all units `low` also satisfies the phase invariant (U5 depends on U1-U4). Matches EN06/07/08 precedent for self-referential tooling changes.
- **Assumption / hard gate - Claude Code supports a non-Bash `PreToolUse` matcher on MCP tool names.** The installer adds a matcher entry keyed to MCP tool-name patterns. Per EN09-F3 this is an **acceptance criterion, not a hope**: U4 must confirm the host actually intercepts a matching MCP tool call (exercised dispatch test) before U4 is considered done. If the host cannot, U4 and EN09 are **blocked/incomplete** and the gap is surfaced loudly - not documented as an acceptable Bash-only fallback (that would leave B2's explicit goal unmet while appearing complete). Existing Bash coverage remains regardless (additive).
- **Risk - a matcher bug silently WEAKENS protection.** *Mitigation:* every gap fix ships with behavioral test cases asserting BOTH the new `ask` and that prior `allow`/`ask` behavior is unchanged (regression guards for the "what holds" list). macOS bash 3.2 compatibility and the JSON-aware python command extraction are preserved.
- **Risk - over-broad matchers cause alert fatigue.** *Mitigation:* keep new patterns high-signal (destructive verbs only), preserve the local test/dev exemption for all SQL patterns, and prompt (never hard-block).

## Technical design

### Safe-exception anchoring (A1) - positive allowlist (refined EN09-F5)
The `rm -rf` artifact exemption is redefined as a **positive lexical allowlist**, not a denylist. A target qualifies for the exemption ONLY if it is a **literal, plain relative path** whose final segment is a known artifact - meaning it contains NONE of: a leading `/`, a leading `~`, any shell expansion or substitution (`$`, `${...}`, `$(...)`, backticks), any glob metacharacter (`*`, `?`, `[`), any quoting, or a `..` segment. Anything else (absolute, home, `${HOME}/dist`, `$PWD/dist`, `$(pwd)/dist`, globbed, quoted, parent-escaping) does NOT match the exemption and falls through to the recursive-rm prompt. Fail closed: if a target can't be proven a literal in-tree relative path, prompt. Implemented as a positive check in the existing `SAFE_ONLY` loop.

### Non-recursive deleters (A2), with a precise redirection contract (refined EN09-F9)
Add high-signal matchers (prompt): `find ... -delete` / `find ... -exec rm`, `rsync ... --delete`, `shred`, `truncate -s 0`, and bulk `unlink`. For **output-redirection truncation** (`>`, `: >`) the contract is explicit to avoid alert fatigue: resolve the redirect target against cwd with **symlink-aware canonicalization** (refined EN09-F14), handling quoting, file-descriptor forms (`2>`, `&>`), and multiple redirections; **ALLOW** creating a new file; **ASK** when truncating an existing regular file OR when the target is a symlink that resolves to an existing file (redirection follows symlinks, so a symlink can truncate a file outside the working folder); **fail closed (ask)** when the target can't be safely canonicalized (expansion/substitution, symlink chain, broken symlink, unparseable). Keep the existing recursive-rm matcher.

### SQL from file/stdin + more SQL verbs (B1, B3)
Fail closed whenever a DB client command carries SQL the hook cannot inspect, against a non-local target. The **supported client-syntax matrix** (per EN09-F4) covers: short and long file flags (`-f <file>`, `--file=<file>`, `-f<file>`), input redirection (`< <file>`), heredocs (`<<`), piped stdin (`... | psql`, `cat x | mysql`), and client-specific file/execute commands (`psql \i` / `\.` , `mysql source`, `-e/--execute` pointing at a file). Any of these against a target that is NOT the local test/dev exemption → **prompt**. Add matchers for `UPDATE ... ` without `WHERE` and the common ORM destroyers (`prisma migrate reset`, `rails db:drop|db:reset`, `drizzle-kit push` with data-loss, `sequelize db:drop`), all under the same local test/dev exemption. A form the matrix does not recognize but that clearly invokes a DB client with a file/pipe defaults to `ask` (fail closed), not `allow`. **The UPDATE-without-WHERE check is statement-local, comment/literal-aware, and top-level-scoped (refined EN09-F7, F11):** before deciding, strip SQL comments (`--...`, `/* ... */`) and quoted string literals, split into statements on top-level `;`, and require a **top-level `WHERE`** that belongs to the outer `UPDATE` - determined by a quote-aware, parenthesis-depth-aware scan so a `WHERE` nested inside a `SET (...)` / `FROM (...)` subquery or a CTE (parenthesis depth > 0) does NOT count. A scoped outer `WHERE` (depth 0) stays `allow`; an unscoped mass UPDATE whose only `WHERE` is in a subquery / comment / literal / later statement → `ask`.

### MCP tool-name matcher (B2) - explicit adapter set, controlling-field exemption (refined EN09-F6, F8)
`install-guardrail` adds a second `PreToolUse` entry matching DB/infra-writing MCP tools. Coverage is an **explicit, server-qualified, adapter-backed identifier list** (refined EN09-F8, F15), NOT generic `query`/`execute` across all `mcp__*` (which would intercept unrelated tools and add prompt fatigue): the installer registers the exact supported tool identifiers (or a narrow provider-specific pattern) for each destructive-capable DB family - e.g. `mcp__Neon__run_sql`, `mcp__Neon__run_sql_transaction`, `mcp__Neon__prepare_database_migration`, and the equivalents for other supported servers. **A destructive-capable DB tool family required by B2 that has no adapter is a build-time COVERAGE FAILURE (blocks U4)**, not something to catch by matching every generic tool name at runtime. `check-guardrail.sh` uses **per-tool adapters** (refined EN09-F6): each supported tool declares (a) the field carrying the statement and (b) the *controlling target field* that actually selects the execution target. The local test/dev exemption is granted ONLY when that controlling field is present, validated, and independently proves BOTH local AND test/dev. **Remote-only providers have no local exemption (refined EN09-F12):** a cloud DB like Neon cannot be `localhost`, so a destructive statement via a Neon tool ALWAYS `ask`s; the local exemption exists only for tools whose controlling fields can authoritatively prove a local target (e.g. a local-Postgres MCP). A local-looking value in a non-controlling / incidental field never exempts, and neither does SQL text. Write-name-matched tool with no adapter, or any unresolved case → `ask` (fail closed). **Host-support gate (EN09-F3, F13):** the build MUST confirm the host honors the non-Bash MCP matcher via a **disposable sentinel MCP tool that records invocation WITHOUT executing SQL** - assert PreToolUse intercepts the destructive-looking payload AND the sentinel body never ran; the dispatch test NEVER targets a real database (that would make U4 destructive and break its `gated:false` classification). If the host doesn't honor the matcher, U4/EN09 is blocked, not downgraded.

### Bypass via hook-process env var (A3)
Remove the inline `ENSEMBLE_GUARDRAIL=off` command-prefix check entirely. The hook instead consults its OWN process environment (`[ "${ENSEMBLE_GUARDRAIL_BYPASS:-}" = "on" ]` or a shared secret value), which the human exports in their shell profile before launching Claude Code. Because the hook reads its inherited process env - not the command string, and not an agent-writable file - a command-level `VAR=value <cmd>` assignment (which only scopes the subprocess) cannot activate it, and neither can the agent's file tools within the session. Residual: editing `~/.zshrc` affects only future shells. SKILL + en-setup document the env-var mechanism and that the old inline prefix no longer bypasses.

## Out of scope (deliberately)

- **A path-sandbox reimplementation** (A4) - the host permission system owns the working-folder boundary; the hook stays a pattern brake.
- **A positive production detector / `production_hosts` config** (B4) - recorded as a future extension, not built in v1.
- **Blocking (vs prompting)** - the hook always emits `ask`, never hard-denies; consistent with today's contract.
- **Changing the process-level gates** (en-build `risk: destructive` / `gated: true`, en-ship safety floor) - unchanged.

## Implementation units

### U1. Safe-exception anchoring + non-recursive deleters (A1, A2)

- **Goal:** The `rm -rf` artifact exemption applies ONLY to relative in-tree paths (absolute/home/parent-escaping always prompt); add high-signal matchers for the common non-recursive destructive deleters.
- **Requirements covered:** none (addresses threat-A gaps A1, A2).
- **Dependencies:** none.
- **Files:** `skills/en-guardrail/bin/check-guardrail.sh`, `tests/en-guardrail/check-guardrail.test.sh` (extend).
- **Approach:** Redefine the `SAFE_ONLY` exemption as a **positive allowlist** (EN09-F5): a target is exempt ONLY if it is a literal plain relative path (final segment a known artifact) with NO leading `/` or `~`, NO shell expansion/substitution (`$`, `${}`, `$()`, backticks), NO glob metacharacter (`*`/`?`/`[`), NO quoting, and NO `..` segment; anything else falls through to the recursive-rm prompt. Add matchers (each emits `ask`): `find` with `-delete` or `-exec rm`, `rsync --delete`, `shred`, `truncate -s 0`, bulk `unlink`, and `>`/`: >` truncation with the precise contract (EN09-F9): resolve the redirect target (quoting, fd forms, multiple redirects), ALLOW new-file creation, ASK truncation of an existing regular file, fail closed (ask) when unresolvable. Preserve bash 3.2 compatibility.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Happy path (regression): `rm -rf node_modules`, `rm -rf ./dist`, `rm -rf build/` still `allow` (relative artifacts). (test asserts allow)
  - Error path (A1 fix): `rm -rf /build`, `rm -rf ~/dist`, `rm -rf $HOME/.cache`, `rm -rf ../dist`, and the shell-expansion forms `rm -rf ${HOME}/dist`, `rm -rf $PWD/dist`, `rm -rf "$(pwd)/dist"` now `ask` (EN09-F5: expansion/substitution never exempts). (test asserts ask)
  - Error path (A2 delete verbs): `find / -name x -delete`, `rsync -a --delete src/ dst/`, `shred secret`, `truncate -s 0 db.sqlite`, bulk `unlink` now `ask`. (test asserts ask)
  - Redirection contract (A2, EN09-F9): truncating an existing regular file (`> existing.log` where the file exists) `ask`s; creating a new file (`> brand-new.log`) `allow`s; an unresolvable target `ask`s. (test creates a temp file to exercise both branches)
  - Redirection symlinks (A2, EN09-F14): `> link` where `link` is a symlink to an existing file (in-tree or out-of-tree) `ask`s; a broken symlink or symlink chain that can't be canonicalized `ask`s (fail closed). (test builds symlinks in a temp dir)
  - Regression (must not break): `rm -rf /` still `ask`; a plain `ls` / `git status` still `allow`. (test asserts unchanged)
- **Verification:** `bash tests/en-guardrail/check-guardrail.test.sh` passes (ends with `report`); `bash tests/run.sh` green.

### U2. SQL-from-file/stdin fail-closed + UPDATE-no-WHERE + ORM resets (B1, B3)

- **Goal:** A DB command that reads SQL the hook can't see (`-f`, `<`, heredoc) against a non-local target prompts; add matchers for `UPDATE` without `WHERE` and common ORM destroyers - all under the existing local test/dev exemption.
- **Requirements covered:** none (addresses threat-B gaps B1, B3).
- **Dependencies:** none.
- **Files:** `skills/en-guardrail/bin/check-guardrail.sh`, `tests/en-guardrail/check-guardrail.test.sh` (extend).
- **Approach:** Detect DB-client invocations (`psql`/`mysql`/`mongosh`/etc.) that carry SQL the hook can't inspect across the full matrix (EN09-F4): `-f <file>` / `--file=<file>` / `-f<file>`, input redirection `< <file>`, heredocs (`<<`), piped stdin (`... | psql`, `cat x | mysql`), and client file/execute commands (`\i` / `\.` / `source` / `-e|--execute <file>`). If the target is not the local test/dev exemption, emit `ask` ("SQL from file/stdin/pipe can't be inspected"); an unrecognized file/pipe form still defaults to `ask` (fail closed). Add `UPDATE <table> ... ` without `\bwhere\b` and ORM patterns (`prisma migrate reset`, `rails db:drop`, `rails db:reset`, `drizzle-kit push`, `sequelize db:drop`) to the matcher list, each honoring `is_local_test_db`.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Error path (B1, full matrix): `psql -h prod.db -f migrate.sql`, `psql -h prod.db --file=migrate.sql`, `psql -h prod.db < migrate.sql`, and `cat migrate.sql | psql -h prod.db` all now `ask`; each equivalent against `-h localhost -d appdev` stays `allow`. (test asserts each form)
  - Error path (B3): `psql -h prod.db -c "UPDATE users SET active=false"` (no WHERE) now `ask`; `... WHERE id=1` stays `allow` (scoped). (test asserts)
  - Error path (B3, EN09-F7/F11 scope guard): an unscoped mass UPDATE whose only `WHERE` is in a comment (`... -- reset WHERE nobody`), a string literal (`SET note='delete WHERE x'`), a later statement (`UPDATE ...; SELECT ... WHERE y=2`), OR a **subquery** (`UPDATE users SET active=(SELECT enabled FROM defaults WHERE id=1)` - no top-level WHERE) all `ask`; a genuinely scoped `UPDATE users SET x=1 WHERE id=2` stays `allow`. (test asserts each; the subquery case requires the parenthesis-depth-aware top-level scan)
  - Error path (B3 ORM): `prisma migrate reset --force`, `rails db:drop`, `drizzle-kit push` now `ask`; exempt when clearly against a local test/dev target. (test asserts)
  - Regression: existing `DROP`/`TRUNCATE`/`DELETE`-no-WHERE prod prompts and local exemptions unchanged. (test asserts unchanged)
- **Verification:** `bash tests/en-guardrail/check-guardrail.test.sh` passes; `bash tests/run.sh` green.

### U3. Bypass hardening via out-of-band token (A3)

- **Goal:** Remove the model-writable inline bypass; the hook honors a bypass ONLY from its own inherited process environment (`ENSEMBLE_GUARDRAIL_BYPASS`), which the human exports before launching - never from the command string and never from an agent-writable file (EN09-F1, F10).
- **Requirements covered:** none (addresses threat-A gap A3).
- **Dependencies:** none.
- **Files:** `skills/en-guardrail/bin/check-guardrail.sh`, `skills/en-guardrail/SKILL.md`, `tests/en-guardrail/check-guardrail.test.sh` (extend).
- **Approach:** Delete the inline `ENSEMBLE_GUARDRAIL=off` command-prefix check. The hook instead reads its OWN process environment (`ENSEMBLE_GUARDRAIL_BYPASS`); when set to the enabling value it allows the command through. Because this is the hook process's inherited env (set by the human in their shell before launch), a command-level `VAR=value <cmd>` assignment cannot reach it and the agent cannot mutate the running parent process env. Document the env-var mechanism, the residual (`~/.zshrc` edits affect only future shells), and the breaking change in SKILL.md.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Error path (A3 fix, EN09-F1): `ENSEMBLE_GUARDRAIL=off rm -rf /` now `ask`; a command-level `ENSEMBLE_GUARDRAIL_BYPASS=on rm -rf /somedir` also `ask` (a command-string assignment must NOT bypass - the hook ignores command text). (test asserts ask for both)
  - Happy path: with `ENSEMBLE_GUARDRAIL_BYPASS=on` exported into the hook's OWN environment (test runs the hook with that env set), a matched destructive command `allow`s; with it unset, the same command `ask`s. (test asserts both, setting the var on the hook process, not in the command)
  - Regression: no marker/env → all existing prompts unchanged. (test asserts)
- **Verification:** `bash tests/en-guardrail/check-guardrail.test.sh` passes; `bash tests/run.sh` green.

### U4. MCP tool-name matcher for DB writes (B2)

- **Goal:** DB/infra-writing MCP tools are covered by the guardrail: a second PreToolUse matcher (an explicit, maintained tool-family set, EN09-F8) routes them to the hook, which reads the statement AND the controlling target field via per-tool adapters (EN09-F6) and applies the same destructive patterns, exempting local test/dev only from authoritative target metadata.
- **Requirements covered:** none (addresses threat-B gap B2).
- **Dependencies:** none.
- **Files:** `skills/en-guardrail/bin/check-guardrail.sh`, `skills/en-guardrail/bin/install-guardrail`, `tests/en-guardrail/check-guardrail.test.sh` (extend), `tests/en-guardrail/install-guardrail.test.sh` (extend).
- **Approach:** In `check-guardrail.sh`, add **per-tool adapters** (EN09-F6): a small table mapping each supported MCP tool to (a) its statement field (`sql` / `params.sql` / `statement` / `query`) and (b) its *controlling target field* (the input that actually selects the execution target, e.g. Neon `project`/`branch`). Resolve the statement and run it through the destructive-pattern matchers; grant the local test/dev exemption ONLY when the controlling target field is present, validated, and independently proves BOTH local AND test/dev - never from SQL text, never from an incidental local-looking field. A destructive statement whose target isn't independently proven local → `ask`; a write-name-matched tool with no adapter, or unresolvable input → `ask` (fail closed). In `install-guardrail`, add a second `PreToolUse` entry whose matcher is the **explicit maintained tool-family set** (EN09-F8: `run_sql`, `run_sql_transaction`, `query`, `execute`, `run_query`, `execute_sql`, `apply_migration`/`prepare_database_migration`, provider mutators) plus the documented conservative naming policy, via the existing JSON-aware merge. **Host-support acceptance gate (EN09-F3):** confirm the host actually intercepts a matching MCP call (exercised dispatch test) AND that a destructive MCP statement is caught end-to-end; if the host does not honor the non-Bash matcher, U4/EN09 is **blocked** and surfaced - NOT silently downgraded to Bash-only.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Happy path (remote-only provider, EN09-F12): `mcp__Neon__run_sql` `{"sql":"DROP TABLE users","project":"prod-app"}` → `ask`; because Neon is cloud-only it has NO local exemption, so `{"sql":"DROP TABLE users","project":"dev-sandbox"}` ALSO `ask`s (a Neon call is never localhost). The local `allow` case is exercised via a local-target adapter (e.g. a local-Postgres MCP whose controlling field proves `localhost` + test/dev) → `allow`. (tests use each tool's real controlling fields)
  - Error path (EN09-F2 spoof guard): `{"sql":"DROP TABLE users -- localhost test","project":"prod"}` → `ask` (local-looking words INSIDE the SQL do NOT exempt). (test asserts ask)
  - Error path (EN09-F6 controlling-field conflict): an incidental local-looking field alongside a prod controlling field, e.g. `{"sql":"DROP TABLE users","label":"localhost-test","project":"prod-app"}` → `ask` (only the controlling `project` field decides). (test asserts ask)
  - Coverage (EN09-F8): a destructive statement via `mcp__X__execute` / `mcp__X__apply_migration` (not just `run_sql`) is matched. (test asserts ask)
  - Edge: `tool_input.params.sql` nesting resolves; a write-name-matched tool with no adapter, and any unresolvable write-tool input → `ask`. (test asserts)
  - Integration (installer): `install-guardrail install-project` writes BOTH the Bash matcher and the MCP tool-name matcher; JSON merge preserves existing hooks; idempotent re-run. (install test asserts)
  - Host-support gate (EN09-F3, F13): a build-time check confirms the host dispatches the MCP matcher to the hook using a **disposable sentinel tool that records invocation without executing SQL** - assert PreToolUse intercepted the destructive-looking payload AND the sentinel body never ran; never targets a real DB. A failing dispatch blocks U4 rather than passing with Bash-only coverage. (sentinel dispatch test)
  - Regression (EN09-F15): a generic non-DB MCP tool (`mcp__foo__read`, and an unrelated `mcp__bar__execute` that is not a registered DB adapter) is NOT matched / not prompted. (test asserts allow)
- **Verification:** `bash tests/en-guardrail/check-guardrail.test.sh` + `bash tests/en-guardrail/install-guardrail.test.sh` pass; the sentinel host-support dispatch check passes (else U4 blocked); `bash tests/run.sh` green.

### U5. Foundation D43 + SKILL / pattern-list sync + en-setup / check-health surfacing

- **Goal:** Record decision D43, sync the en-guardrail SKILL pattern list + safe-exception + bypass docs, and surface the new bypass marker and MCP matcher in en-setup / check-health.
- **Requirements covered:** none (decision record + doc sync).
- **Dependencies:** U1, U2, U3, U4.
- **Files:** `docs/foundation.md`, `skills/en-guardrail/SKILL.md`, `skills/en-setup/SKILL.md`, `scripts/check-health`, `tests/lint/en-guardrail-hardening.test.sh` (new).
- **Approach:** Add **D43** after D42: the verified gap classes, the fixes (relative-only safe-exception, non-recursive deleters, SQL-from-file fail-closed, UPDATE-no-WHERE + ORM, out-of-band bypass token, MCP tool-name matcher), the A4/B4 framing (host owns the path boundary; positive production-marker is a future extension), and a cross-reference to D41/D42's prose-to-auditable-gate pattern. Update the en-guardrail SKILL's "Patterns flagged" / "Safe exceptions" / "Per-command bypass" sections to match the shipped behavior. Add the MCP matcher + bypass-marker to en-setup's guardrail install/status and `scripts/check-health`. New drift test asserts SKILL/foundation/en-setup are in sync with the shipped matchers.
- **Risk:** low
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: foundation D43 names the gap classes + the fixes + the future-extension framing; cross-references D41/D42. (drift guard asserts)
  - Integration: en-guardrail SKLL "Per-command bypass" section documents the out-of-band marker (not the inline prefix) and instructs the agent never to write it; "Safe exceptions" documents relative-only. (drift guard asserts)
  - Integration: en-setup + check-health surface the MCP matcher and bypass-marker status. (drift guard asserts)
  - **Test expectation:** covered by the drift guard above - this is a decision-record + doc-sync unit.
- **Verification:** `tests/lint/en-guardrail-hardening.test.sh` passes (ends with `report`); `bin/ensemble-lint --scope docs/` exit 0; foundation shows D43.

## Verification (whole plan)

- `bash tests/run.sh` - full suite green (extended `check-guardrail.test.sh` + `install-guardrail.test.sh`; new `tests/lint/en-guardrail-hardening.test.sh`).
- `bin/ensemble-lint --scope docs/` - exit 0.
- Manual re-probe (the original 12-command probe set): A1/A2/A3/B1/B2/B3 cases now `ask`; the "what holds" set still `ask`; local test/dev exemptions still `allow`.
- Branch-level cross-agent review at build completion (D35/D41), `review-verdict:` + `simplify-verdict:` trailers, `--require-simplify` audit green.
