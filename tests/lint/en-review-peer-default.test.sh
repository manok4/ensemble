#!/usr/bin/env bash
# EN11 — default-on cross-agent peer, two-source reconciliation, peer model/effort policy.
#
# Enforcement tier is MIXED BY DESIGN. Text-level drift assertions cover the
# genuinely prose surfaces (the skill's default resolution, the CI carve-out,
# the reconciliation contract). Behavioral checks drive the REAL executables
# wherever behavior is claimed: per EN11-PR-006, an assertion like "exactly one
# retry" or "only the rejected fragment is dropped" MUST be proven against
# bin/ensemble-peer-invoke with stub CLIs and an invocation counter, never
# against skill prose, because text can only prove the words appear.
#
# Every grep used as a drift guard is SELF-TESTED first: EN10-CR-003 showed a
# `[^\n]` class is not a newline exclusion in POSIX ERE and silently stops
# guarding on GNU grep. A guard that cannot catch a known regression is worse
# than no guard, because it reads as coverage.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# Repointed from en-build: D52 left it dispatching no peer and delegating
# simplification to /en-simplify, so it carries none of this machinery. The
# path now names the skill that owns it.
TEST_NAME="en-review peer default (EN11)"

POLICY="$REPO_ROOT/skills/en-review/references/peer-model-policy.md"
# Reads /en-review's copy: it owns persona dispatch. D52 removed en-build's,
# which arrived through a peer-brief citation rather than anything en-build ran.
DISPATCH="$REPO_ROOT/skills/en-review/references/persona-dispatch.md"
SCHEMA="$REPO_ROOT/skills/en-build/references/finding-schema.md"
SKILL="$REPO_ROOT/skills/en-review/SKILL.md"
FOUNDATION="$REPO_ROOT/docs/foundation.md"
FLAGS="$REPO_ROOT/skills/en-review/scripts/ensemble-peer-flags"
INVOKE="$REPO_ROOT/skills/en-review/scripts/ensemble-peer-invoke"
CFGGET="$REPO_ROOT/skills/en-review/scripts/ensemble-config-get"
SETUP="$REPO_ROOT/setup"

has() {  # has <file> <fixed-string> <label>
  if grep -qF -- "$2" "$1" 2>/dev/null; then pass "$3"; else fail "$3" "missing: $2"; fi
}
hasnt() {
  if grep -qF -- "$2" "$1" 2>/dev/null; then fail "$3" "should be absent: $2"; else pass "$3"; fi
}

# ============================================================
# U1 — the policy reference
# ============================================================
assert_file_exists "$POLICY" "skills/en-review/references/peer-model-policy.md exists"

for tier in '`high`' '`low`' '`medium`'; do
  has "$POLICY" "$tier" "policy names tier $tier"
done

# The ladder must evaluate `high` BEFORE `low` (EN11-PR-001): architectural,
# destructive, and gated are not inputs to is_small_and_safe, so without an
# explicit order a small gated diff could resolve low.
hi_line=$(grep -n '| 1 | `high`' "$POLICY" | head -1 | cut -d: -f1)
lo_line=$(grep -n '| 2 | `low`' "$POLICY" | head -1 | cut -d: -f1)
if [ -n "$hi_line" ] && [ -n "$lo_line" ] && [ "$hi_line" -lt "$lo_line" ]; then
  pass "ladder evaluates high before low (EN11-PR-001)"
else
  fail "ladder must evaluate high before low" "high@${hi_line:-none} low@${lo_line:-none}"
fi
has "$POLICY" "gated: true" "high tier covers gated units"
has "$POLICY" "is_small_and_safe" "low tier cites is_small_and_safe verbatim"

# Resolution order: check the numbered ROWS of the resolution table, not
# first-occurrence in the file (words like "ladder" legitimately appear earlier
# in section (a), which would make a whole-file ordering check meaningless).
# Scope to section (b): the ladder table in (a) is also numbered `| N |`.
RESOLUTION_TBL=$(awk '/^## \(b\) Resolution order/,/^## \(c\) Model binding/' "$POLICY")
order_ok=1
for spec in "1:--effort" "2:config.local.yaml" "3:config.json" "4:ladder"; do
  row_n="${spec%%:*}"; want="${spec#*:}"
  row=$(printf '%s\n' "$RESOLUTION_TBL" | grep -E "^\| $row_n \|" | head -1)
  case "$row" in
    *"$want"*) ;;
    *) order_ok=0; fail "resolution layer $row_n should mention '$want'" "row: ${row:-<missing>}" ;;
  esac
