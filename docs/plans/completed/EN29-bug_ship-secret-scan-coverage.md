---
type: plan
plan_type: bug
plan_id: EN29
title: Scan every line a ship pushes, with remediation that works
status: completed
location: completed
created: 2026-11-10
shipped: 2026-11-11
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: revise
peer_review_iterations: 2
peer_review_last_run: 2026-11-10
peer_review_plan_hash: b4d9a009c13fe3591d6c84660f7dd93c739b39161069e4cf6a2fc37f845f1e94
peer_review_resolutions:
  - finding_id: 1-1
    iteration: 1
    severity: P1
    title: "Merge-created binary filenames escape both channels"
    status: applied
    location: U2
  - finding_id: 1-2
    iteration: 1
    severity: P1
    title: "Added-path transport leaves filename decoding unspecified"
    status: applied
    location: U2
  - finding_id: 2-1
    iteration: 2
    severity: P1
    title: "Root-commit patch coverage still depends on configuration"
    status: applied
    location: U2
  - finding_id: 2-2
    iteration: 2
    severity: P1
    title: "Per-commit patch command places diff options before the subcommand"
    status: applied
    location: U2
depth: standard
data_scale: small
---

# EN29 — Scan every line a ship pushes, with remediation that works

## Context

`/en-ship`'s secret scan was meant to cover the lines a push adds, but on `main` it ran `--staged`, which reads an empty index on the usual `push-existing` ship. That let every committed line through, as on PR #147 on 2026-11-10. Branch `fix-ship-secret-scan-range` already holds two commits. 3710ff1 and 14b9c00 add `--commits <a>..<b>`, make step 6 scan it, scan `--staged` at the end of step 7, stop on exit 2, and narrow `long-hex-string` so plan hashes do not warn. The `/en-fix` run stopped at its second review round with these findings still open:

- **P1, three sources:** `--no-merges` drops merge-resolution lines, and step 3 can create such merges.
- **P2:** a red-flag filename that arrives by a pure rename, or as a binary file, escapes the filename tier.
- **P2:** a finding in an earlier commit cannot be cleared by step 6's remedies, and the report names no commit.
- **P3:**
  - user git config can blind the parser;
  - non-UTF-8 bytes crash the scanner;
  - commit messages, the step-8 flip and the step-10 commit go unscanned;
  - already-pushed commits are rescanned on every re-ship.

The findings in round 2 sat inside round 1's fixes, which `docs/learnings/repeated-review-rejects-are-a-design-signal-2026-09-11.md` names as a design signal. This plan settles the coverage model once.

## Requirements covered

None from `docs/foundation.md`. This repairs `/en-ship`'s safety floor, the "secret-scan match" hard stop that D38 and the SKILL.md list.

## Out of scope for this plan

- New credential patterns, or changes to the HIGH, FILENAME or other HEURISTIC entries.
- Scanning the content of binary files. Only their names reach the filename tier.
- Rewriting history for the user. The scanner names the commit, and the user decides.
- How `/en-resolve-pr` and `/en-sweep` call the scanner. They keep `--staged` before their own commits, which is correct for them, and they only receive the byte-identical script.

## Approach (high-level)

**The coverage model.** A push sends commits, and each commit carries a patch and a message. Merges are included. So the scanner reads commits, not trees.

**Outgoing commits.** A new mode, `--outgoing <base-ref>`, lists the commits in `<base-ref>..HEAD` and splits them by whether any `origin` ref already contains them:

- **Unpushed commits** get the normal tiers. HIGH and FILENAME block, and HEURISTIC warns.
- **Commits already on the remote** report every match as `NOTICE` and never block or warn. Refusing the push cannot unexpose them; the user should rotate the key instead. That also stops confirmed warnings from re-prompting on every re-ship.

**What each commit contributes.**

