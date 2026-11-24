---
project: report
type: foundation
status: active
created: 2026-11-24
updated: 2026-11-24
owner: eval
depth: lightweight
plan_id_prefix: RP
---

# report — Foundation

## 1. Strategy

<!-- strategy: author-approved 2026-11-24 -->

report exists so that a team can read its sales totals from a terminal and pipe them into other scripts. It serves the analysts and the scripts other teams own. It owns exactly one thing: turning data/sales.json into a regional summary.

### ST1. Output stays plain text

Every command prints plain text that a shell pipeline can parse. No colour codes, no interactive prompts.

### ST2. No network calls

The CLI reads local files only. It never opens a socket or calls a remote API.

### Scope

- Not a dashboard: no charts, no HTML output.
- Not a data fetcher: no live prices, rates or remote sources.

A change aligns when it makes the local summary easier to read or to parse.
A change should be resisted when it adds a network dependency.
