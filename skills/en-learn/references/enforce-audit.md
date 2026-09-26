# `--enforce-audit`

Read when `/en-learn --enforce-audit` runs. It applies `enforcement-layers.md` to
the rules a repo already keeps in prose, and files the ones that belong at L1 or
L2 and have no check yet. Use it once when adopting the router in a repo, and
again after a map file grows.

## Procedure

1. **Read the map files whole:** `AGENTS.md`, `CLAUDE.md` and `REVIEW.md` at the
   repo root, skipping any that do not exist. They are short by convention, so
   read them rather than searching them; a rule phrased without "never" or
   "must" is still a rule.
2. **List the rules.** A rule tells an agent to do or avoid something. Skip
   descriptions of how the code works, commands to run and pointers to other
   files.
3. **Confirm existing checks.** For a rule that names a test, lint config or
   script, open the cited file and confirm it rejects what the rule forbids. A
   confirmed rule is already enforced: skip it. A citation that does not hold
   leaves the rule in.
4. **Classify each remaining rule** with `enforcement-layers.md`. Only L1 and L2
   file an entry. A rule that already sits at its strongest layer (L3 project
   knowledge, say) needs nothing.
5. **File** each L1 or L2 rule through `scripts/ensemble-td-append`:
   `--source "en-learn --enforce-audit"`, `--location <file>:<line>` of the prose
   rule, the proposed check, and a rule key. Run `--list-keys` first and reuse
   the key of an open entry that describes the same rule; exit 4 means it is
   already tracked. That reuse is what makes a rerun file nothing new. Exit 1
   means the tracker is not in the canonical layout: file nothing and report
   every proposal in the table instead.
6. **Report** one table: rule, layer, proposed check, and the TD-ID or
   `exists TD<N>`.

The audit writes no learning files and edits nothing but the tracker. Building
the checks is ordinary work: a plan that cites the TD-IDs.