- **The patch:** `git log -p --cc --no-renames`. `--cc` adds only a merge's own lines, the lines no parent has, so a conflict resolution is scanned and the base's lines are not rescanned. `--no-renames` turns a rename into a delete plus an add, so the new name and the full content are visible.
- **The message:** read separately and scanned under a synthetic path, `<commit-message>`.
- **Its added paths:** the paths the commit's tree has and none of its parents' trees have, read NUL-delimited from git (`git diff -z --name-only --diff-filter=A <parent> <commit>` per parent, intersected; `git diff-tree -z --root` for a root commit). The filename tier runs on them. This catches a binary file, which has no `+++` line, and a file that only a merge introduced.

**Attribution.** Every finding carries the short SHA of the commit that added it.

**Rendering.** Every git call pins its output: `--no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/`. User config such as `color.ui=always` or `diff.noprefix` can then neither blind nor confuse the parser. The diff is read as UTF-8 with `errors="replace"`, and any internal error exits 2. Exit 2 is "could not scan", which step 6 already treats as a stop, so a decode failure can no longer read as a credential.

**Where `/en-ship` scans.** Early and late, by your decision:

- **Step 6** runs `--outgoing origin/<base>` before any staging or commit, so a secret stops the run cheaply.
- **Step 7** keeps `--staged` on the final scope, so a secret is caught before `/en-ship` commits.
- **Step 11** runs `--outgoing origin/<base>` again immediately before `git push`. That covers what nothing else does: the step-8 plan flip, the step-10 commit and its message.

**Remediation by where the finding sits.**

- **A staged line:** `git restore --staged <file>` and fix it, or the per-line pragma. `--allow-secrets` stays possible here, sparingly.
- **An unpushed commit (`commit <sha>`):** rewrite that commit, by amend, or by rebase or squash with the user's approval, then re-run. `--allow-secrets` is not offered as the fix.
- **A NOTICE:** rotate the key. The push proceeds.

## Test seams

- **`ensemble-secret-scan` CLI** (existing seam): behavioural cases in `tests/lint/ensemble-secret-scan.test.sh` against fixture repos that the test builds, including a bare `origin` for the pushed and unpushed split.
- **`/en-ship` SKILL.md prose** (existing seam): wording pins in the same file, each with a negative control.
- **Parity** of the three script copies and four reference copies: `tests/parity/*`, unchanged.

## Technical design

Data flow for `--outgoing <base>`:

```
git rev-list <base>..HEAD                         → C (outgoing candidates, oldest first)
git rev-list <base>..HEAD --not --remotes=origin  → U (unpushed); C \ U = P (already on origin)
for each commit c in C:
  patch    = git log <pinned flags> --root -1 -p --cc --format= c   (patch paths C-unquoted)
  message  = git log -1 -z --format=%B c       → scanned as path "<commit-message>", line = message line
  added    = ∩ over parents p of: git diff -z --name-only --diff-filter=A --no-renames p c
             (root commit: git diff-tree -z --root -r --name-only --diff-filter=A c) → filename tier
  findings tagged commit=c[:7]; c in P → tier rewritten to "notice"
exit 1 iff any non-notice HIGH/FILENAME finding (and not --allow-secrets); 2 on any internal error
```

`--commits <a>..<b>`, which the branch added, becomes `--outgoing` without the remote split: every commit in the range gets normal tiers. Tests keep using it to exercise the walk with no remote.

## Implementation units

### U1. Pin git's rendering and make the scanner fail closed on its own errors

- **Goal:** Make no git config change what the scanner parses, and turn any internal failure into exit 2 rather than a phantom block.
- **Requirements covered:** none
- **Dependencies:** none
- **Files:**
  - `skills/en-ship/scripts/ensemble-secret-scan` (modify)
  - `skills/en-resolve-pr/scripts/ensemble-secret-scan` (modify)
  - `skills/en-sweep/scripts/ensemble-secret-scan` (modify)
  - `tests/lint/ensemble-secret-scan.test.sh` (modify)
