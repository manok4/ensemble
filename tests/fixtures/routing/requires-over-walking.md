---
expect_type: decision
expect_path: docs/decisions/
---
We chose explicit `requires:` declarations over inferring each skill's file set
by walking its references. The walker produced five distinct classes of false
edge, each found only by deleting something and seeing what broke. Every file a
skill reads is now declared, and a declared file naming an undeclared one is a
hole.
