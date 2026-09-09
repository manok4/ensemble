# `/en-plan` failure protocol

Read when a run hits one of these; each row is the behavior, not a suggestion.

| Failure | Behavior |
|---|---|
| User declines the plan file, then asks to `/en-build` it | There is no file to build. Offer to write the plan now; do not synthesize one silently from the conversation, because it would carry no peer verdict and no hash. |
| Plan touches > 30 files | Warn about size; offer a split into several plans |
| Design doc matching the topic is `superseded` | Do not carry its decisions; treat the request as unexplored and apply the brainstorm soft-nudge. |
| Two units claim the same file with conflicting changes | A planning bug; don't write the plan |
| User accepts plan but peer review hasn't returned yet | Wait for the peer; on timeout write the plan without a verdict and say so in the report |
| Peer rejects the plan (verdict: reject) | Pause and surface the reject reason; leave `status: draft`. If the user explicitly overrides the rejection ("proceed anyway"), treat as approved: run the **status-flip step** (compute hash, flip `status: draft → open`, write `peer_review_verdict: reject` + a `peer_review_overridden: true` marker for audit) and continue to the **auto-commit step**. The valid post-flip status is **`open`** — `active/` is the directory the file lives in, not a status value. |
| Finalize loop hits iteration cap with `verdict: revise` | Surface latest findings; ask user "accept as-is and flip to `open`, or stay in `draft`?". User keeps control. |
| Re-review surfaces a finding the user previously disagreed with | Add it to the next prompt's "do not re-flag" list; a third appearance counts as the cap hit. |
| Auto-commit refused due to unrelated staged changes | Skip the commit and say so; the plan still flips to `open`, and `/en-build` pre-flight offers the commit next time. |
| A `risk: destructive` unit is ordered before a non-destructive one | Refuse to write. Surface the two units and the fix: move the destructive unit later, or raise the other's risk. |
| Plan-number collision | Re-scan, increment, retry; the lint catches a slip. |
| `bin/ensemble-lint` is not present in the project | Check frontmatter, per-unit `risk:` and the destructive ordering by hand; continue; say the lint is missing and that `/en-setup` installs it. |
