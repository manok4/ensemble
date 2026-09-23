#!/usr/bin/env bash
# tests/linear-plan/linear-plan.test.sh
#
# ensemble-linear-plan owns every Linear data transform (EN19 U1, D119). EN18
# left them to the model, so none could carry a negative control; these tests
# are that control. Every rule here is observed through the script's CLI over
# fixtures in tests/fixtures/linear/, never by grepping prose.
#
# Fixtures:
#   EN18-sample-plan.md    the source plan
#   EN18-readback.json     a LIVE capture of two units (EN18 U1)
#   EN19-readback.json     render of the source, with Linear's measured marker
#                          rewrite applied and units reversed (synthetic)
#   EN19-rendered-plan.md  the golden materialize output of EN19-readback.json

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="linear plan transforms"

L="$REPO_ROOT/skills/en-build/scripts/ensemble-linear-plan"
H="$REPO_ROOT/skills/en-build/scripts/ensemble-plan-hash"
FX="$REPO_ROOT/tests/fixtures/linear"
SRC="$FX/EN18-sample-plan.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

if ! command -v python3 >/dev/null 2>&1; then
  pass "SKIPPED: python3 not installed; ensemble-linear-plan needs it"
  report; exit 0
fi

lp() { python3 "$L" "$@"; }
# A JSON edit, applied with python so the tests do not depend on jq.
jedit() {  # <in> <out> <python expression over d>
  python3 - "$1" "$2" "$3" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
exec(sys.argv[3])
json.dump(d, open(sys.argv[2], "w"), indent=1, ensure_ascii=False)
PY
}
# Linear's measured transformation, for readbacks built inside a test.
linearize() {  # <payload.json> <readback.json> [extra python over rb]
  python3 - "$1" "$2" "${3:-}" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
rw = lambda s: re.sub(r'(?m)^(\s*(?:>\s*)*)- ', r'\1* ', s)
rb = {"parent": {"identifier": "T-1", "title": d["parent"]["title"],
                 "description": rw(d["parent"]["description"])},
      "sub_issues": [{"identifier": f"T-{i+2}", "title": u["title"], "status": "Agent Ready",
                      "description": rw(u["description"])} for i, u in enumerate(d["units"])]}
exec(sys.argv[3])
json.dump(rb, open(sys.argv[2], "w"), indent=1, ensure_ascii=False)
PY
}

# --- 1. the golden round trip -------------------------------------------------
lp materialize "$FX/EN19-readback.json" --out "$WORK/golden.md"; rc=$?
assert_eq "0" "$rc" "materialize accepts the EN19 read-back"
if cmp -s "$WORK/golden.md" "$FX/EN19-rendered-plan.md"; then
  pass "materialize reproduces the committed golden file byte for byte"
else
  fail "materialize reproduces the committed golden file" "$(diff "$FX/EN19-rendered-plan.md" "$WORK/golden.md" | head -8)"
fi
# The golden file is not the only witness: the independent source must agree,
# or a wrong golden file would pass the check above by construction.
assert_eq "$(bash "$H" "$SRC")" "$(bash "$H" "$WORK/golden.md")" \
  "the round trip keeps the default plan hash of the source"
assert_eq "$(bash "$H" --full "$SRC")" "$(bash "$H" --full "$WORK/golden.md")" \
  "and the --full hash, which covers every field and plan-level section"
body() { sed '1,/^---$/d' "$1" | sed '1,/^---$/d'; }
assert_eq "$(body "$SRC")" "$(body "$WORK/golden.md")" \
  "the plan body, Context and Technical design included, survives byte for byte"
lp verify "$SRC" "$FX/EN19-readback.json" 2>"$WORK/err"; rc=$?
assert_eq "0" "$rc" "verify accepts a faithful read-back"

