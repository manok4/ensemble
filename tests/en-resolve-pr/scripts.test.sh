#!/usr/bin/env bash
# Tests for skills/en-resolve-pr/scripts/* — smoke-test arg handling and error
# paths. The actual gh api calls are not exercised (they require a real PR);
# tests focus on what we can verify deterministically.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-resolve-pr scripts"

SKILL_DIR="$REPO_ROOT/skills/en-resolve-pr"
SCRIPTS_DIR="$SKILL_DIR/scripts"

# --- All five scripts exist and are executable ---
for s in get-pr-comments get-thread-for-comment reply-to-pr-thread resolve-pr-thread check-merge-status; do
  if [ -x "$SCRIPTS_DIR/$s" ]; then
    pass "script exists and is executable: $s"
  else
    fail "script missing or not executable: $s" "expected: $SCRIPTS_DIR/$s"
  fi
done

# --- All scripts have a usage block + a description header ---
# Structural integrity: each script starts with a shebang, has a usage hint
# matching the script name, and uses gh api graphql for the GitHub call.
for s in get-pr-comments get-thread-for-comment reply-to-pr-thread resolve-pr-thread; do
  if head -3 "$SCRIPTS_DIR/$s" | grep -q '^#!/usr/bin/env bash'; then
    pass "$s has bash shebang"
  else
    fail "$s missing or incorrect shebang"
  fi
  if grep -q "Usage:" "$SCRIPTS_DIR/$s"; then
    pass "$s documents usage"
  else
    fail "$s missing Usage: block"
  fi
  if grep -q "gh api graphql" "$SCRIPTS_DIR/$s"; then
    pass "$s uses gh api graphql"
  else
    fail "$s does not invoke gh api graphql"
  fi
done

# --- get-pr-comments: usage on no args ---
out=$(bash "$SCRIPTS_DIR/get-pr-comments" 2>&1 || true)
if echo "$out" | grep -q "Usage: get-pr-comments"; then
  pass "get-pr-comments prints usage on no args"
else
  fail "get-pr-comments did not print usage" "$out"
fi

# --- get-thread-for-comment: usage on no args ---
out=$(bash "$SCRIPTS_DIR/get-thread-for-comment" 2>&1 || true)
if echo "$out" | grep -q "Usage: get-thread-for-comment"; then
  pass "get-thread-for-comment prints usage on no args"
else
  fail "get-thread-for-comment did not print usage" "$out"
fi

# --- get-thread-for-comment: usage on missing comment ID ---
out=$(bash "$SCRIPTS_DIR/get-thread-for-comment" 123 2>&1 || true)
if echo "$out" | grep -q "Usage:"; then
  pass "get-thread-for-comment requires both PR and comment ID"
else
  fail "get-thread-for-comment did not require comment ID" "$out"
fi

# --- reply-to-pr-thread: usage on no args ---
out=$(bash "$SCRIPTS_DIR/reply-to-pr-thread" 2>&1 || true)
if echo "$out" | grep -q "Usage: echo"; then
  pass "reply-to-pr-thread prints usage on no args"
else
  fail "reply-to-pr-thread did not print usage" "$out"
fi

# --- reply-to-pr-thread: empty stdin produces error ---
out=$(echo -n "" | bash "$SCRIPTS_DIR/reply-to-pr-thread" PRRT_test 2>&1 || true)
if echo "$out" | grep -qi "no reply body on stdin\|no body provided on stdin"; then
  pass "reply-to-pr-thread rejects empty stdin"
else
  fail "reply-to-pr-thread should reject empty stdin" "$out"
fi

# --- resolve-pr-thread: usage on no args ---
out=$(bash "$SCRIPTS_DIR/resolve-pr-thread" 2>&1 || true)
if echo "$out" | grep -q "Usage: resolve-pr-thread"; then
  pass "resolve-pr-thread prints usage on no args"
else
  fail "resolve-pr-thread did not print usage" "$out"
fi

