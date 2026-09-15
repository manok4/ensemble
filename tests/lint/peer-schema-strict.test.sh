#!/usr/bin/env bash
# tests/lint/peer-schema-strict.test.sh
#
# Codex's --output-schema is OpenAI structured outputs: every object needs
# additionalProperties:false and every property must be listed in required.
# On 2026-09-08 the peer failed in five seconds with invalid_json_schema
# because the schema said additionalProperties:true, and the branch review
# ran with no peer. This walks every object in the schema and checks both.
#
# Claude's --json-schema is the other end of the same contract, and it is
# stricter in one direction: it resolves whatever $schema declares and has no
# meta-schema registered, so `"$schema": "https://json-schema.org/draft/2020-12/schema"`
# made it refuse the schema outright with `no schema with key or ref "..."`
# (2026-09-15, Claude Code 2.1.271). Every Claude peer call died in one second
# and en-review reported peer-failed:unknown. tests/lint/peer-isolation.test.sh
# cannot catch this: it drives PATH-shadow CLIs, which accept any argv handed
# to them. Both CLIs infer the draft, so the declaration buys nothing.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="peer findings schema is strict"

command -v jq >/dev/null 2>&1 || { pass "SKIPPED — jq not installed"; report; }
for f in "$REPO_ROOT"/skills/*/scripts/peer-findings.schema.json; do
  n=$(basename "$(dirname "$(dirname "$f")")")
  jq -e . "$f" >/dev/null 2>&1 && pass "$n: schema parses" || { fail "$n: schema parses"; continue; }
  loose=$(jq -r '[.. | objects | select(.type == "object") | select(.additionalProperties != false)] | length' "$f")
  assert_eq "0" "$loose" "$n: every object sets additionalProperties:false"
  gaps=$(jq -r '[.. | objects | select(.type == "object") | select((.properties | keys | sort) != (.required // [] | sort))] | length' "$f")
  assert_eq "0" "$gaps" "$n: every object lists all of its properties in required"
  # A property that must be allowed to be absent in the peer's answer is
  # expressed as nullable, never by leaving it out of required.
  nullable=$(jq -r '.properties.findings.items.properties.u_id.type | if type=="array" then (index("null") != null) else false end' "$f")
  assert_eq "true" "$nullable" "$n: optional finding fields are nullable"
  # Anywhere, not just at the root: a nested $ref target would carry the same
  # declaration to the same validator and fail the same way.
  metas=$(jq -r '[.. | objects | select(has("$schema"))] | length' "$f")
  assert_eq "0" "$metas" "$n: declares no \$schema (Claude's --json-schema cannot resolve one)"
done

report
