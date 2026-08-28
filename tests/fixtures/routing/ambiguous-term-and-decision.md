---
expect_type: term
expect_path: docs/CONTEXT.md
tie_break: term > decision
---
"Declaration closure" means a declared file may not name an undeclared one. We
adopted it after finding 90 gaps where a declared agent referenced a reference
nobody had listed.

Both a definition and a choice. The tie-break sends it to the term; the decision
that adopted it cites the term rather than redefining it.
