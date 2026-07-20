#!/usr/bin/env bash
# Tests for skills/en-guardrail/bin/install-guardrail — exercise install,
# idempotency, merge with existing hooks, uninstall, status reporting.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-guardrail installer"

INSTALLER="$REPO_ROOT/skills/en-guardrail/bin/install-guardrail"
HOOK_SCRIPT="$REPO_ROOT/skills/en-guardrail/bin/check-guardrail.sh"

[ -x "$INSTALLER" ] || { fail "installer missing or not executable: $INSTALLER"; report; exit 1; }
[ -x "$HOOK_SCRIPT" ] || { fail "hook script missing or not executable: $HOOK_SCRIPT"; report; exit 1; }

TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

# Helper: count guardrail hook entries in a settings file
count_guardrail_entries() {
  local file="$1"
  python3 - "$file" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(0); raise SystemExit
n = 0
for e in d.get("hooks", {}).get("PreToolUse", []):
    if e.get("matcher") != "Bash":
        continue
    for h in e.get("hooks", []):
        if "en-guardrail" in h.get("command", "") and "check-guardrail.sh" in h.get("command", ""):
            n += 1
print(n)
PY
}

# --- install-project into a non-existent settings file ---
F1="$TMP/case1/.claude/settings.json"
GUARDRAIL_SETTINGS_FILE="$F1" "$INSTALLER" install-project >/dev/null
if [ -f "$F1" ] && [ "$(count_guardrail_entries "$F1")" = "1" ]; then
  pass "install-project creates settings.json with one guardrail entry"
else
  fail "install-project from scratch did not produce a single hook entry" "file=$F1, count=$(count_guardrail_entries "$F1")"
fi

# --- status reflects installed state ---
status_out=$(GUARDRAIL_SETTINGS_FILE="$F1" "$INSTALLER" status 2>/dev/null || true)
if echo "$status_out" | grep -q "project (.*): yes"; then
  pass "status reports project: yes after install"
else
  fail "status did not report project: yes" "$status_out"
fi

# --- install-project a second time is idempotent ---
GUARDRAIL_SETTINGS_FILE="$F1" "$INSTALLER" install-project >/dev/null
if [ "$(count_guardrail_entries "$F1")" = "1" ]; then
  pass "install-project is idempotent (still 1 entry after second run)"
else
  fail "install-project duplicated entries on second run" "count=$(count_guardrail_entries "$F1")"
fi

# --- install-project preserves existing unrelated hooks ---
F2="$TMP/case2/.claude/settings.json"
mkdir -p "$(dirname "$F2")"
cat > "$F2" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit",
        "hooks": [{"type":"command","command":"echo edit-hook-preserved"}]
      }
    ],
    "PostToolUse": [
      {"matcher":"*","hooks":[{"type":"command","command":"echo post-preserved"}]}
    ]
  },
  "permissions": {"allow":["Read"]}
}
EOF
GUARDRAIL_SETTINGS_FILE="$F2" "$INSTALLER" install-project >/dev/null
if grep -q "edit-hook-preserved" "$F2" \
   && grep -q "post-preserved" "$F2" \
   && grep -q '"allow"' "$F2" \
   && [ "$(count_guardrail_entries "$F2")" = "1" ]; then
  pass "install-project preserves existing hooks and adds guardrail alongside"
else
  fail "install-project did not preserve existing structure" "$(cat "$F2")"
fi

# --- uninstall-project removes the entry but leaves others alone ---
GUARDRAIL_SETTINGS_FILE="$F2" "$INSTALLER" uninstall-project >/dev/null
if grep -q "edit-hook-preserved" "$F2" \
   && grep -q "post-preserved" "$F2" \
   && [ "$(count_guardrail_entries "$F2")" = "0" ]; then
  pass "uninstall-project removes guardrail and preserves other hooks"
else
  fail "uninstall-project produced unexpected state" "$(cat "$F2")"
fi

# --- install-global without --apply prints advisory, never modifies anything ---
ADVISORY=$("$INSTALLER" install-global 2>&1)
if echo "$ADVISORY" | grep -q "self-modification" \
   && echo "$ADVISORY" | grep -q "install-global --apply"; then
  pass "install-global (no --apply) prints self-modification advisory"