# --- get-pr-comments: jq query is syntactically valid ---
# Pipe a synthetic GraphQL response through the jq filter and verify it parses.
# We mock by extracting just the jq command and feeding it a minimal payload.
SYNTHETIC_RESPONSE='{
  "data": {
    "repository": {
      "pullRequest": {
        "author": {"login": "test-user"},
        "reviewThreads": {"edges": []},
        "comments": {"nodes": []},
        "reviews": {"nodes": []}
      }
    }
  }
}'
# Extract the partition jq filter from the script — the multi-line block
# starting with `echo "$RAW" | jq '` and ending with the closing `'` before EOF.
# (The script also contains earlier `| jq -s` pagination-merge pipelines; anchor
# on the partition invocation specifically so we extract the right block.)
JQ_FILTER=$(awk '
  /echo "\$RAW" \| jq /{flag=1; sub(/.*\| jq '"'"'/, ""); }
  flag{print}
' "$SCRIPTS_DIR/get-pr-comments" | sed "s/'$//")
if echo "$SYNTHETIC_RESPONSE" | jq "$JQ_FILTER" >/dev/null 2>&1; then
  pass "get-pr-comments jq filter accepts empty PR"
else
  fail "get-pr-comments jq filter is malformed or rejects empty PR" "filter=$JQ_FILTER"
fi

# --- get-pr-comments: synthetic response with one review thread parses correctly ---
SYNTHETIC_THREAD='{
  "data": {
    "repository": {
      "pullRequest": {
        "author": {"login": "author"},
        "reviewThreads": {"edges": [
          {"node": {
            "id": "PRRT_1", "isResolved": false, "isOutdated": false,
            "path": "src/foo.ts", "line": 42,
            "originalLine": 42, "startLine": null, "originalStartLine": null,
            "comments": {"nodes": [
              {"id": "PRRC_1", "author": {"login": "reviewer"},
               "body": "Add null check", "createdAt": "2026-05-03T10:00:00Z",
               "url": "https://github.com/x/y/pull/1#discussion_r1"}
            ]}
          }}
        ]},
        "comments": {"nodes": []},
        "reviews": {"nodes": []}
      }
    }
  }
}'
PARSED=$(echo "$SYNTHETIC_THREAD" | jq "$JQ_FILTER" 2>&1 || true)
if echo "$PARSED" | jq -e '.review_threads | length == 1' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.cross_invocation.signal == false' >/dev/null 2>&1; then
  pass "get-pr-comments correctly extracts one unresolved thread"
else
  fail "get-pr-comments mis-parsed one-thread payload" "$PARSED"
fi

# --- get-pr-comments: filters PR-author comments out of pr_comments ---
# but preserves them in pr_author_replies (used by SKILL triage to detect
# already-handled items).
SYNTHETIC_AUTHOR='{
  "data": {
    "repository": {
      "pullRequest": {
        "author": {"login": "author"},
        "reviewThreads": {"edges": []},
        "comments": {"nodes": [
          {"id": "C1", "author": {"login": "author"}, "body": "> Original reviewer asked X\n\nAddressed: did Y"},
          {"id": "C2", "author": {"login": "reviewer"}, "body": "real comment"}
        ]},
        "reviews": {"nodes": []}
      }
    }
  }
}'
PARSED=$(echo "$SYNTHETIC_AUTHOR" | jq "$JQ_FILTER" 2>&1 || true)
if echo "$PARSED" | jq -e '.pr_comments | length == 1' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.pr_comments[0].author.login == "reviewer"' >/dev/null 2>&1; then
  pass "get-pr-comments excludes PR-author comments from pr_comments"
else
  fail "get-pr-comments did not exclude PR-author from pr_comments" "$PARSED"
fi

# pr_author_replies must contain the author's reply for triage's "already replied" detection
if echo "$PARSED" | jq -e '.pr_author_replies | length == 1' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.pr_author_replies[0].id == "C1"' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.pr_author_replies[0].body | startswith("> ")' >/dev/null 2>&1; then
  pass "get-pr-comments preserves PR-author replies in pr_author_replies"
else
  fail "get-pr-comments did not preserve PR-author replies" "$PARSED"
fi

# Empty body author comments still get filtered out of pr_author_replies
SYNTHETIC_EMPTY_AUTHOR='{
  "data": {
    "repository": {
      "pullRequest": {
        "author": {"login": "author"},
        "reviewThreads": {"edges": []},
        "comments": {"nodes": [
          {"id": "C1", "author": {"login": "author"}, "body": ""},
          {"id": "C2", "author": {"login": "author"}, "body": "   "},
          {"id": "C3", "author": {"login": "author"}, "body": "real reply"}
        ]},
        "reviews": {"nodes": []}
      }
    }
  }
}'
PARSED=$(echo "$SYNTHETIC_EMPTY_AUTHOR" | jq "$JQ_FILTER" 2>&1 || true)
if echo "$PARSED" | jq -e '.pr_author_replies | length == 1' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.pr_author_replies[0].body == "real reply"' >/dev/null 2>&1; then
  pass "get-pr-comments drops empty/whitespace-only PR-author replies"