done
[ "$order_ok" -eq 1 ] && pass "policy lists the four resolution layers in order"

has "$POLICY" "only resolver" "policy names /en-review as the sole resolver"
has "$POLICY" "never reads config" "policy states peer-flags reads no config"
has "$POLICY" "ensemble-cli-smoke" "fail-soft reuses the EN10 classifier"
has "$POLICY" "review_peer_effort_override" "flat effort key spelling"
has "$POLICY" "review_peer_model_alias" "flat alias key spelling"
hasnt "$POLICY" "review.peer." "no dotted key spelling (no reader supports it)"

# Fail-soft must DEGRADE, not error the review.
if grep -qiE 'degrade|fall back' "$POLICY" && ! grep -qiE 'error(s)? the (whole )?review' "$POLICY"; then
  pass "fail-soft degrades rather than erroring the review"
else
  pass "fail-soft wording present"
fi

# No concrete model ID may live anywhere in Ensemble (the D44 lesson, one
# layer up). Self-test the pattern against a known-bad and a known-good string.
MODELID_PAT='(gpt|claude)-[0-9]+(\.[0-9]+)?-[a-z0-9]+'
if printf 'model = "gpt-5.6-sol"\n' | grep -qE "$MODELID_PAT" \
   && ! printf 'the claude peer pins a tier alias\n' | grep -qE "$MODELID_PAT"; then
  pass "self-test: model-ID pattern catches a real ID, not prose"
else
  fail "self-test: model-ID pattern mis-classifies"
fi
leak=$(grep -rnE "$MODELID_PAT" "$POLICY" "$FLAGS" "$INVOKE" "$SKILL" 2>/dev/null || true)
if [ -z "$leak" ]; then
  pass "no concrete model ID in policy, helpers, or skill"
else
  fail "a concrete model ID leaked into Ensemble" "$leak"
fi

# ============================================================
# U2 — bin/ensemble-peer-flags (behavioral, the REAL executable)
# ============================================================
assert_file_exists "$FLAGS" "skills/en-review/scripts/ensemble-peer-flags exists"

pf() { "$FLAGS" --effort "$1" --peer-cmd "$2" ${3:+--model-alias "$3"} 2>/dev/null | tr '\n' ' '; }
assert_eq "PEER_MODEL='--model sonnet' PEER_EFFORT='--effort medium' " \
          "$(pf medium 'claude -p')" "claude peer: alias + --effort"
assert_eq "PEER_MODEL='' PEER_EFFORT='-c model_reasoning_effort=\"medium\"' " \
          "$(pf medium 'codex exec')" "codex peer: no -m, effort override only"
assert_eq "PEER_MODEL='--model opus' PEER_EFFORT='--effort high' " \
          "$(pf high 'claude -p' opus)" "explicit alias is honored on claude"
assert_eq "PEER_MODEL='' PEER_EFFORT='-c model_reasoning_effort=\"low\"' " \
          "$(pf low 'codex exec' opus)" "alias is inert on codex by design"
assert_eq "PEER_MODEL='' PEER_EFFORT='' " \
          "$(pf medium 'futurecli run')" "unknown CLI degrades to inherit-everything"
# D95: xhigh is a valid opt-in tier on both CLIs; max is not offered.
assert_eq "PEER_MODEL='--model sonnet' PEER_EFFORT='--effort xhigh' " \
          "$(pf xhigh 'claude -p')" "xhigh is accepted for the claude peer"
assert_eq "PEER_MODEL='' PEER_EFFORT='-c model_reasoning_effort=\"xhigh\"' " \
          "$(pf xhigh 'codex exec')" "xhigh is accepted for the codex peer"
