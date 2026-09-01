#!/usr/bin/env python3
"""Derive a skill's payload from its own markdown, instead of a declared manifest.

Ported from compound-engineering-plugin's skill-conventions.test.ts, whose rules
were themselves settled by auditing every references/-, scripts/- and assets/-
mentioning line across its skills. Each rule below exists because the naive
version of it produced a wrong answer on a real file in this repo.

WHAT COUNTS AS NAMING A FILE

  1. A path token inside a backtick span, whether the span IS the path
     (`references/x.md`) or embeds it in a command (`bash scripts/x`,
     `python3 scripts/foo.py <arg>`). Commands matter: a renamed script that is
     only ever mentioned as an invocation must still be caught.

  2. A markdown link or image target (`[text](references/x.md)`) outside a fence.

  3. The same path tokens inside FENCED code blocks. Fences are where real
     bundled invocations live, so skipping them would let a deleted script pass
     while the skill breaks at runtime. Markdown-link syntax inside a fence is
     NOT a candidate — that is teaching material, and its brackets fail the
     bare-token shape.

  4. A bare agent name in a dispatch: subagent_type: "x" anywhere, or a
     backticked `x` in SKILL.md matching a file in agents/.

WHAT DELIBERATELY DOES NOT COUNT

  - Bare path tokens in prose with no backticks, link, or fence. Unmarked prose
    is where hypothetical and illustrative paths live, and treating them as
    dependencies is what made a comparison in peer-model-policy.md drag 1,024
    lines of build machinery into a skill that never builds.

  - Directory-only mentions (`references/` with no filename): they name no file.

  - Paths that do not resolve inside the skill. A sibling skill's file is a
    self-containment violation, caught by its own guard, not a payload entry.

NORMALISATION

  Variable prefixes are stripped: `${VAR}/`, `${VAR:-default}/` and `$VAR/` all
  mean skill-root-relative by this repo's documented invocation style, so
  `bash "$SKILL_DIR/scripts/x"` yields `scripts/x`. Surrounding quotes go too.
  bin/ and scripts/ are interchangeable — en-guardrail keeps helpers in bin/.

SIBLING RESOLUTION INSIDE SCRIPTS

  A carried script calls its helpers by a path relative to itself, with no
  asset-directory prefix to match on: check-guardrail.sh runs
  `python3 "$SCRIPT_DIR/guardrail_analyze.py"`. Stripping the variable leaves a
  bare filename, so a prefix-anchored token rule cannot see it and the analyzer
  looks like dead payload. Inside a non-markdown file, therefore, a token with a
  file extension is resolved against that file's OWN directory as well. The
  filesystem is the filter: a token that does not resolve to a file inside the
  skill is not a dependency, so ordinary words and foreign paths drop out.
"""

import os, re, sys, glob

ASSET_DIRS = ('references', 'scripts', 'bin', 'agents', 'templates', 'assets')
DIR_ALT = '|'.join(ASSET_DIRS)

# A path token: dir/ + at least one more segment. Trailing punctuation that
# markdown prose attaches (period, comma, colon, paren) is not part of a path.
TOKEN = re.compile(rf'(?:{DIR_ALT})/[A-Za-z0-9._/-]*[A-Za-z0-9_-]')
VAR_PREFIX = re.compile(r'\$\{?[A-Za-z_][A-Za-z0-9_]*(?::-[^}]*)?\}?/')
BACKTICK = re.compile(r'`([^`\n]+)`')
MDLINK = re.compile(r'\[[^\]]*\]\(([^)\s]+)\)')
SUBAGENT = re.compile(r'subagent_type:\s*"([a-z][a-z0-9-]*)"')


# No extension required: shell helpers are sourced by bare name. Resolution
# against the script's own directory is what filters this, not the token shape.
SIBLING = re.compile(r'[A-Za-z0-9_.-]{3,}')


def _norm(skill, raw, base=''):
    """A raw token -> a skill-relative path that exists, or None."""
    t = raw.strip().strip('"\'')
    t = VAR_PREFIX.sub('', t)
    t = t.lstrip('./')
    if not t or t.endswith('/'):
        return None
    cands = [t, t.replace('bin/', 'scripts/', 1), t.replace('scripts/', 'bin/', 1)]
    if base:
        cands.append(os.path.join(base, t))
    for cand in cands:
        if os.path.isfile(os.path.join(skill, cand)):
            return cand
    return None


def _named_in(skill, text, agents, base=''):
    """Every payload path this text names, by the rules above."""
    found = set()

    # A script's helpers are named relative to the script, not to the skill root.
    # Strictly relative: no skill-root fallback, or this degrades into a bare-token
    # rule that ignores the backtick requirement and matches every prose mention of
    # SKILL.md. Scripts only — in markdown, the backtick rules already apply.
    if base:
        for m in SIBLING.findall(text):
            cand = os.path.join(base, m.strip('"\''))
            if os.path.isfile(os.path.join(skill, cand)):
                found.add(cand)

    for span in BACKTICK.findall(text):
        for m in TOKEN.findall(span):
            p = _norm(skill, m, base)
            if p: found.add(p)

    # Link targets, fences stripped first so fenced [text](x) stays teaching material.
    unfenced = re.sub(r'```.*?```', '', text, flags=re.S)
    for target in MDLINK.findall(unfenced):
        p = _norm(skill, target, base)
        if p: found.add(p)

    # Fenced blocks: real invocations live here. Backticks inside a fence act as
    # separators, so tokenising the raw fence body is correct.
    for fence in re.findall(r'```(.*?)```', text, flags=re.S):
        for m in TOKEN.findall(fence):
            p = _norm(skill, m, base)
            if p: found.add(p)

    for a in SUBAGENT.findall(text):
        p = _norm(skill, f'agents/{a}.md')
        if p: found.add(p)

    return found


