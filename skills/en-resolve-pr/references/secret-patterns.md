# Secret-scan patterns

Patterns `/en-ship` greps for in the staging diff before pushing. Any match → pause and require explicit user confirmation.

## High-confidence patterns

| Pattern | Matches |
|---|---|
| `AKIA[0-9A-Z]{16}` | AWS access key ID |
| `(?i)aws_secret_access_key\s*=\s*["']?[A-Za-z0-9/+=]{40}` | AWS secret access key |
| `ghp_[A-Za-z0-9_]{36,}` | GitHub personal access token |
| `gho_[A-Za-z0-9_]{36,}` | GitHub OAuth token |
| `ghu_[A-Za-z0-9_]{36,}` | GitHub user-to-server token |
| `ghs_[A-Za-z0-9_]{36,}` | GitHub server-to-server token |
| `xox[bpoa]-[0-9]+-[0-9]+-[0-9]+-[a-z0-9]{32}` | Slack token |
| `sk-[A-Za-z0-9]{20,}` | OpenAI / Anthropic API key style |
| `sk-ant-[A-Za-z0-9_-]{40,}` | Anthropic API key |
| `-----BEGIN (RSA |OPENSSH |EC |DSA |PGP )?PRIVATE KEY-----` | Private key block |
| `(?i)bearer\s+[A-Za-z0-9_\-\.=]{40,}` | Bearer tokens (JWT-shape) |

## File-name red flags

| Pattern | Notes |
|---|---|
| `\.env(\.|$)` | Any `.env`, `.env.local`, `.env.production` etc. (should be gitignored) |
| `id_rsa$`, `id_ed25519$` | SSH private keys |
| `\.pem$`, `\.key$` | Certificate / key files |
| `secrets?\.(json|ya?ml|toml)$` | Config files literally named "secrets" |
| `service-account.*\.json$` | GCP service account credentials |
| `credentials\.(json|ya?ml)$` | Credential dumps |

If a path matches → fail loudly. Suggest the user move it out of the diff (or add to `.gitignore` if it slipped in).

## Lower-confidence (heuristic) patterns

These match common keys/tokens but have false positives. Surface as warnings, not blockers — let the user decide.

| Pattern | Notes |
|---|---|
| `(?i)password\s*=\s*["'][^"']{6,}["']` | Hardcoded password assignment |
| `(?i)api[_-]?key\s*=\s*["'][^"']{16,}["']` | API key assignment |
| `(?i)secret\s*=\s*["'][^"']{16,}["']` | Generic "secret" assignment |
| `\b[A-Fa-f0-9]{40,64}\b` | Long hex strings (may be tokens, hashes, or just hex data) |

## Implementation

The `ensemble-secret-scan` helper that `/en-ship` bundles implements this table. **This file stays the source of truth for the list**, and `tests/lint/ensemble-secret-scan.test.sh` fails when a pattern documented here is missing from the scanner.

```bash
ensemble-secret-scan [--staged | --working | --range <a>..<b>] [--allow-secrets] [--json]
#  exit 0  no blocking match (warnings may still be reported)
#  exit 1  a high-confidence pattern or a red-flag filename matched
```

Three properties are worth knowing before changing it:

- **It never prints the credential.** Output is the pattern name, the path, the line and a preview masked after four characters. The sketch that used to live here was `grep -n`, which prints the matching line: that moves the secret from the diff into the terminal, the PR body and the transcript.
- **`grep -E` cannot do this table.** There is no portable inline case-insensitive flag, so every `(?i)` pattern above is silently case-sensitive in a hand-rolled scan. The helper uses Python's `re`.
- **Added lines only.** A credential already in history is a real problem and refusing this push does not fix it; blocking on it trains people to pass `--allow-secrets` by reflex.

`--allow-secrets` exists for legitimate cases (cryptographic test vectors, documentation examples that intentionally show key shapes). It **downgrades blocking matches to warnings**, never silences them. Use sparingly; the per-line pragma is narrower and reviewable.

## False-positive handling

When a high-confidence pattern matches but the content is intentional (e.g., a test fixture or doc example):

1. Wrap the match in a comment that signals intent: `# pragma: ensemble-allow-secret`.
2. The scan ignores lines containing that pragma.
3. `/en-ship` reports the count of pragma-suppressed matches in the secret-scan summary so the user is aware they exist.

Pragma example:

```python
TEST_AWS_ACCESS_KEY = "AKIAIOSFODNN7EXAMPLE"  # pragma: ensemble-allow-secret — AWS docs example
```

## What this scan does NOT replace

- **`.gitignore` discipline.** If `.env` isn't gitignored, fix that first.
- **Pre-commit hooks** that run the same scan on every commit (recommended for repos that ship).
- **Server-side scanning** by GitHub / GitLab. Their secret scanning catches what slipped through.

The `/en-ship` scan is a last-mile guard, not the primary defense.

## Updating patterns

When a new credential format emerges (a vendor changes their token shape):

1. Add the regex to this file.
2. Add it to the `ensemble-secret-scan` helper in the same order, so the two read as one list.
3. Add a case to `tests/lint/ensemble-secret-scan.test.sh` with one match and one non-match.
4. Copy the script byte-identical to every carrier (`tests/parity/script-parity.test.sh` checks this).