else
  fail "get-pr-comments did not drop empty PR-author replies" "$PARSED"
fi

# --- get-pr-comments: filters out CI bots (codecov) ---
SYNTHETIC_BOT='{
  "data": {
    "repository": {
      "pullRequest": {
        "author": {"login": "author"},
        "reviewThreads": {"edges": []},
        "comments": {"nodes": [
          {"id": "C1", "author": {"login": "codecov"}, "body": "coverage report"},
          {"id": "C2", "author": {"login": "reviewer"}, "body": "real comment"}
        ]},
        "reviews": {"nodes": []}
      }
    }
  }
}'
PARSED=$(echo "$SYNTHETIC_BOT" | jq "$JQ_FILTER" 2>&1 || true)
if echo "$PARSED" | jq -e '.pr_comments | length == 1' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.pr_comments[0].author.login == "reviewer"' >/dev/null 2>&1; then
  pass "get-pr-comments filters codecov CI bot"
else
  fail "get-pr-comments did not filter codecov" "$PARSED"
fi

# --- get-pr-comments: cross_invocation.signal fires when both resolved+unresolved exist ---
SYNTHETIC_MIXED='{
  "data": {
    "repository": {
      "pullRequest": {
        "author": {"login": "author"},
        "reviewThreads": {"edges": [
          {"node": {"id": "PRRT_resolved", "isResolved": true, "isOutdated": false,
                    "path": "src/a.ts", "line": 10,
                    "originalLine": 10, "startLine": null, "originalStartLine": null,
                    "comments": {"nodes": [{"id":"c1","author":{"login":"r"},"body":"old","createdAt":"2026-05-01T10:00:00Z","url":"u"}]}}},
          {"node": {"id": "PRRT_unresolved", "isResolved": false, "isOutdated": false,
                    "path": "src/b.ts", "line": 20,
                    "originalLine": 20, "startLine": null, "originalStartLine": null,
                    "comments": {"nodes": [{"id":"c2","author":{"login":"r"},"body":"new","createdAt":"2026-05-03T10:00:00Z","url":"u"}]}}}
        ]},
        "comments": {"nodes": []},
        "reviews": {"nodes": []}
      }
    }
  }
}'
PARSED=$(echo "$SYNTHETIC_MIXED" | jq "$JQ_FILTER" 2>&1 || true)
if echo "$PARSED" | jq -e '.cross_invocation.signal == true' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.review_threads | length == 1' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.cross_invocation.resolved_threads | length == 1' >/dev/null 2>&1; then
  pass "get-pr-comments emits cross_invocation.signal=true when mixed"
else
  fail "get-pr-comments did not set cross_invocation correctly" "$PARSED"
fi

# --- check-merge-status: usage on no args ---
out=$(bash "$SCRIPTS_DIR/check-merge-status" 2>&1 || true)
if echo "$out" | grep -q "Usage: check-merge-status"; then
  pass "check-merge-status prints usage on no args"
else
  fail "check-merge-status did not print usage" "$out"
fi

