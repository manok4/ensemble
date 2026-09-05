#!/usr/bin/env bash
# Drift guards for the en-sweep CI fix (FR01 U11).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# Repointed from en-build: D52 left it dispatching no peer and delegating
# simplification to /en-simplify, so it carries none of this machinery. The
# path now names the skill that owns it.
TEST_NAME="en-sweep CI fix"

CI="$REPO_ROOT/skills/en-sweep/scripts/en-sweep-ci"
WF="$REPO_ROOT/skills/en-setup/references/templates/github-workflow-en-sweep.yml"
SETUP="$REPO_ROOT/skills/en-setup/SKILL.md"

# --- syntax valid ---
if bash -n "$CI" 2>/dev/null; then
  pass "en-sweep-ci is syntactically valid"
else
  fail "en-sweep-ci has a syntax error"
fi

# --- registers the cloned plugin ---
if grep -qF -- "--plugin-dir" "$CI" && grep -qF "ENSEMBLE_PLUGIN_DIR" "$CI"; then
  pass "en-sweep-ci registers the cloned plugin (--plugin-dir)"
else
  fail "en-sweep-ci must register the cloned plugin"
fi

# --- guards against no-op runs ---
if grep -qiE "num_turns" "$CI" && grep -qiE "unknown command" "$CI"; then
  pass "en-sweep-ci guards on num_turns / unknown command"
else
  fail "en-sweep-ci must guard on num_turns / unknown command"
fi

# --- the guard actually exits non-zero (function exists + exit 1 path) ---
if grep -qE "guard_claude|guard_codex" "$CI" && grep -qE "exit 1" "$CI"; then
  pass "en-sweep-ci has a failing guard path"
else
  fail "en-sweep-ci must fail (exit 1) on a no-op run"
fi

# --- codex JSONL stream is guarded separately from claude's envelope ---
if grep -qE "guard_codex" "$CI" && grep -qE "turn.completed|agent_message" "$CI"; then
  pass "en-sweep-ci guards codex JSONL stream separately"
else
  fail "en-sweep-ci must guard codex's JSONL stream (not assume claude's envelope)"
fi

# --- functional: guard fails on a no-op envelope, passes on a real run ---
guard_test() {
  out="$1"
  turns=$(printf '%s' "$out" | jq -r '.num_turns // empty' 2>/dev/null || true)
  result=$(printf '%s' "$out" | jq -r '.result // empty' 2>/dev/null || true)
  is_err=$(printf '%s' "$out" | jq -r '.is_error // empty' 2>/dev/null || true)
  if [ "${turns:-0}" = "0" ] || printf '%s' "$result" | grep -qi 'unknown command' || [ "$is_err" = "true" ]; then
    return 1; fi; return 0
}
if guard_test '{"num_turns":0,"result":"Unknown command: /en-sweep","is_error":false}'; then
  fail "guard should reject a no-op (num_turns:0) run"
else
  pass "guard rejects the green-but-inert no-op run"
fi
if guard_test '{"num_turns":9,"result":"swept","is_error":false}'; then
  pass "guard accepts a real run"
else
  fail "guard should accept a real run"
fi

# --- workflow prefers the cloned script ---
if grep -qF 'ENSEMBLE_PLUGIN_DIR/bin/en-sweep-ci' "$WF"; then
  pass "workflow invokes the cloned en-sweep-ci"
else
  fail "workflow must prefer the cloned en-sweep-ci"
fi

# --- en-setup documents the re-sync caveat ---
if grep -qiE "Re-sync on update|frozen snapshot|do NOT propagate" "$SETUP"; then
  pass "en-setup documents the consumer re-sync caveat"
else
  fail "en-setup must document the re-sync caveat"
fi

# --- D99: the wrapper supplies the prompt when the workflow passes none -------
# The workflow calls the wrapper bare, and `claude -p` with no prompt reads an
# empty stdin. The prompt carries the autonomous framing so a runner cannot pass
# the num_turns guard by describing the PR it would open. Behavioural: a stub
# `claude` on PATH records its argv.
STUB=$(mktemp -d); cat > "$STUB/claude" <<'S'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_OUT"
printf '{"type":"result","num_turns":3,"is_error":false,"result":"ok"}\n'
S
chmod +x "$STUB/claude"
STUB_OUT="$STUB/argv" PATH="$STUB:$PATH" bash "$REPO_ROOT/skills/en-sweep/scripts/en-sweep-ci" >/dev/null 2>&1 || true
if grep -q "operating unattended in CI" "$STUB/argv" 2>/dev/null; then
  pass "wrapper passes the autonomous prompt when called bare"
else
  fail "wrapper must pass the autonomous prompt when called bare (D99)"
fi
STUB_OUT="$STUB/argv2" PATH="$STUB:$PATH" bash "$REPO_ROOT/skills/en-sweep/scripts/en-sweep-ci" "custom prompt" >/dev/null 2>&1 || true
if grep -q "custom prompt" "$STUB/argv2" 2>/dev/null && ! grep -q "operating unattended" "$STUB/argv2" 2>/dev/null; then
  pass "a caller-supplied prompt is passed through unchanged"
else
  fail "a caller-supplied prompt must be passed through unchanged"
fi
# D100: runner model and effort arrive as env and become CLI flags; a bad
# value is dropped, never passed.
STUB_OUT="$STUB/argv3" ENSEMBLE_SWEEP_MODEL=fable ENSEMBLE_SWEEP_EFFORT=high PATH="$STUB:$PATH" \
  bash "$REPO_ROOT/skills/en-sweep/scripts/en-sweep-ci" >/dev/null 2>&1 || true
if grep -qx -- "--model" "$STUB/argv3" && grep -qx "fable" "$STUB/argv3" \
   && grep -qx -- "--effort" "$STUB/argv3" && grep -qx "high" "$STUB/argv3"; then
  pass "ENSEMBLE_SWEEP_MODEL and ENSEMBLE_SWEEP_EFFORT become --model and --effort"
else
  fail "ENSEMBLE_SWEEP_MODEL/EFFORT must become --model/--effort (D100)" "$(tr '\n' ' ' < "$STUB/argv3" 2>/dev/null)"
fi
STUB_OUT="$STUB/argv4" ENSEMBLE_SWEEP_MODEL='x --dangerously' ENSEMBLE_SWEEP_EFFORT=turbo PATH="$STUB:$PATH" \
  bash "$REPO_ROOT/skills/en-sweep/scripts/en-sweep-ci" >/dev/null 2>&1 || true
if ! grep -qx -- "--model" "$STUB/argv4" && ! grep -qx -- "--effort" "$STUB/argv4"; then
  pass "a malformed model or unknown effort is dropped, not passed"
else
  fail "a malformed model or unknown effort must be dropped" "$(tr '\n' ' ' < "$STUB/argv4" 2>/dev/null)"
fi
grep -q 'vars.ENSEMBLE_SWEEP_MODEL' "$WF" && pass "workflow template passes ENSEMBLE_SWEEP_MODEL from repo variables" \
  || fail "workflow template must pass ENSEMBLE_SWEEP_MODEL from vars"
rm -rf "$STUB"

report