# --- 2. negative control: the marker rewrite is what materialize repairs -------
# Rebuilt WITHOUT normalization, the units hash as seven empty fields each. A
# test that only checked "materialize succeeded" would pass against that bug.
python3 - "$FX/EN19-readback.json" "$WORK/raw.md" <<'PY'
import json, re, sys
rb = json.load(open(sys.argv[1]))
fm = re.search(r"```yaml\n(.*?)\n```", rb["parent"]["description"], re.S).group(1)
units = sorted(rb["sub_issues"], key=lambda s: int(re.search(r"\(U(\d+)\)", s["title"]).group(1)))
uid = lambda u: re.search(r"(U\d+)", u["title"]).group(1)
body = "\n\n".join("### " + uid(u) + ". x\n\n" + u["description"] for u in units)
open(sys.argv[2], "w").write(f"---\n{fm}\n---\n\n## Implementation units\n\n{body}\n")
PY
[ -s "$WORK/raw.md" ] && pass "the un-normalized rebuild was written" || fail "the un-normalized rebuild was written"
assert_ne "$(bash "$H" "$SRC")" "$(bash "$H" "$WORK/raw.md")" \
  "un-normalized read-back does NOT hash like the source (the repair is load-bearing)"
bash "$H" --canon "$WORK/raw.md" | grep -q '^Goal:0:' \
  && pass "and it canonicalizes to empty fields, the silent failure EN18 U1 found" \
  || fail "raw read-back canonicalizes to empty fields"

# --- 3. the live EN18 capture still materializes --------------------------------
# Real Linear bytes for U1 and U2, under the synthetic parent (the capture has
# no parent description). U2's capture carries no Approach, so U1 is the
# field-equality case, as it was in EN18.
jedit "$FX/EN19-readback.json" "$WORK/live.json" '
cap = json.load(open("'"$FX"'/EN18-readback.json"))
d["sub_issues"] = [{"identifier": s["id"], "title": s["title"], "status": s["status"],
                    "description": s["description"]} for s in cap["sub_issues"]]'
lp materialize "$WORK/live.json" --out "$WORK/live.md"; rc=$?
assert_eq "0" "$rc" "materialize accepts the live EN18 capture's sub-issues"
u1() { bash "$H" --canon "$1" | awk '/^U:U1$/{f=1; next} /^U:/{f=0} f && /^(Goal|Files|Approach|Risk|Category|Gated|Dependencies):/'; }
assert_eq "$(u1 "$SRC")" "$(u1 "$WORK/live.md")" "U1's hashed fields from real Linear bytes equal the source's"
order=$(grep -oE '^### U[0-9]+' "$WORK/live.md" | tr '\n' ' ')
assert_eq "### U1 ### U2 " "$order" "units are ordered by U-ID although the capture lists U2 first"

# --- 4. unit order and canceled units ------------------------------------------
order=$(grep -oE '^### U[0-9]+' "$WORK/golden.md" | tr '\n' ' ')
assert_eq "### U1 ### U2 ### U3 ### U4 " "$order" "a reversed read-back materializes in U-ID order"

# An amend that removes U3: the parent carries the revised plan's contract and
# U3's sub-issue is canceled, not deleted (the MCP server has no delete tool).
awk '/^### U3\./{skip=1; next} /^### U4\./{skip=0} !skip' "$SRC" > "$WORK/minus3.md"
lp render "$WORK/minus3.md" --repo github.com/example/ensemble > "$WORK/minus3.json"
linearize "$WORK/minus3.json" "$WORK/minus3-rb.json" '
rb["sub_issues"].append({"identifier": "T-9", "title": "Document the trailer (U3)", "status": "Canceled", "description": "old"})'
lp verify "$WORK/minus3.md" "$WORK/minus3-rb.json" 2>"$WORK/err"; rc=$?
assert_eq "0" "$rc" "a canceled sub-issue is not a unit, so removing U3 still verifies"
lp materialize "$WORK/minus3-rb.json" | grep -q '^### U3\.' \
  && fail "a canceled unit must not be materialized" \
  || pass "the canceled U3 is not materialized"

