---
expect_type: decision
expect_path: docs/decisions/
tie_break: decision > solution
---
Grounding findings are advisory rather than a hard gate, because a solution doc
legitimately cites a path the fix deleted. We found this when the first cut
flagged 10 of 17 references in the repo.

Both a solved problem and a choice with a rule attached. The tie-break sends it
to the decision, whose invariant is that grounding never blocks a write.
