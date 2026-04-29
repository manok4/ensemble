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

`/en-ship` runs the scan as a pre-flight step:

```bash
# Gather staged diff
diff_text=$(git diff --cached)

# Run high-confidence patterns
violations=$(printf '%s' "$diff_text" | grep -nE '<concatenated-high-confidence-regexes>' || true)

if [ -n "$violations" ]; then
  echo "ERROR: potential secrets in staged diff." >&2
  printf '%s\n' "$violations" >&2
  echo "" >&2
  echo "If these are intentional (test fixtures, public examples), confirm with --allow-secrets." >&2
  exit 1
fi
```

`--allow-secrets` exists for legitimate cases (cryptographic test vectors, documentation examples that intentionally show key shapes). Use sparingly.

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
2. Update `bin/en-ship-secret-scan` (when implemented as a separate binary).
3. Add a test fixture under `tests/secret-scan/` with one match and one non-match.
4. Bump version in `package.json`; note in `CHANGELOG.md`.
