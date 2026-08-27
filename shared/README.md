# `shared/` — build input, not a runtime tree

Canonical text for anything two or more skills read. **Nothing here is read
while a skill runs** — that is the invariant this tree exists to protect, and
what makes each skill directory work on its own.

The plugin manifests do name `shared/agents` for their `agents` key. That is an
install-time read of where the canonical definitions live, in the same sense as
`"skills": "./skills"`, not a skill resolving a path at runtime. A generated
flat copy at the repo root existed briefly to avoid naming this directory at
all; it was a third identical copy of eleven files bought with nothing, so it
is gone.

Every skill directory under `skills/` is self-contained: it carries its own copy
of every reference, template, script and agent it reads, so the folder works
wherever it lands — a copied install, a versioned marketplace cache, a converter
that ships one skill on its own. That is only maintainable if there is still a
single place to edit, which is what this tree is.

```
shared/references/…   canonical text
shared/bin/…          canonical scripts (also the target the test suite runs against)
shared/agents/…       canonical agent definitions
shared/manifest.json  which skill receives which file
```

## Working here

Edit the file in `shared/`, then:

```bash
scripts/sync-shared
```

`scripts/sync-shared --check` verifies instead of writing and is what CI runs.
It fails when a generated copy drifts from its source, when a skill names a
relative path with no file behind it, and when the manifest grants a file to a
skill that never reads it.

## Two rules that look like details and are not

**Never edit a generated copy under `skills/`.** Change the file here and
re-run the sync. The parity check will catch it either way, but it costs you a
round trip.

**Nothing is injected into a generated copy.** Copies are byte-for-byte with
mode bits preserved, and `shared/manifest.json` is the only record of what is
generated. A "generated, do not edit" banner added at copy time would break byte
parity by construction, and in a script it would land above the shebang and stop
the file executing. Warnings therefore live *inside* the canonical file, below
the shebang, so they travel as part of the bytes.