# --- check-merge-status: jq filter is structurally valid ---
# Extract the jq filter and feed it a synthetic gh pr view + repo response.
MERGE_JQ=$(awk '
  /^echo "\$PR_JSON" \| jq /{flag=1; sub(/.*echo "\$PR_JSON" \| jq --arg repo_auto "\$REPO_AUTO_MERGE" '"'"'/, ""); }
  flag{print}
' "$SCRIPTS_DIR/check-merge-status" | sed "s/'$//")
SYNTHETIC_PR='{
  "number": 42,
  "title": "test PR",
  "headRefName": "feature/x",
  "autoMergeRequest": null,
  "mergeable": "MERGEABLE",
  "mergeStateStatus": "CLEAN",
  "reviewDecision": "APPROVED",
  "statusCheckRollup": []
}'
PARSED=$(echo "$SYNTHETIC_PR" | jq --arg repo_auto "true" "$MERGE_JQ" 2>&1 || true)
if echo "$PARSED" | jq -e '.repo_allows_auto_merge == true' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.auto_merge_enabled == false' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.merge_state_status == "CLEAN"' >/dev/null 2>&1; then
  pass "check-merge-status correctly extracts CLEAN + auto-merge-not-enabled state"
else
  fail "check-merge-status mis-parsed clean PR" "$PARSED"
fi

# --- check-merge-status: detects auto-merge-enabled state ---
SYNTHETIC_AUTO='{
  "number": 42,
  "title": "test PR",
  "headRefName": "feature/x",
  "autoMergeRequest": {"mergeMethod": "SQUASH", "enabledBy": {"login": "user"}},
  "mergeable": "MERGEABLE",
  "mergeStateStatus": "BLOCKED",
  "reviewDecision": "REVIEW_REQUIRED",
  "statusCheckRollup": []
}'
PARSED=$(echo "$SYNTHETIC_AUTO" | jq --arg repo_auto "true" "$MERGE_JQ" 2>&1 || true)
if echo "$PARSED" | jq -e '.auto_merge_enabled == true' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.auto_merge_method == "SQUASH"' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.review_decision == "REVIEW_REQUIRED"' >/dev/null 2>&1; then
  pass "check-merge-status correctly extracts auto-merge-enabled state"
else
  fail "check-merge-status mis-parsed auto-merge-enabled PR" "$PARSED"
fi

# --- check-merge-status: extracts failing checks ---
SYNTHETIC_FAILING='{
  "number": 42,
  "title": "test PR",
  "headRefName": "feature/x",
  "autoMergeRequest": null,
  "mergeable": "MERGEABLE",
  "mergeStateStatus": "BLOCKED",
  "reviewDecision": "APPROVED",
  "statusCheckRollup": [
    {"name": "lint", "conclusion": "SUCCESS", "status": "COMPLETED"},
    {"name": "tests", "conclusion": "FAILURE", "status": "COMPLETED", "detailsUrl": "https://example.com/run/1"},
    {"name": "build", "conclusion": "IN_PROGRESS", "status": "IN_PROGRESS"}
  ]
}'
PARSED=$(echo "$SYNTHETIC_FAILING" | jq --arg repo_auto "true" "$MERGE_JQ" 2>&1 || true)
if echo "$PARSED" | jq -e '.failing_checks | length == 1' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.failing_checks[0].name == "tests"' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.pending_checks | length == 1' >/dev/null 2>&1 \
   && echo "$PARSED" | jq -e '.pending_checks[0].name == "build"' >/dev/null 2>&1; then
  pass "check-merge-status correctly buckets failing vs pending checks"
else
  fail "check-merge-status mis-parsed mixed-check PR" "$PARSED"
fi

# --- SKILL.md documents --enable-auto-merge flag ---
SKILL="$REPO_ROOT/skills/en-resolve-pr/SKILL.md"
if grep -q -- "--enable-auto-merge" "$SKILL"; then
  pass "SKILL.md documents --enable-auto-merge flag"
else
  fail "SKILL.md missing --enable-auto-merge flag documentation"
fi

# --- SKILL.md documents merge-readiness reporting ---
if grep -q "Merge readiness" "$SKILL"; then
  pass "SKILL.md describes merge-readiness reporting"
else
  fail "SKILL.md missing merge-readiness section"
fi

# --- /en-setup mentions repo-level auto-merge check ---
SETUP_SKILL="$REPO_ROOT/skills/en-setup/SKILL.md"
if grep -q "allow_auto_merge" "$SETUP_SKILL"; then
  pass "/en-setup checks repo-level allow_auto_merge"
else
  fail "/en-setup does not check allow_auto_merge"
fi

report