else
  fail "install-global advisory missing expected content" "$ADVISORY"
fi

# --- install-global --apply targets ~/.claude/settings.json; isolate via HOME override ---
HOME_OVERRIDE="$TMP/case3/home"
mkdir -p "$HOME_OVERRIDE/.claude"
HOME="$HOME_OVERRIDE" "$INSTALLER" install-global --apply >/dev/null
F3="$HOME_OVERRIDE/.claude/settings.json"
if [ "$(count_guardrail_entries "$F3")" = "1" ]; then
  pass "install-global --apply writes hook to \$HOME/.claude/settings.json"
else
  fail "install-global --apply did not produce hook" "count=$(count_guardrail_entries "$F3"), file=$F3"
fi

# --- malformed JSON fails cleanly without corrupting the file ---
F4="$TMP/case4/.claude/settings.json"
mkdir -p "$(dirname "$F4")"
echo '{ this is not json' > "$F4"
ORIGINAL=$(cat "$F4")
ERR=$(GUARDRAIL_SETTINGS_FILE="$F4" "$INSTALLER" install-project 2>&1 || true)
if [ "$(cat "$F4")" = "$ORIGINAL" ] && echo "$ERR" | grep -qi "not valid json"; then
  pass "malformed settings.json: error reported, file untouched"
else
  fail "malformed settings.json was modified or no error surfaced" "$ERR ; file=$(cat "$F4")"
fi

# --- backup is created before mutation ---
F5="$TMP/case5/.claude/settings.json"
mkdir -p "$(dirname "$F5")"
echo '{"hooks":{},"sentinel":"original"}' > "$F5"
GUARDRAIL_SETTINGS_FILE="$F5" "$INSTALLER" install-project >/dev/null
backup_count=$(ls "$(dirname "$F5")"/settings.json.bak.* 2>/dev/null | wc -l | tr -d ' ')
if [ "$backup_count" -ge 1 ] && grep -q "sentinel" "$(dirname "$F5")"/settings.json.bak.* 2>/dev/null; then
  pass "install-project creates a backup of the original file"
else
  fail "no backup created on install-project" "backups=$backup_count"
fi

# --- EN09 U4: install writes BOTH the Bash matcher AND the MCP DB-tool matcher ---
mcp_matcher_present() {  # arg: settings file -> prints 1 if an MCP guardrail matcher exists
  python3 - "$1" <<'PY'
import json, sys, re
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(0); sys.exit(0)
n = 0
for e in d.get("hooks", {}).get("PreToolUse", []):
    m = e.get("matcher", "")
    if not m.startswith("mcp__"):
        continue
    if any("check-guardrail.sh" in h.get("command", "") for h in e.get("hooks", [])):
        # must be a compilable regex that targets run_sql-family DB writers
        try: re.compile(m)
        except re.error: continue
        if "run_sql" in m:
            n += 1
print(n)
PY
}
F6="$TMP/case6/.claude/settings.json"
GUARDRAIL_SETTINGS_FILE="$F6" "$INSTALLER" install-project >/dev/null
if [ "$(mcp_matcher_present "$F6")" = "1" ] && [ "$(count_guardrail_entries "$F6")" = "1" ]; then
  pass "install-project writes both the Bash and the MCP DB-tool matcher"
else
  fail "install-project missing the MCP matcher (or Bash matcher)" "$(cat "$F6")"
fi

# idempotent for the MCP matcher too (no duplicate on re-run)
GUARDRAIL_SETTINGS_FILE="$F6" "$INSTALLER" install-project >/dev/null
if [ "$(mcp_matcher_present "$F6")" = "1" ]; then
  pass "MCP matcher install is idempotent"
else
  fail "MCP matcher duplicated or lost on re-run" "$(cat "$F6")"
fi

# uninstall removes BOTH matchers
GUARDRAIL_SETTINGS_FILE="$F6" "$INSTALLER" uninstall-project >/dev/null
if [ "$(mcp_matcher_present "$F6")" = "0" ] && [ "$(count_guardrail_entries "$F6")" = "0" ]; then
  pass "uninstall-project removes both the Bash and MCP guardrail matchers"
else
  fail "uninstall left a guardrail matcher behind" "$(cat "$F6")"
fi

report
