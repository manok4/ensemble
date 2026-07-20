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

# --- the hook actually implements what the docs claim ---
# positive-allowlist safe exception (not the old bare-name globs)
if grep -qiE "positive allowlist" "$HOOK"; then
  pass "hook implements a positive-allowlist safe exception"
else
  fail "hook must implement the positive-allowlist safe exception"
fi
# bypass is read from the hook's OWN env, and the inline prefix grep is gone
if grep -qF 'ENSEMBLE_GUARDRAIL_BYPASS' "$HOOK" \
   && ! grep -qE "grep -qE '\(\^\|\[\[:space:\]\]\)ENSEMBLE_GUARDRAIL=off" "$HOOK"; then
  pass "hook reads bypass from its process env; inline-prefix grep removed"
else
  fail "hook must read ENSEMBLE_GUARDRAIL_BYPASS from env and drop the inline-prefix check"
fi
# per-tool MCP adapter registry present
if grep -qF "ADAPTERS" "$HOOK" && grep -qF "mcp__Neon__run_sql" "$HOOK"; then
  pass "hook carries the MCP per-tool adapter registry"
else
  fail "hook must carry the MCP adapter registry"
fi
# non-recursive deleters + UPDATE-scope patterns present
deleters_ok=1
for p in "rsync" "shred" "truncate" "unlink" "redir_truncates_existing" "update_no_where" "sql_from_file" "orm_destructive"; do
  grep -qF "$p" "$HOOK" || deleters_ok=0
done
if [ "$deleters_ok" -eq 1 ]; then
  pass "hook carries the non-recursive deleter + SQL/UPDATE/ORM matchers"
else
  fail "hook missing one of the EN09 deleter/SQL matchers"
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