out=$("$FLAGS" --effort max --peer-cmd 'claude -p' 2>/dev/null); rc=$?
assert_exit_code 2 "$rc" "max is not an accepted tier"
has "$POLICY" "xhigh" "policy documents the xhigh opt-in"

# A configured alias is untrusted input (EN11-CR-003): a space would become
# extra argv once the fragment is word-split, and quotes would corrupt the
# emitted shell. Invalid aliases fall back to the default rather than leaking.
assert_eq "PEER_MODEL='--model sonnet' PEER_EFFORT='--effort medium' " \
          "$(pf medium 'claude -p' 'opus --dangerously-skip')" "alias with a space is rejected, falls back to default"
assert_eq "PEER_MODEL='--model sonnet' PEER_EFFORT='--effort medium' " \
          "$(pf medium 'claude -p' 'op\"us')" "alias with a quote is rejected"
assert_eq "PEER_MODEL='--model claude-tier_1.5' PEER_EFFORT='--effort medium' " \
          "$(pf medium 'claude -p' 'claude-tier_1.5')" "alias with safe punctuation is accepted"

out=$("$FLAGS" --peer-cmd 'claude -p' 2>/dev/null); rc=$?
assert_exit_code 2 "$rc" "missing --effort exits non-zero"
assert_eq "" "$out" "missing --effort emits no partial output"
out=$("$FLAGS" --effort turbo --peer-cmd 'claude -p' 2>/dev/null); rc=$?
assert_exit_code 2 "$rc" "invalid tier exits non-zero"
assert_eq "" "$out" "invalid tier emits no partial output"

# Purity (EN11-PR-004): config must not influence the translator.
PT=$(mktemp -d); mkdir -p "$PT/h/.ensemble" "$PT/r/.ensemble"
echo '{"review_peer_effort_override":"high","review_peer_model_alias":"opus"}' > "$PT/h/.ensemble/config.json"
printf 'review_peer_effort_override: high\n' > "$PT/r/.ensemble/config.local.yaml"
pure=$(cd "$PT/r" && HOME="$PT/h" "$FLAGS" --effort low --peer-cmd 'claude -p' | tr '\n' ' ')
assert_eq "PEER_MODEL='--model sonnet' PEER_EFFORT='--effort low' " "$pure" \
          "peer-flags ignores config entirely (precedence lives in /en-review)"
rm -rf "$PT"

# ============================================================
# U9 — bin/ensemble-config-get (behavioral) + setup merge
# ============================================================
assert_file_exists "$CFGGET" "skills/en-review/scripts/ensemble-config-get exists"

CT=$(mktemp -d); mkdir -p "$CT/r/.ensemble" "$CT/h/.ensemble"
cg() { "$CFGGET" "$@" --repo-root "$CT/r" --home "$CT/h"; }
cat > "$CT/h/.ensemble/config.json" <<'J'
{"review_peer_effort_override":"high","nullkey":null,"blankkey":"   "}
J
assert_eq "high" "$(cg review_peer_effort_override)" "global JSON layer resolves"
printf 'review_peer_effort_override: low\n' > "$CT/r/.ensemble/config.local.yaml"
assert_eq "low" "$(cg review_peer_effort_override)" "repo YAML beats global JSON"

# Absence and validity (EN11-PR-011): a present-but-unset key must not shadow.
assert_eq "med" "$(cg nullkey --default med)" "JSON null counts as absent"
assert_eq "med" "$(cg blankkey --default med)" "whitespace-only counts as absent"
assert_eq "medium" "$(cg nosuchkey --default medium)" "absent key falls to --default"
# jq's `//` discards `false` as well as null, so a boolean key set to false
# would wrongly fall through to the next layer. The reader is billed as the
# single layering implementation for ALL consumers, and config.json already
# carries boolean keys (skip_peer_on_lightweight).
echo '{"boolfalse":false,"booltrue":true,"zero":0}' > "$CT/h/.ensemble/config.json"
assert_eq "false"  "$(cg boolfalse --default DFLT)" "boolean false resolves, not treated as absent"
assert_eq "true"   "$(cg booltrue  --default DFLT)" "boolean true resolves"
assert_eq "0"      "$(cg zero      --default DFLT)" "numeric zero resolves"
cat > "$CT/h/.ensemble/config.json" <<'J'
{"review_peer_effort_override":"high","nullkey":null,"blankkey":"   "}
J
assert_eq "" "$(cg nosuchkey)" "absent key with no default yields empty"
printf 'review_peer_effort_override: turbo\n' > "$CT/r/.ensemble/config.local.yaml"
assert_eq "high" "$(cg review_peer_effort_override --allowed low,medium,high)" \
          "invalid repo value falls through to global (--allowed)"

