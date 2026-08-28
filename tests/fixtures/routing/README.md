# Routing fixtures

Candidate → expected artifact type. Each file is one candidate that has already
passed the capture gate, with the type and path it should route to.

**These are not run by any shell test**, and that is deliberate. Routing is a
judgment executed by a model; no shell assertion reaches whether a model given a
candidate emits the right type. Claiming otherwise would be the decorative-guard
failure this plan's own gate warns about.

They exist for two real reasons:

1. They are the corpus a behavioural eval suite runs (**TD7**). Writing them now
   means that suite has inputs the day someone builds it.
2. They are the source of the worked examples in
   `skills/en-learn/references/artifact-types.md`, where they do measurable work
   as few-shot guidance to the model actually doing the routing.

Format: frontmatter carries `expect_type` and `expect_path`; the body is the
candidate as an agent would hold it at the end of a session.