def _body(skill):
    """SKILL.md with frontmatter removed — the flow, not the header."""
    raw = open(os.path.join(skill, 'SKILL.md'), encoding='utf-8', errors='ignore').read()
    if raw.startswith('---'):
        end = raw.find('\n---', 3)
        if end != -1:
            raw = raw[end + 4:]
    return raw


def derive(skill):
    """Transitive closure of what the skill's flow reaches."""
    agents = [os.path.basename(p)[:-3] for p in glob.glob(os.path.join(skill, 'agents/*.md'))]
    body = _body(skill)

    roots = _named_in(skill, body, agents)
    # A bare backticked agent name in SKILL.md is a dispatch.
    for a in agents:
        if re.search(r'`/?%s`' % re.escape(a), body):
            roots.add(f'agents/{a}.md')

    seen, stack = set(), list(roots)
    while stack:
        n = stack.pop()
        if n in seen:
            continue
        seen.add(n)
        try:
            text = open(os.path.join(skill, n), encoding='utf-8', errors='ignore').read()
        except OSError:
            continue
        nxt = _named_in(skill, text, agents,
                        base=os.path.dirname(n) if not n.endswith('.md') else '')
        # Inside a carried file, a bare agent name is also a dispatch: shared
        # recipes name their agents in prose, not only as subagent_type.
        for a in agents:
            if re.search(r'\b%s\b' % re.escape(a), text):
                p = _norm(skill, f'agents/{a}.md')
                if p: nxt.add(p)
        stack.extend(e for e in nxt if e not in seen)
    return seen


# Ensemble overloads bin/ for two namespaces: helpers a skill CARRIES, and the
# lint script en-setup INSTALLS into a consuming repo's own bin/. Only the first
# is payload. The list is exactly the second kind, and is asserted to stay at one
# entry so it cannot grow into a hole that hides a genuinely dangling path.
# (The other three scripts en-setup installs are written "$SKILL_DIR/scripts/..."
# at their mention sites, so they resolve as carried files and need no exemption.)
CONSUMING_REPO = {'bin/ensemble-lint'}
assert len(CONSUMING_REPO) == 1

# An explicit cross-skill path (skills/en-x/bin/y) is not this skill's payload.
# It is a self-containment violation, which has its own guard; counting it here
# would report it twice and in the wrong vocabulary.
CROSS_SKILL = re.compile(r'skills/[a-z0-9-]+/')


def named_but_absent(skill):
    """Skill-local paths the markdown names that do not exist on disk.

    The other direction, and the one that breaks a lone install: a renamed or
    deleted file whose mentions were not updated sends an agent to read
    something that is not there. Only markdown is scanned — a script naming a
    path it builds at runtime is not a documentation claim.
    """
    out = set()
    files = [os.path.join(skill, 'SKILL.md')] + \
            [p for d in ('references', 'agents') for p in
             glob.glob(os.path.join(skill, d, '**', '*.md'), recursive=True)]
    for f in files:
        if not os.path.isfile(f):
            continue
        text = open(f, encoding='utf-8', errors='ignore').read()
        spans = BACKTICK.findall(text) + MDLINK.findall(re.sub(r'```.*?```', '', text, flags=re.S))
        for span in spans:
            if CROSS_SKILL.search(span):
                continue
            for m in TOKEN.findall(span):
                t = VAR_PREFIX.sub('', m).lstrip('./')
                full = os.path.join(skill, t)
                # A directory mention names no file. A path that resolves under
                # either bin/ or scripts/ is present under this repo's alias.
                if os.path.isdir(full) or t in CONSUMING_REPO:
                    continue
                if any(os.path.isfile(os.path.join(skill, c)) for c in
                       (t, t.replace('bin/', 'scripts/', 1), t.replace('scripts/', 'bin/', 1))):
                    continue
                out.add((os.path.relpath(f, skill), t))
    return out


def on_disk(skill):
    out = set()
    for d in ASSET_DIRS:
        for p in glob.glob(os.path.join(skill, d, '**', '*'), recursive=True):
            if os.path.isfile(p):
                out.add(os.path.relpath(p, skill))
    return out


if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else 'compare'
    # A root argument lets the fixtures in skill-payload.test.sh drive this on a
    # synthetic tree, so the rules are provable on cases the real tree does not
    # currently contain.
    root = sys.argv[2] if len(sys.argv) > 2 else 'skills'
    for skill in sorted(glob.glob(os.path.join(root, '*/'))):
        name = os.path.basename(skill.rstrip('/'))
        d, k = derive(skill), on_disk(skill)
        if mode == 'derive':
            for p in sorted(d): print(f'{name}\t{p}')
        else:
            for p in sorted(k - d): print(f'{name}\tUNREACHED\t{p}')
            for src, p in sorted(named_but_absent(skill)): print(f'{name}\tMISSING\t{p}\t(named in {src})')
