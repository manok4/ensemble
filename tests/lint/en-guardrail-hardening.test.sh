#!/usr/bin/env bash
# Drift guards for EN09 en-guardrail hardening: keep the docs (foundation D43,
# en-guardrail SKILL, en-setup, check-health) in sync with the SHIPPED matcher
# behavior. The behavioral guarantee lives in tests/en-guardrail/*.test.sh; this
# guard stops the prose/config from drifting away from what the hook does.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-guardrail hardening"

FOUNDATION="$REPO_ROOT/docs/foundation.md"
SKILL="$REPO_ROOT/skills/en-guardrail/SKILL.md"
HOOK="$REPO_ROOT/skills/en-guardrail/bin/check-guardrail.sh"
ANALYZER="$REPO_ROOT/skills/en-guardrail/bin/guardrail_analyze.py"
INSTALLER="$REPO_ROOT/skills/en-guardrail/bin/install-guardrail"
SETUP="$REPO_ROOT/skills/en-setup/SKILL.md"
HEALTH="$REPO_ROOT/scripts/check-health"

# --- foundation D43 exists and names the key facets ---
d43="$(grep -E "^- \*\*D43\." "$FOUNDATION" || true)"
if [ -n "$d43" ] && printf '%s' "$d43" | grep -qiE "en-guardrail"; then
  pass "foundation D43 records the en-guardrail hardening"
else
  fail "foundation must add D43 for the en-guardrail hardening"
  report
fi
if printf '%s' "$d43" | grep -qiE "positive allowlist" \
   && printf '%s' "$d43" | grep -qiE "MCP" \
   && printf '%s' "$d43" | grep -qF "ENSEMBLE_GUARDRAIL_BYPASS"; then
  pass "D43 names the positive allowlist + MCP matcher + hook-process-env bypass"
else
  fail "D43 must name the positive allowlist, the MCP matcher, and the env bypass"
fi
if printf '%s' "$d43" | grep -qF "D41" && printf '%s' "$d43" | grep -qF "D42"; then
  pass "D43 cross-references D41/D42's pattern"
else
  fail "D43 should cross-reference D41/D42"
fi

# --- the wrapper delegates to the analyzer + reads the env bypass ---
if grep -qF 'ENSEMBLE_GUARDRAIL_BYPASS' "$HOOK" && grep -qF 'guardrail_analyze.py' "$HOOK"; then
  pass "wrapper reads the env bypass and delegates to guardrail_analyze.py"
else
  fail "check-guardrail.sh must read ENSEMBLE_GUARDRAIL_BYPASS and call guardrail_analyze.py"
fi
# the wrapper must NOT re-introduce the inline-prefix bypass LOGIC (a comment
# explaining that it is gone is fine; a grep/case that acts on it is not).
if grep -qE '(grep|case).*ENSEMBLE_GUARDRAIL=off' "$HOOK"; then
  fail "wrapper still has inline ENSEMBLE_GUARDRAIL=off matching logic"
else
  pass "wrapper has no inline ENSEMBLE_GUARDRAIL=off bypass logic (comment-only ref is fine)"
fi
# --- the analyzer implements what the docs claim ---
[ -f "$ANALYZER" ] || { fail "guardrail_analyze.py missing"; report; }
# positive-allowlist safe exception (ARTIFACTS set + structural rm analysis)
if grep -qF "ARTIFACTS" "$ANALYZER" && grep -qF "rm_recursive_unsafe" "$ANALYZER"; then
  pass "analyzer implements the positive-allowlist rm analysis"
else
  fail "analyzer must implement the positive-allowlist rm analysis"
fi
# per-tool MCP adapter registry present
if grep -qF "ADAPTERS" "$ANALYZER" && grep -qF "mcp__Neon__run_sql" "$ANALYZER"; then
  pass "analyzer carries the MCP per-tool adapter registry"
else
  fail "analyzer must carry the MCP adapter registry"
fi
# non-recursive deleters + SQL/UPDATE/ORM + redirection + local-target parsing
analyzer_ok=1
for p in "rsync" "shred" "unlink" "redir_truncates" "update_no_where" "sql_from_uninspectable" "orm" "parse_target"; do
  grep -qF "$p" "$ANALYZER" || analyzer_ok=0
done
if [ "$analyzer_ok" -eq 1 ]; then
  pass "analyzer carries the deleter + SQL/UPDATE/ORM + target-parse logic"
else
  fail "analyzer missing one of the EN09 matchers"
fi

# --- installer registers the MCP matcher ---
if grep -qF "MCP_MATCHER" "$INSTALLER" && grep -qF "run_sql" "$INSTALLER"; then
  pass "install-guardrail registers the MCP DB-tool matcher"
else
  fail "install-guardrail must register the MCP matcher"
fi

# --- en-guardrail SKILL documents the shipped behavior ---
skill_ok=1
grep -qiE "positive allowlist" "$SKILL" || skill_ok=0          # relative-only exemption
grep -qiE "MCP database tools" "$SKILL" || skill_ok=0          # MCP coverage
grep -qF "ENSEMBLE_GUARDRAIL_BYPASS" "$SKILL" || skill_ok=0    # env bypass
grep -qiE "pattern-based accident brake|not a path sandbox" "$SKILL" || skill_ok=0  # A4/B4 framing
if [ "$skill_ok" -eq 1 ]; then
  pass "en-guardrail SKILL documents allowlist + MCP + env-bypass + scope framing"
else
  fail "en-guardrail SKILL must document the shipped EN09 behavior"
fi
# the SKILL must NOT still present the old inline-prefix bypass as the mechanism
if grep -qiE "honors .ENSEMBLE_GUARDRAIL=off. for the" "$SKILL"; then
  fail "SKILL still documents the obsolete inline ENSEMBLE_GUARDRAIL=off bypass"
else
  pass "SKILL no longer presents the inline-prefix bypass as the mechanism"
fi

# --- en-setup surfaces the MCP matcher + the env bypass ---
if grep -qiE "MCP DB-tool matcher|DB-writing MCP" "$SETUP" && grep -qF "ENSEMBLE_GUARDRAIL_BYPASS" "$SETUP"; then
  pass "en-setup surfaces the MCP matcher and the env bypass"
else
  fail "en-setup must surface the MCP matcher and the env bypass"
fi

# --- check-health reports the guardrail + MCP matcher status ---
if grep -qiE "en-guardrail hook" "$HEALTH" && grep -qF "mcp__" "$HEALTH"; then
  pass "check-health reports en-guardrail + MCP-matcher status"
else
  fail "check-health must report the guardrail + MCP-matcher status"
fi

report