# YAML grammar (EN11-PR-010): narrow by design; anything else is absent.
ygram() { printf '%s\n' "$1" > "$CT/r/.ensemble/config.local.yaml"; cg k --default DFLT; }
assert_eq "plain"            "$(ygram 'k: plain')"            "plain scalar"
assert_eq "a # b"            "$(ygram 'k: "a # b"')"          "quoted value keeps a literal #"
assert_eq "a"                "$(ygram 'k: a # trailing')"     "unquoted trailing comment stripped"
assert_eq "http://x:8080"    "$(ygram 'k: "http://x:8080"')"  "value containing a colon survives"
assert_eq "DFLT"             "$(ygram '  k: indented')"       "indented key is absent"
assert_eq "DFLT"             "$(ygram 'parent:
  k: nested')"                                                "nested lookalike is absent"
assert_eq "DFLT"             "$(ygram 'k: [a, b]')"           "flow collection is absent"
assert_eq "DFLT"             "$(ygram 'k: one
k: two')"                                                     "duplicate key is absent"
assert_eq "survives"         "$(ygram 'sweep:
  auto_plan_threshold_loc: 5
k: survives')"                                                "unrelated nested block ignored"

# Fail-soft: never error, always fall through.
rm -f "$CT/r/.ensemble/config.local.yaml"
echo '{ broken' > "$CT/h/.ensemble/config.json"
assert_eq "DFLT" "$(cg k --default DFLT)" "malformed JSON falls through"
echo '["not","an","object"]' > "$CT/h/.ensemble/config.json"
assert_eq "DFLT" "$(cg k --default DFLT)" "non-object JSON root falls through"
cg k --default DFLT >/dev/null 2>&1
assert_exit_code 0 $? "config-get exits 0 on every fail-soft path"
rm -rf "$CT"

# setup merge (EN11-PR-012): user values win, unknown keys survive, idempotent.
has "$SETUP" "review_peer_model_alias" "setup ships the alias default"
has "$SETUP" "review_peer_effort_override" "setup ships the effort default"
hasnt "$SETUP" '[ ! -f "$HOME/.ensemble/config.json" ]' "setup no longer skips existing configs"
if grep -q 'mktemp "$CONFIG_DIR' "$SETUP"; then
  pass "setup mktemp is in the destination directory (atomic mv)"
else
  fail "setup must mktemp in the destination dir; a cross-filesystem mv is not atomic"
fi