- **Approach:**
  - **Pinned flags.** Define `GIT_DIFF_FLAGS="--no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ --no-renames"` once in the shell part and pass it to every `git diff` and `git log -p` call, always after the subcommand (`git diff $GIT_DIFF_FLAGS ...`, `git log $GIT_DIFF_FLAGS ...`), because these are subcommand options, not git global options. That covers the `staged`, `working`, `range` and `commits` modes. Also export `GIT_CONFIG_NOSYSTEM=1` and `GIT_PAGER=cat` for those calls.
  - **Decoding.** The Python part opens the diff with `encoding="utf-8", errors="replace"`.
  - **Exit codes.** The whole Python body sits in a `try:`. An unexpected exception prints `ensemble-secret-scan: internal error: <type>` to stderr and exits 2. The shell maps any Python exit other than 0 or 1 to 2.
  - **Copies.** Edit the en-ship copy, then copy it byte-identical to the other two.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a fixture repo with `git config color.ui always` and `color.diff always`, and an AKIA key staged. `--staged` exits 1 and names `aws-access-key-id`. Today the coloured `+` lines are invisible.
  - *Happy path:* the same with `git config diff.noprefix true`. The finding carries the real path, not `?`.
  - *Edge case:* a staged file holding Latin-1 bytes (`printf 'caf\xe9\n'`) and no secret. Exit 0, `secret-scan: clean`, no traceback.
  - *Error path:* the scanner run where `python3` gets a deliberately unreadable diff file, simulated by a `DIFF_FILE` override in the environment for the test only. It exits 2, never 1, and stderr says `internal error`.
  - *Edge case:* a staged rename `git mv env.txt .env` where `env.txt` was committed earlier. `--staged` blocks on `dotenv-file` because of `--no-renames`.
- **Verification:** `./tests/run.sh -k ensemble-secret-scan` and `./tests/run.sh -k script-parity` pass. Each new case is negative-controlled by removing its flag or handler.

### U2. Walk outgoing commits: merges, messages, added paths, attribution, pushed notices

- **Goal:** Make `--outgoing <base>` scan exactly what a push sends, name the commit behind every finding, and turn findings in already-pushed commits into notices.
- **Requirements covered:** none
- **Dependencies:** U1
- **Interfaces:**
  - *Produces:* `ensemble-secret-scan --outgoing <base-ref> [--remote <name>] [--allow-secrets] [--json]`, where `--remote` defaults to `origin`. `--commits <a>..<b>` remains, as the same walk with no remote split.
    - Each output line gains a trailing `commit <sha7>`. Message findings use the path `<commit-message>` and the message's own line number.
    - A new tier, `NOTICE`, is printed as `NOTICE` and never affects the exit code.
    - JSON gains `"commit"` on every finding and a `"notices": []` array beside `findings` and `warnings`.
    - Exit codes: 0 means no blocking finding in an unpushed commit, 1 means at least one, and 2 means usage error or internal error.
  - *Compatibility:* additive. `--staged`, `--working` and `--range` output is unchanged except for the absence of `commit`. Existing callers parse exit codes only.
- **Files:**
  - `skills/en-ship/scripts/ensemble-secret-scan` (modify)
  - `skills/en-resolve-pr/scripts/ensemble-secret-scan` (modify)
  - `skills/en-sweep/scripts/ensemble-secret-scan` (modify)
  - `tests/lint/ensemble-secret-scan.test.sh` (modify)