# --- 5. refusals ------------------------------------------------------------------
expect_refusal() {  # <label> <readback> <stderr pattern>
  lp materialize "$2" >/dev/null 2>"$WORK/err"; local rc=$?
  if [ "$rc" -eq 3 ] && grep -qE -- "$3" "$WORK/err"; then pass "$1"
  else fail "$1" "rc=$rc err=$(cat "$WORK/err")"; fi
}
jedit "$FX/EN19-readback.json" "$WORK/trunc.json" '
u = [s for s in d["sub_issues"] if "(U2)" in s["title"]][0]
u["description"] = u["description"][:200] + "... (truncated, use get_issue for full description)"'
expect_refusal "a truncated unit description refuses, naming the unit" "$WORK/trunc.json" 'U2.*truncated'
jedit "$FX/EN19-readback.json" "$WORK/dup.json" '
u = [s for s in d["sub_issues"] if "(U2)" in s["title"]][0]
d["sub_issues"].append(dict(u, identifier="EMB-99"))'
expect_refusal "two live sub-issues claiming U2 refuse, naming both" "$WORK/dup.json" 'U2.*EMB-1[0-9].*EMB-99|U2.*EMB-99'
jedit "$FX/EN19-readback.json" "$WORK/nosuffix.json" '
d["sub_issues"][0]["title"] = "A unit with no suffix"'
expect_refusal "a sub-issue title with no (U<N>) suffix refuses" "$WORK/nosuffix.json" 'no \(U<N>\) suffix'
jedit "$FX/EN19-readback.json" "$WORK/nocontract.json" '
d["parent"]["description"] = d["parent"]["description"].split("## Verification Contract")[0]'
expect_refusal "a parent without a Verification Contract refuses" "$WORK/nocontract.json" 'Verification Contract'

# --- 6. verify catches plan-level edits, and only real ones ----------------------
jedit "$FX/EN19-readback.json" "$WORK/scope.json" '
d["parent"]["description"] = d["parent"]["description"].replace("## Out of scope (deliberately)", "## Out of scope (deliberately)\n\n* **Also:** ship a dashboard.", 1)'
lp verify "$SRC" "$WORK/scope.json" 2>"$WORK/err"; rc=$?
assert_eq "3" "$rc" "an edit to Out of scope made in Linear fails verify"
grep -q 'Out of scope' "$WORK/err" && pass "and the report names the section" || fail "verify names the section" "$(head -3 "$WORK/err")"
lp materialize "$WORK/scope.json" --out "$WORK/scope.md"
assert_ne "$(bash "$H" --full "$SRC")" "$(bash "$H" --full "$WORK/scope.md")" "the same edit moves --full"

{ cat "$SRC"; printf '\n## Iteration log\n\n- 2026-09-22: first entry.\n'; } > "$WORK/withlog.md"
lp render "$WORK/withlog.md" --repo github.com/example/ensemble > "$WORK/withlog.json"
linearize "$WORK/withlog.json" "$WORK/withlog-rb.json" '
rb["parent"]["description"] = rb["parent"]["description"].replace("first entry.", "first entry.\n* 2026-09-23: a later entry.")'
lp verify "$WORK/withlog.md" "$WORK/withlog-rb.json" 2>"$WORK/err"; rc=$?
assert_eq "0" "$rc" "an Iteration log-only difference passes verify"
lp materialize "$WORK/withlog-rb.json" --out "$WORK/withlog-rt.md"
assert_eq "$(bash "$H" --full "$WORK/withlog.md")" "$(bash "$H" --full "$WORK/withlog-rt.md")" \
  "and leaves --full unchanged, the same rule on both sides"

# --- 7. awkward content survives --------------------------------------------------
cat > "$WORK/awkward.md" <<'PLAN'
---
type: plan
plan_id: EN98
title: Awkward content
status: open
depth: standard
data_scale: small
---

# EN98: Awkward content

## Context

A request quoted from an issue, headings and all:

> ## Implementation units
> - a bullet inside the quote
> - **Goal:** not a real field

## Implementation units

### U1. Nested lists and code

- **Goal:** survive the trip
- **Files:** `a.sh`, `b.py`
- **Approach:** handle `--flag` and `{a,b}`:
  - first, a nested bullet
    - and a deeper one
  - then `code => spans`
- **Risk:** low
- **Category:** feature
- **Gated:** false
- **Dependencies:** none
- **Test scenarios:**
  - *Happy path:* it works

### U2. Second

- **Goal:** depend on U1
- **Dependencies:** U1
PLAN
lp render "$WORK/awkward.md" --repo github.com/example/ensemble > "$WORK/awkward.json"; rc=$?
assert_eq "0" "$rc" "render accepts a plan whose quoted Context carries its own headings"
assert_eq "U1 U2 " "$(python3 -c 'import json,sys;print("".join(u["u_id"]+" " for u in json.load(open(sys.argv[1]))["units"]))' "$WORK/awkward.json")" \
  "a blockquoted \`## Implementation units\` does not open the units section"
assert_eq '["U1"]' "$(python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1]))["units"][1]["blocked_by"]))' "$WORK/awkward.json")" \
  "blocked_by comes from the unit's Dependencies"
linearize "$WORK/awkward.json" "$WORK/awkward-rb.json"
lp materialize "$WORK/awkward-rb.json" --out "$WORK/awkward-rt.md"
assert_eq "$(body "$WORK/awkward.md")" "$(body "$WORK/awkward-rt.md")" \
  "nested lists, code spans and a quoted report round-trip byte for byte"
lp verify "$WORK/awkward.md" "$WORK/awkward-rb.json" 2>"$WORK/err"; rc=$?
assert_eq "0" "$rc" "and verify accepts it"

# --- 7b. idempotent round trip (EN19 U6) -----------------------------------------
# An amend materializes the published plan and later re-renders it. If render
# of a materialized plan differed from render of the source, every amend would
# rewrite unchanged units in Linear.
lp render "$SRC" --repo github.com/example/ensemble > "$WORK/r1.json"
lp render "$WORK/golden.md" --repo github.com/example/ensemble > "$WORK/r2.json"
if cmp -s "$WORK/r1.json" "$WORK/r2.json"; then
  pass "rendering a materialized plan reproduces the original payload"
else
  fail "rendering a materialized plan reproduces the original payload" "$(diff "$WORK/r1.json" "$WORK/r2.json" | head -6)"
fi

# --- 8. repo identity ------------------------------------------------------------
R="$WORK/repo"; mkdir -p "$R"; cp "$SRC" "$R/plan.md"
( cd "$R" && git init -q . ) >/dev/null 2>&1
lp render "$R/plan.md" >/dev/null 2>"$WORK/err"; rc=$?
[ "$rc" -eq 3 ] && grep -q 'origin' "$WORK/err" \
  && pass "render refuses a repo with no origin remote" \
  || fail "render refuses a repo with no origin remote" "rc=$rc $(cat "$WORK/err")"
( cd "$R" && git remote add origin git@github.com:Owner/Name.git )
assert_eq "github.com/owner/name" "$(lp render "$R/plan.md" | python3 -c 'import json,sys;print(json.load(sys.stdin)["repo"])')" \
  "an scp-style origin normalizes to host/owner/name, lowercased, without .git"
( cd "$R" && git remote set-url origin https://user:tok@GitHub.com/Owner/Name.git/ )
assert_eq "github.com/owner/name" "$(lp render "$R/plan.md" | python3 -c 'import json,sys;print(json.load(sys.stdin)["repo"])')" \
  "an https origin with userinfo normalizes to the same identity"

# --- 9. carriers --------------------------------------------------------------------
cmp -s "$L" "$REPO_ROOT/skills/en-plan/scripts/ensemble-linear-plan" \
  && pass "en-plan and en-build carry the same script" \
  || fail "en-plan and en-build carry the same script"

report