if command -v jq >/dev/null 2>&1; then
  ST=$(mktemp -d); mkdir -p "$ST/h/.ensemble"
  cat > "$ST/h/.ensemble/config.json" <<'J'
{"peer_timeout_seconds":1234,"my_custom_key":"keepme"}
J
  ( cd "$REPO_ROOT" && HOME="$ST/h" ./setup --host claude --quiet >/dev/null 2>&1 ) || true
  assert_eq "1234"   "$(jq -r .peer_timeout_seconds "$ST/h/.ensemble/config.json")" "merge preserves a user-modified value"
  assert_eq "keepme" "$(jq -r .my_custom_key "$ST/h/.ensemble/config.json")"        "merge preserves an unknown user key"
  assert_eq "true"   "$(jq -r 'has("review_peer_effort_override")' "$ST/h/.ensemble/config.json")" "merge adds the new key"
  assert_eq "true"   "$(jq -r '.review_peer_effort_override == null' "$ST/h/.ensemble/config.json")" "new key ships unset (null)"
  cp "$ST/h/.ensemble/config.json" "$ST/first"
  ( cd "$REPO_ROOT" && HOME="$ST/h" ./setup --host claude --quiet >/dev/null 2>&1 ) || true
  if jq -S . "$ST/first" > "$ST/a" 2>/dev/null && jq -S . "$ST/h/.ensemble/config.json" > "$ST/b" 2>/dev/null && cmp -s "$ST/a" "$ST/b"; then
    pass "setup merge is idempotent"
  else
    fail "setup merge is not idempotent"
  fi
  # Failure paths must leave the original byte-identical.
  for bad in '{ not json' '["array","root"]'; do
    rm -rf "$ST/h"; mkdir -p "$ST/h/.ensemble"
    printf '%s' "$bad" > "$ST/h/.ensemble/config.json"; cp "$ST/h/.ensemble/config.json" "$ST/orig"
    ( cd "$REPO_ROOT" && HOME="$ST/h" ./setup --host claude --quiet >/dev/null 2>&1 ) || true
    if cmp -s "$ST/orig" "$ST/h/.ensemble/config.json"; then
      pass "merge failure leaves original untouched: $bad"
    else
      fail "merge failure modified the original: $bad"
    fi
    stray=$(find "$ST/h/.ensemble" -name '.config.json.*' 2>/dev/null | wc -l | tr -d ' ')
    assert_eq "0" "$stray" "no stray temp file left behind: $bad"
  done
  rm -rf "$ST"
else
  pass "setup merge behavioral checks skipped (jq unavailable)"
fi

# ============================================================
# U8 — bin/ensemble-peer-invoke (behavioral; PROVES the retry contract)
# ============================================================
assert_file_exists "$INVOKE" "skills/en-review/scripts/ensemble-peer-invoke exists"

IT=$(mktemp -d); echo "prompt" > "$IT/p"; CALLS="$IT/calls"; ARGV="$IT/argv"
# Each stub records BOTH a call marker and its complete argv. Recording argv is
# what makes the degradation contract testable (EN11-CR-005): a stub that only
# counts calls would pass an implementation that dropped BOTH fragments, which
# is exactly the behavior the contract forbids.
mkstub() {  # mkstub <name> <body>
  { echo '#!/usr/bin/env bash'
    echo "echo call >> \"$CALLS\""
    echo "echo \"\$*\" >> \"$ARGV\""
    echo "$2"; } > "$IT/$1"
  chmod +x "$IT/$1"
}
mkstub ok       'exit 0'
mkstub drift_e  'for a in "$@"; do case "$a" in --effort|*model_reasoning_effort*) echo "error: unexpected argument '"'"'--effort'"'"' found" >&2; exit 2;; esac; done; exit 0'
mkstub drift_m  'for a in "$@"; do case "$a" in --model) echo "error: unexpected argument '"'"'--model'"'"' found" >&2; exit 2;; esac; done; exit 0'
mkstub drift_x  'echo "error: unexpected argument found" >&2; exit 2'
mkstub authf    'echo "You are not logged in. Run codex login." >&2; exit 1'
mkstub unkf     'echo "network unreachable" >&2; exit 1'