- **Approach:**
  - **Walk in Python, not shell.** The `commits` and `outgoing` modes do the walk inside the Python part, calling git through `subprocess.run([...], capture_output=True)` with an argument list. No line-record stream is built, so no path is ever re-parsed from a display form.
  - **Per commit.** For each SHA from `git rev-list --reverse <range>`:
    - **Patch.** Run `git log <pinned flags> --root -1 -p --cc --format= <sha>` (diff options after the subcommand; `--root` so `log.showRoot=false` cannot hide a root commit's patch) and feed it to the existing line parser with `current_commit = sha`.
      - In a `--cc` hunk, the header is `@@@ ... +n,m @@@` with one `@` per parent plus one. Lines whose marker columns, as many as there are parents, contain a `+` are added. Strip those columns before matching.
      - Patch paths go through a `c_unquote()` helper. When git quotes a path (`"b/dir\tx/.env"`), it reverses git's C-style escapes `\t \n \" \\` and octal `\NNN` bytes, decoded UTF-8 with `errors="replace"`. A path is never matched in its quoted display form.
    - **Message.** Run `git log -1 -z --format=%B <sha>`. Scan each line under path `<commit-message>`, numbered from 1.
    - **Added paths.**
      - For each parent `p` from `git rev-list --parents -n1 <sha>`, run `git -c core.quotePath=false diff -z --no-renames --name-only --diff-filter=A <p> <sha>`, split on NUL. Intersect the sets: a path is added only if no parent had it, which covers merges.
      - A root commit uses `git diff-tree -z --root -r --name-only --diff-filter=A <sha>`.
      - Run the filename tier on each path, de-duplicated against filename hits from the patch for the same commit and path.
  - **The remote split.** `--outgoing <base>` computes the range `<base>..HEAD` and the unpushed set `git rev-list <base>..HEAD --not --remotes=<remote>`. A finding whose commit is outside the unpushed set becomes `notice`.
  - **Remote state.** When `git rev-parse --verify refs/remotes/<remote>/HEAD` and every `refs/remotes/<remote>/*` are absent, so the branch has never been fetched or pushed, all commits count as unpushed.
  - **Copies.** Keep the three copies byte-identical.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* main and the branch both edit `f`. The branch merges main and resolves the conflict to the AWS documentation example key (the test file's `AKIA_FIXTURE`). `--commits main..HEAD` exits 1, and the finding names the merge commit's SHA.
  - *Happy path:* a commit whose message body contains `ghp_` followed by 36 characters. Exit 1, path `<commit-message>`.
  - *Happy path:* commit A adds `env.txt`, and commit B renames it to `.env`. `--commits` blocks on `dotenv-file`, attributed to B.
  - *Edge case:* a binary file `deploy.key` (made with `printf '\x00\x01'`) added in a commit. Blocks on `cert-or-key-file`.
  - *Edge case:* a merge that introduces a binary `deploy.key` present in neither parent, committed during `git merge --no-commit`. Blocks on `cert-or-key-file`, attributed to the merge commit.
  - *Edge case:* paths with unusual names: a binary `.env` under a directory named with a tab (`$'dir\tx'`), and a renamed `.env` under a directory named with a newline. Both block with the decoded real path in the finding, never a quoted display form.
  - *Edge case:* a merge of main into the branch that is clean, with no conflict, while main had added `password = "hunter2xyz"`. No finding: `--cc` does not rescan base lines.
  - *Integration:* a bare `origin`. Commit A has a hardcoded password and is pushed. Commit B is unpushed and clean. `--outgoing <base>` exits 0 with one `NOTICE ... commit <A>` line and no `WARN`. Adding an unpushed commit C with an AKIA key makes it exit 1, naming C.
  - *Edge case:* no remote-tracking refs at all. Every commit counts as unpushed.
  - *Edge case:* a repo with `git config log.showRoot false` and an outgoing root commit, from an unrelated history, that adds an AKIA key to an ordinary `cfg.txt`. `--commits` exits 1, attributed to the root commit.
  - *Integration:* the committed-secret scenario runs through the exact subprocess construction the walk uses. That proves the pinned options parse in their position after `log`.
  - *Error path:* `--outgoing nosuchref` exits 2.
- **Verification:** the same test commands as U1. The live EN28 range `--commits 0f311fa..45762f7` still shows only the planted fixture password, now with its commit.

### U3. Wire /en-ship to the coverage model and give each finding a remedy that works

- **Goal:** Make `/en-ship` scan outgoing commits early and once more right before the push, with remediation chosen by where the finding sits.
- **Requirements covered:** none
- **Dependencies:** U2
- **Files:**
  - `skills/en-ship/SKILL.md` (modify)
  - `skills/en-ship/references/secret-patterns.md` (modify)
  - `skills/en-debug/references/secret-patterns.md` (modify)
  - `skills/en-resolve-pr/references/secret-patterns.md` (modify)
  - `skills/en-sweep/references/secret-patterns.md` (modify)
  - `skills/en-ship/references/ship-failures.md` (modify)
  - `tests/lint/ensemble-secret-scan.test.sh` (modify)
- **Approach:**
  - **Step 6.** Change it to `--outgoing origin/<base>`. Keep the sentence about step 7's `--staged` scan.
  - **Remediation.** Replace step 6's Exit 1 bullet with a remedy by source: a staged line, `commit <sha>`, or `NOTICE`. These are the three bullets in the Approach above, and `--allow-secrets` is listed only for staged lines.
  - **Step 11.** Before `git push`, insert one line: `bash "$SKILL_DIR/scripts/ensemble-secret-scan" --outgoing origin/<base>`, handled as step 6 says. It covers the plan flip, the ship commit and its message. Exit 1 here stops before the push. The commit `/en-ship` just made stays local, and the report names `git reset --soft HEAD~1` as the user's way to unwind it. `/en-ship` never runs that itself.
  - **Size.** Keep the SKILL.md additions short. The file is at about 25.6 KB of a 26,624-byte budget, and `tests/lint/skill-size.test.sh` is the gate. Move detail into `references/secret-patterns.md`'s Usage section: the modes, the tiers including NOTICE, and the remedy table. Edit the four reference copies byte-identically.
  - **Failures table.** Update `references/ship-failures.md`'s secret-scan row to name the step-11 gate.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* the step-6 pin matches `ensemble-secret-scan" --outgoing origin/<base>`. The step-11 pin matches the pre-push line. Both go red when removed.
  - *Edge case:* step 6's remedy text names `commit <sha>` and says `--allow-secrets` is not the fix for it. Pinned.
  - *Error path:* `references/secret-patterns.md` documents `--outgoing`, `NOTICE` and the remedy table. Reference parity stays green across the four copies, and `skill-size` stays green.
- **Verification:** `./tests/select-for.sh` over the changed paths, then `./tests/run.sh` in full before the PR.

## Decisions, assumptions & risks

- **Decision:** early and final gates, by your choice. The final gate sits immediately before `git push`, the only point at which every outgoing line exists.
- **Decision:** only unpushed commits block, by your choice. Commits already on `origin` produce `NOTICE`s, because a refused push cannot unexpose them.
- **Decision:** `--cc` for merges, by your choice. It was verified on git 2.50.1 on 2026-11-10 to catch a key that exists only in a conflict resolution, and `--no-merges` missed it. It is available on every supported git.
- **Decision:** the step-7 `--staged` scan stays. It catches a staged secret before `/en-ship` makes a commit it would then have to ask the user to unwind.
- **Alternative:** the net diff (`--range`) alongside `--commits`. Rejected: it double-scans the same lines and still misses commit messages and binary names.
- **Assumption:** `git rev-list --not --remotes=origin` reflects what the push will send. That holds after step 3's `git fetch`. A remote that moved after the fetch can only reduce the set, which turns a would-block into a notice, so the result is never weaker than reality for commits we hold. A stale fetch is mitigated by step 3 fetching every ship.
- **Risk:** the `--cc` hunk parsing has more columns than a plain diff. **Mitigation:** dedicated merge tests, both the resolution case and a clean merge.
- **Risk:** a finding in an unpushed commit now needs history rewritten, which is harder for the user than restoring a file. **Mitigation:** the report names the commit, the remedy is stated by source, and `/en-ship` never rewrites history itself.

## Tracked debt

None.

## Iteration log

> - 2026-11-10 (initial): plan v0 from the stopped `/en-fix` run on `fix-ship-secret-scan-range`, which carries 3710ff1 and 14b9c00. Round 1 decisions: early and final gates, unpushed-only blocking, `--cc`. Research was the round-2 review findings plus a local `--cc` versus `--no-merges` reproduction; no research agents were dispatched, since the review had already read the code under change.
> - 2026-11-10 (peer pass 1, codex, revise): applied two P1s. Added paths are the tree paths no parent had, so merge-introduced binaries count. The walk moves into Python, using NUL-delimited git output and C-unquoted patch paths, with tests for tab and newline directory names.
> - 2026-11-10 (peer pass 2, codex, revise): applied two P1s. The patch reader passes `--root`, so `log.showRoot=false` cannot hide a root commit. The pinned diff options go after the subcommand, and the root-commit and real-invocation tests are added. The cap is reached.
