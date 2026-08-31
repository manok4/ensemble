#!/usr/bin/env bash
# tests/lint/skill-payload-reachable.test.sh
#
# The self-contained guard checks that everything a skill NAMES resolves inside
# it. This checks the other direction: that everything a skill CARRIES is
# reachable from its own flow.
#
# Nothing checked that direction, and the answer was 5,010 lines. en-plan shipped
# en-build's two execution flavors under a hard gate against building anything;
# en-foundation and en-review shipped the build-time evidence verifier;
# en-cross-review, en-ship and en-simplify each shipped three research agents
# while mentioning research nowhere in their own flow.
#
# Reachability follows every way one carried file can name another, and each of
# these was learned by getting it wrong first:
#
#   backticked asset paths        `references/x.md`
#   paths inside command strings  --brief references/peer-brief.md
#   subagent_type recipes         subagent_type: "dimension-reviewer"
#   bare-name prose dispatch      dispatch the `web-research` agent
#   helpers run through a var     python3 "$SCRIPT_DIR/guardrail_analyze.py"
#   scripts/ OR bin/              en-guardrail uses bin/
#
# EXEMPTIONS are for files no flow reaches BY DESIGN — a deliverable the user or
# another skill invokes directly. Each must name its invoker, so the list cannot
# grow into a place to hide genuine dead payload.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="skill payload is reachable"
cd "$REPO_ROOT"

OUT=$(python3 - <<'PY'
import re, os, glob
ASSET  = re.compile(r'(?:references|templates|agents|scripts|bin)/[A-Za-z0-9._/-]+')
SUBAG  = re.compile(r'subagent_type:\s*"([a-z][a-z-]*)"')
VARREF = re.compile(r'\$[A-Za-z_]+"?/([A-Za-z0-9_.-]+)')

# file -> the invoker that reaches it from outside its own skill
EXEMPT = {('en-guardrail', 'bin/install-guardrail'): '/en-setup, and the user directly'}

def norm(skill, p):
    for c in (p, p.replace('bin/', 'scripts/'), p.replace('scripts/', 'bin/')):
        if os.path.exists(os.path.join(skill, c)):
            return c
    return None

def reaches(skill, rel, agents):
    try: t = open(os.path.join(skill, rel), errors='ignore').read()
    except Exception: return set()
    out = set()
    for m in ASSET.findall(t):
        n = norm(skill, m)
        if n: out.add(n)
    for a in SUBAG.findall(t) :
        n = norm(skill, f'agents/{a}.md')
        if n: out.add(n)
    for a in agents:
        if re.search(r'\b%s\b' % re.escape(a), t):
            n = norm(skill, f'agents/{a}.md')
            if n: out.add(n)
    if rel.startswith(('scripts/', 'bin/')):
        for v in VARREF.findall(t):
            for d in ('scripts', 'bin'):
                n = norm(skill, f'{d}/{v}')
                if n: out.add(n); break
    return out

bad = []
for skill in sorted(glob.glob('skills/*/')):
    name = os.path.basename(skill.rstrip('/'))
    lines = open(os.path.join(skill, 'SKILL.md')).read().split('\n')
    i0 = next(n for n, l in enumerate(lines) if l.startswith('requires:'))
    i = i0 + 1; declared = []
    while i < len(lines) and lines[i].startswith('  - '):
        declared.append(lines[i][4:].strip()); i += 1
    body = '\n'.join(l for n, l in enumerate(lines) if not (i0 <= n < i))
    agents = [os.path.basename(p)[:-3] for p in glob.glob(os.path.join(skill, 'agents/*.md'))]

    roots = set()
    for m in ASSET.findall(body):
        n = norm(skill, m)
        if n: roots.add(n)
    for a in SUBAG.findall(body):
        n = norm(skill, f'agents/{a}.md')
        if n: roots.add(n)
    for a in agents:
        if re.search(r'`%s`' % re.escape(a), body):
            n = norm(skill, f'agents/{a}.md')
            if n: roots.add(n)

    seen, st = set(), list(roots)
    while st:
        n = st.pop()
        if n in seen: continue
        seen.add(n); st.extend(e for e in reaches(skill, n, agents) if e not in seen)

    for d in declared:
        if d in seen or (name, d) in EXEMPT: continue
        n = sum(1 for _ in open(os.path.join(skill, d), errors='ignore'))
        bad.append(f'{name}:{d}({n}L)')

print(' '.join(bad))
PY
) || { fail "the reachability walk could not run" "python3 required"; report; exit 0; }

if [ -z "$OUT" ]; then
  pass "every skill's declared payload is reachable from its own flow"
else
  fail "every skill's declared payload is reachable from its own flow" "$OUT"
fi

# An exemption that no longer names a real file is a hole, not an exemption.
if [ -f "skills/en-guardrail/bin/install-guardrail" ]; then
  pass "the one exemption still points at a real file"
else
  fail "the exemption list is stale" "en-guardrail/bin/install-guardrail is gone"
fi

report