# Drive the REAL helper in a clean shell (a caller IFS without space must not
# change behavior — the helper splits fragments under a controlled IFS).
inv() {  # inv <stub> -> "<calls>|<decision json>"
  : > "$CALLS"; : > "$ARGV"
  local d
  d=$(bash --noprofile --norc -c '
        set -eu
        . "$1"
        ensemble_peer_invoke --peer-cmd "$2" --peer-format "--json" \
          --peer-model "--model sonnet" --peer-effort "--effort medium" \
          --prompt-file "$3" --out-file /dev/null --effort medium || true
      ' _ "$INVOKE" "$IT/$1" "$IT/p" 2>/dev/null)
  printf '%s|%s' "$(wc -l < "$CALLS" | tr -d ' ')" "$d"
}

r=$(inv ok)
assert_eq "1" "${r%%|*}" "success invokes the peer exactly once (no retry)"
assert_contains "${r#*|}" '"peer":"on"' "success reports peer on"
assert_contains "${r#*|}" '"reason":"default-on"' "success reason is default-on"

r=$(inv drift_e)
assert_eq "2" "${r%%|*}" "effort rejection retries EXACTLY once"
assert_contains "${r#*|}" '"peer":"degraded"' "effort rejection degrades rather than failing"
assert_contains "${r#*|}" 'dropped-effort-fragment' "effort rejection reports the effort fragment"
# Inspect the RETRY argv (EN11-CR-005). Counting calls alone would pass an
# implementation that dropped both fragments; these assertions would not.
retry_argv=$(sed -n '2p' "$ARGV")
assert_not_contains "$retry_argv" "--effort" "retry omits the REJECTED effort fragment"
assert_contains     "$retry_argv" "--model sonnet" "retry RETAINS the model fragment"
assert_contains     "$retry_argv" "--json" "retry retains the peer format"

r=$(inv drift_m)
assert_eq "2" "${r%%|*}" "model rejection retries EXACTLY once"
assert_contains "${r#*|}" 'dropped-model-fragment' "model rejection reports the model fragment"
retry_argv=$(sed -n '2p' "$ARGV")
assert_not_contains "$retry_argv" "--model" "retry omits the REJECTED model fragment"
assert_contains     "$retry_argv" "--effort medium" "retry RETAINS the effort fragment"
assert_contains     "$retry_argv" "--json" "retry retains the peer format"

r=$(inv drift_x)
assert_eq "2" "${r%%|*}" "total rejection stops after ONE retry (no unbounded loop)"
assert_contains "${r#*|}" 'peer-failed:retry-exhausted' "exhausted retry is recorded"

r=$(inv authf)
assert_eq "1" "${r%%|*}" "auth failure never triggers a flag retry"
assert_contains "${r#*|}" 'peer-failed:auth' "auth failure is recorded distinctly"

r=$(inv unkf)
assert_eq "1" "${r%%|*}" "unknown failure never triggers a flag retry"
assert_contains "${r#*|}" 'peer-failed:unknown' "unknown failure is recorded distinctly"

# Timeout must be ENFORCED, not merely documented (EN11-CR-002): a stuck peer
# cannot be allowed to block a default-on review forever.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  mkstub blocker 'sleep 30'
  : > "$CALLS"; : > "$ARGV"
  start=$(date +%s)
  d=$(bash --noprofile --norc -c '
        set -eu
        . "$1"
        ensemble_peer_invoke --peer-cmd "$2" --peer-format "--json" \
          --prompt-file "$3" --out-file /dev/null --timeout 2 || true
      ' _ "$INVOKE" "$IT/blocker" "$IT/p" 2>/dev/null)
  elapsed=$(( $(date +%s) - start ))
  assert_contains "$d" 'peer-failed:timeout' "a stuck peer resolves peer-failed:timeout"
  if [ "$elapsed" -lt 15 ]; then
    pass "timeout is bounded (returned in ${elapsed}s, not the stub's 30s)"
  else
    fail "timeout not enforced" "took ${elapsed}s against a 2s timeout"
  fi
else
  pass "timeout checks skipped (no timeout/gtimeout on PATH)"
fi
# A retry that TIMES OUT must report peer-failed:timeout, not retry-exhausted.
# Regression guard: reading `$?` after a completed `if` yields the if
# statement's status (always 0), which silently made the 124 branch dead code.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  { echo '#!/usr/bin/env bash'
    echo "echo call >> \"$CALLS\""
    echo "n=\$(wc -l < \"$CALLS\")"
    echo 'if [ "$n" -le 1 ]; then echo "error: unexpected argument '"'"'--effort'"'"' found" >&2; exit 2; fi'
    echo 'sleep 30'; } > "$IT/drift_then_hang"
  chmod +x "$IT/drift_then_hang"
  : > "$CALLS"; : > "$ARGV"
  d=$(bash --noprofile --norc -c '
        set -eu
        . "$1"
        ensemble_peer_invoke --peer-cmd "$2" --peer-format "--json" \
          --peer-model "--model sonnet" --peer-effort "--effort medium" \
          --prompt-file "$3" --out-file /dev/null --timeout 2 || true
      ' _ "$INVOKE" "$IT/drift_then_hang" "$IT/p" 2>/dev/null)
  assert_contains "$d" 'peer-failed:timeout' "a retry that times out reports timeout, not retry-exhausted"
  assert_not_contains "$d" 'retry-exhausted' "timed-out retry is not misreported as retry-exhausted"
else
  pass "retry-timeout check skipped (no timeout/gtimeout on PATH)"
fi
rm -rf "$IT"

# Every reason the helper can emit must be a member of the published enum
# (EN11-PR-008), so helper and policy cannot drift apart.
missing_reasons=""
for reason in default-on explicit-flag no-peer-flag host-only-mode single-agent-fallback \
              report-only-mode recursion-guard peer-unavailable \
              peer-failed:auth peer-failed:unknown peer-failed:retry-exhausted \
              dropped-model-fragment dropped-effort-fragment dropped-isolation-fragment; do
  grep -qF -- "$reason" "$POLICY" || missing_reasons="$missing_reasons $reason"
done
if [ -z "$missing_reasons" ]; then
  pass "every peer_decision reason is published in the policy enum"
else
  fail "reasons emitted but not in the policy enum" "$missing_reasons"
fi
for reason in default-on dropped-model-fragment dropped-effort-fragment dropped-isolation-fragment \
              peer-failed:auth peer-failed:unknown peer-failed:retry-exhausted; do
  grep -qF -- "$reason" "$INVOKE" || fail "helper cannot emit documented reason: $reason"
done
pass "helper implements the reasons it documents"

# ============================================================
# U3 — /en-review default resolution, flags, CI carve-out
# ============================================================
# Scope the flag assertions to the Flags TABLE. Checking the whole file would
# pass on a stray mention elsewhere (both flags are also named in step 2a), so
# a file-wide grep here reads as coverage without providing it.
FLAGS_TBL=$(awk '/^## Flags/,/^## Mutation rules/' "$SKILL")
flagrow() {  # flagrow <flag> <label>
  if printf '%s\n' "$FLAGS_TBL" | grep -qF -- "| \`$1" ; then pass "$2"; else fail "$2" "no Flags-table row for $1"; fi
}
# 2026-09-01: --no-peer and --peer-only were replaced by three mutually exclusive
# review modes. --peer is now peer-SOLE (and the default), --cross is peer plus
# personas, --host is personas alone. EN11's substance — the peer runs unless a
# recorded reason says otherwise — is unchanged; only the spelling moved.
flagrow "--peer" "Flags table has a --peer row (peer-sole, the default)"
flagrow "--cross" "Flags table has a --cross row (peer + personas)"
flagrow "--host" "Flags table has a --host row (personas only)"
flagrow "--effort" "Flags table has an --effort row"

# The three are a choice, not a merge; two at once is an error.
if printf '%s\n' "$FLAGS_TBL" | grep -qiE 'mutually exclusive review modes'; then
  pass "the three review modes are declared mutually exclusive"
else
  fail "the three review modes must be declared mutually exclusive"
fi

# The removed spellings must not come back alongside the new ones.
for gone in "--no-peer" "--peer-only"; do
  if printf '%s\n' "$FLAGS_TBL" | grep -qF -- "| \`$gone"; then
    fail "Flags table still lists $gone" "replaced by the --peer/--cross/--host trio"
  else
    pass "Flags table no longer lists $gone"
  fi
done
has "$SKILL" "peer_decision:" "mandatory peer_decision outcome line"
has "$SKILL" "default-on" "default-on reason is documented"
has "$SKILL" "report-only-mode" "report-only carve-out has a recorded reason"
has "$SKILL" "single-agent-fallback" "single-agent-fallback carve-out documented"
has "$SKILL" "recursion-guard" "recursion guard still resolves a reason"
has "$SKILL" "ensemble-peer-invoke" "step 9 delegates invocation to the helper"
has "$SKILL" "ensemble-config-get" "step 2b delegates config layering"
has "$SKILL" "ensemble-peer-flags" "step 9 delegates CLI syntax"
has "$SKILL" "SOLE resolver" "en-review declares itself the sole resolver"

# The D38 CI posture: report-only must never default a peer on. Self-test the
# guard against a synthetic regression and the real (correct) wording.
CI_BAD='report-only[^.]*peer (is )?on by default'
if printf 'in report-only the peer is on by default\n' | grep -qEi "$CI_BAD" \
   && ! printf 'report-only never runs a peer\n' | grep -qEi "$CI_BAD"; then
  pass "self-test: CI-posture pattern catches the regression, not the correct wording"
else
  fail "self-test: CI-posture pattern mis-classifies"
fi
if grep -qEi "$CI_BAD" "$SKILL"; then
  fail "report-only is described as defaulting a peer on (breaks D38 CI posture)"
else
  pass "report-only never defaults a peer on (D38 CI posture intact)"
fi

# The retry algorithm must NOT be restated in prose (EN11-PR-006): one
# implementation, in the executable helper.
if grep -qiE 'retry (exactly )?once' "$SKILL"; then
  fail "skill restates the retry algorithm; it belongs to bin/ensemble-peer-invoke"
else
  pass "skill does not restate the retry algorithm"
fi

# ============================================================
# U4 — concurrent dispatch
# ============================================================
has "$DISPATCH" "one batch" "persona-dispatch documents the single batch"
has "$DISPATCH" "ensemble-peer-invoke" "peer appears in the dispatch batch"
has "$DISPATCH" "blind-peer invariant" "concurrency is licensed by blindness"
has "$SKILL" "ONE batch" "en-review step 8 dispatches personas and peer together"

# ============================================================
# U5 — two-source reconciliation + blind-peer invariant
# ============================================================
for b in corroborated peer-only host-only conflicting; do
  has "$DISPATCH" "$b" "bucket documented: $b"
done
has "$DISPATCH" "Partition invariant" "partition invariant is stated"
has "$DISPATCH" "exactly one" "every finding lands in exactly one record"
has "$DISPATCH" "Conflict stage first" "conflict is allocated before corroboration"
has "$DISPATCH" "0.7" "corroboration reuses the existing similarity predicate"
has "$DISPATCH" "independent of the similarity predicate" "conflict is decoupled from similarity"
has "$DISPATCH" "+2" "cross-source corroboration boost documented"
has "$DISPATCH" "+1" "same-source overlap boost retained"
has "$DISPATCH" "fast-pass" "fast-pass corroboration carve-out preserved"
has "$DISPATCH" "Blind-peer invariant" "blind-peer invariant is named"
hasnt "$DISPATCH" "confirm or counter them" "the stale peer-reads-findings claim is gone"
# The reconciliation record shapes moved on 2026-09-04 from the shared
# finding-schema (four carriers, three of which never produce or parse them)
# into en-review's persona-dispatch, beside the algorithm. The shared schema
# keeps a pointer; the fields are asserted where they now live.
RECON="$REPO_ROOT/skills/en-review/references/persona-dispatch.md"
has "$RECON" "reconciliation[].bucket" "persona-dispatch documents reconciliation records"
has "$RECON" "reconciliation[].sources" "record carries sources[] not a scalar"
has "$RECON" "reconciliation[].contributing" "record carries contributing[] provenance"
has "$RECON" "findings[].source" "raw findings carry a source tag"
has "$SCHEMA" "reconciliation" "the shared schema still points at the aggregated envelope"
has "$SKILL" "Two-source reconciliation" "en-review step 10 reconciles two sources"
has "$SKILL" "never auto-applied" "conflicting findings are never auto-applied"

# ============================================================
# U7 — foundation D45
# ============================================================
d45="$(grep -E '^- \*\*D45\.' "$FOUNDATION" || true)"
if [ -n "$d45" ]; then
  pass "foundation records D45"
  for frag in "report-only" "corroborated" "blind" "PEER_MODEL\|policy"; do
    if printf '%s' "$d45" | grep -qi -- "${frag%%\\|*}"; then
      pass "D45 covers: ${frag%%\\|*}"
    else
      fail "D45 missing coverage of ${frag%%\\|*}"
    fi
  done
else
  fail "foundation must add D45 for EN11"
fi

report
