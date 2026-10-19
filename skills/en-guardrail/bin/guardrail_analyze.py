#!/usr/bin/env python3
"""en-guardrail command analyzer (EN09).

Reads a Claude Code tool-input JSON object on stdin and decides whether the
command / MCP DB statement is destructive enough to require a permission
prompt. Prints exactly one line:

    ALLOW
    ASK\t<pattern>\t<message>

The Bash wrapper (check-guardrail.sh) turns ALLOW into `{}` and ASK into the
`{"permissionDecision":"ask",...}` envelope (plus analytics). All shell/SQL
parsing lives here — proper tokenization (shlex), structural connection-target
parsing, and one statement-scope analyzer shared by the Bash and MCP paths —
because bash-regex parsing was bypassable (EN09 branch-review CR1-CR6: rm
option-ordering / compound commands, spoofable localhost substrings, quoted
redirection, quoted/aliased UPDATE tables, piped SQL through wrappers).

Fail closed: when structure can't be resolved on a destructive-looking command,
prompt.
"""
import sys, json, re, shlex, os

ARTIFACTS = {"node_modules", ".next", "dist", "__pycache__", ".cache", "build", ".turbo", "coverage"}
DB_CLIENTS = {"psql", "mysql", "mariadb", "mongosh", "sqlite3", "cockroach", "clickhouse-client", "usql"}
WRAPPERS = {"env", "timeout", "gtimeout", "nice", "nohup", "stdbuf", "time", "sudo", "command", "xargs"}
# Wrapper options that take a value, so `sudo -u root rm -rf /x` resolves to rm
# and not to `root`; and wrappers with a positional argument before the command.
WRAPPER_VALUE_OPTS = {
    "sudo": {"-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T"},
    "env": {"-u", "-C", "-S", "--unset", "--chdir", "--split-string"},
    "nice": {"-n", "--adjustment"},
    "timeout": {"-s", "-k", "--signal", "--kill-after"},
    "gtimeout": {"-s", "-k", "--signal", "--kill-after"},
    "xargs": {"-n", "-I", "-L", "-P", "-s", "-d", "-E", "-a", "--max-args", "--replace",
              "--max-procs", "--delimiter", "--arg-file", "--max-chars", "--eof"},
    "stdbuf": {"-i", "-o", "-e"},
}
WRAPPER_POSITIONAL = {"timeout": 1, "gtimeout": 1}
# Reserved words that can open a simple command: `then rm -rf /x` is rm.
SHELL_KEYWORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "(", "fi", "done", "}", ")", "exec"}
SQL_FLAGS = ("-c", "--command", "-e", "--execute")
LOOPBACK = {"localhost", "127.0.0.1", "::1"}
# A heredoc fed to one of these is shell, and is analysed as shell.
SHELL_RUNNERS = {"bash", "sh", "zsh", "dash", "ksh", "ssh", "eval", "su", "docker", "podman", "kubectl"}
# A heredoc fed to one of these is a program in another language: not parsed as
# shell, but still scanned for `rm -r` and SQL DROP/TRUNCATE text.
INTERPRETERS = {"python", "python3", "node", "ruby", "perl", "php", "deno", "bun", "uv", "tsx", "ts-node"} | DB_CLIENTS
# Readers that never execute what they read: a heredoc fed to one of these, with
# no pipe after it, is data and is dropped. Anything else keeps its body inline.
DATA_READERS = {"cat", "tee", "git", "gh", "sponge", "wc", "jq", "pbcopy", "base64", "sort", "head", "tail"}
# Commands whose arguments are never run: a `rm -rf`, `DROP` or `git push -f` in
# a grep pattern, an echo or a commit message is text. Every other command, a
# function call or anything unresolved, is scanned (fail closed).
INERT = {"grep", "egrep", "fgrep", "rg", "ag", "ack", "echo", "printf", "gh", "jq", "cat", "head", "tail", "wc", "ls"}
INERT_GIT = {"commit", "log", "grep", "show", "diff", "status", "blame", "shortlog"}
MKTEMP_MARK, TMPDIR_MARK = "\x00MKTEMP", "\x00TMPDIR"


def emit(pattern, message):
    sys.stdout.write("ASK\t%s\t%s\n" % (pattern, message)); sys.exit(0)


def allow():
    sys.stdout.write("ALLOW\n"); sys.exit(0)


# ---------------------------------------------------------------- SQL scope
def _strip_sql(sql):
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\n]*", " ", sql)
    sql = re.sub(r"'(?:''|[^'])*'", "''", sql)      # single-quoted SQL literals
    return sql


def _top_level_where(after_kw):
    depth = 0
    for m in re.finditer(r"[()]|\bwhere\b", after_kw, re.I):
        t = m.group(0)
        if t == "(":
            depth += 1
        elif t == ")":
            depth = max(0, depth - 1)
        elif depth == 0:
            return True
    return False


_TARGET = r'(?:"[^"]+"|`[^`]+`|\[[^\]]+\]|[a-zA-Z_][\w.$]*)'
_UPDATE_HEAD = re.compile(r"\bupdate\s+" + _TARGET + r"(?:\s+(?:as\s+)?[a-zA-Z_]\w*)?\s+set\b", re.I)
_UPDATE_ANY = re.compile(r"\bupdate\b", re.I)
_DELETE = re.compile(r"\bdelete\s+from\b", re.I)


def sql_destructive(sql):
    """(pattern, message) if the SQL is destructive-and-unscoped, else None."""
    for stmt in _strip_sql(sql).split(";"):
        low = stmt.lower()
        if re.search(r"\bdrop\s+(table|database|schema)\b", low):
            return ("drop", "SQL DROP permanently deletes database objects.")
        if re.search(r"\btruncate\b", low):
            return ("truncate", "SQL TRUNCATE deletes all rows from a table.")
        m = _DELETE.search(stmt)
        if m and not _top_level_where(stmt[m.end():]):
            return ("delete_no_where", "DELETE without a top-level WHERE deletes every row.")
        m = _UPDATE_HEAD.search(stmt)
        if m:
            if not _top_level_where(stmt[m.end():]):
                return ("update_no_where", "UPDATE without a top-level WHERE modifies every row.")
        elif _UPDATE_ANY.search(stmt):
            return ("update_unparsed", "UPDATE statement could not be parsed; confirm it is scoped.")
    return None


# ---------------------------------------------------- connection-target parse
def parse_target(v):
    """Return (host, db) from a connection URL/DSN or key=value string."""
    host = db = None
    m = re.search(r"://(?:[^@/\s]*@)?([^/:?\s]+)", v)      # host after :// (opt. user@)
    if m:
        host = m.group(1)
    m = re.search(r"://[^/\s]+/([^/?\s]+)", v)             # first path segment = db
    if m:
        db = m.group(1)
    m = re.search(r"host=([^\s]+)", v, re.I)
    if m:
        host = m.group(1)
    m = re.search(r"(?:dbname|database)=([^\s]+)", v, re.I)
    if m:
        db = m.group(1)
    return host, db


def _is_loopback(host):
    if not host:
        return False
    host = host.strip().strip("[]").lower()
    host = re.sub(r":\d+$", "", host)                      # drop :port
    return host in LOOPBACK


def _testdev(name):
    return bool(name) and any(k in name.lower() for k in ("test", "dev", "local"))


def targets_local_testdev(tokens):
    """Loopback host AND a test/dev/local db name, from flags + URL + key=value.
    Host must be an EXACT loopback (localhost.example.com is remote — CR1)."""
    host = db = None
    for tok in tokens:
        if "://" in tok or "host=" in tok.lower() or "dbname=" in tok.lower() or "database=" in tok.lower():
            h, d = parse_target(tok)
            host = h or host
            db = d or db
    for i, tok in enumerate(tokens):
        if tok in ("-h", "--host") and i + 1 < len(tokens):
            host = tokens[i + 1]
        elif tok.startswith("-h") and len(tok) > 2:
            host = tok[2:]
        elif tok in ("-d", "--dbname") and i + 1 < len(tokens):
            db = tokens[i + 1]
        elif tok.startswith("-d") and len(tok) > 2:
            db = tok[2:]
    return _is_loopback(host) and _testdev(db)


# --------------------------------------------------------- shell parse
_ASSIGN_TOK = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def base(tok):
    return tok.rsplit("/", 1)[-1]


def command_index(tokens):
    """Index of the word that runs: past reserved words, assignments, wrappers
    and each wrapper's own options, so `sudo -u root rm -rf /x`, `then rm -rf /x`
    and `timeout 30 psql` all resolve to the command they run."""
    i, n = 0, len(tokens)
    while i < n:
        tok = tokens[i]
        if tok in SHELL_KEYWORDS or _ASSIGN_TOK.match(tok):
            i += 1
            continue
        w = base(tok)
        if w in WRAPPERS:
            i += 1
            opts, pos = WRAPPER_VALUE_OPTS.get(w, set()), WRAPPER_POSITIONAL.get(w, 0)
            while i < n:
                t = tokens[i]
                if t == "--":
                    i += 1
                    break
                if t.startswith("-") and t != "-":
                    i += 2 if t in opts else 1
                    continue
                if w == "env" and _ASSIGN_TOK.match(t):
                    i += 1
                    continue
                if pos:
                    pos -= 1
                    i += 1
                    continue
                break
            continue
        return i
    return None


def command_word(tokens):
    i = command_index(tokens or [])
    return None if i is None else tokens[i]


def is_inert(tokens):
    """True only for a command positively known never to run its arguments."""
    i = command_index(tokens or [])
    if i is None:
        return False
    w = base(tokens[i])
    if w in INERT:
        return True
    if w == "git":
        j = i + 1
        while j < len(tokens) and tokens[j].startswith("-"):
            j += 2 if tokens[j] in ("-C", "-c") else 1
        return j < len(tokens) and tokens[j] in INERT_GIT
    return False


def split_ops(cmd):
    """[(tokens|None, raw, op_before)] per simple command, split on `;`, newline,
    `&&`, `||`, `|` and a background `&`. op_before is the operator that joined
    the segment to the one before it (None for the first)."""
    segs, buf, i, quote, op = [], "", 0, None, None
    n = len(cmd)
    while i < n:
        c = cmd[i]
        if quote:
            buf += c
            if c == quote:
                quote = None
        elif c in ("'", '"'):
            quote = c; buf += c
        elif c in (";", "\n"):
            segs.append((buf, op)); buf = ""; op = ";"
        elif cmd[i:i + 2] in ("&&", "||"):
            segs.append((buf, op)); buf = ""; op = cmd[i:i + 2]; i += 2; continue
        elif c == "|":
            segs.append((buf, op)); buf = ""; op = "|"
            if cmd[i + 1:i + 2] == "&":                    # `|&` pipes stderr too
                i += 1
        elif c == "&" and cmd[i - 1:i] not in ("<", ">") and cmd[i + 1:i + 2] != ">":
            segs.append((buf, op)); buf = ""; op = "&"     # background: a new command
        else:
            buf += c
        i += 1
    segs.append((buf, op))
    out = []
    for seg, before in segs:
        seg = seg.strip()
        if not seg:
            continue
        try:
            toks = shlex.split(seg, comments=False, posix=True)
        except ValueError:
            toks = None
        out.append((toks, seg, before))
    return out


def split_simple(cmd):
    return [(toks, raw) for toks, raw, _ in split_ops(cmd)]


_HEREDOC_AT = re.compile(r"<<(-?)\s*(['\"]?)([A-Za-z_][\w.-]*)\2")


def _heredoc_kind(prefix, suffix):
    """'shell', 'interp' or 'data' for a heredoc, from the command reading it.
    Data only for a known non-executing reader with no pipe after the marker;
    anything unknown stays shell, which is how it was analysed before."""
    last = re.split(r"\|\||&&|[|;&]", prefix)[-1]
    try:
        toks = shlex.split(last, posix=True)
    except ValueError:
        toks = last.split()
    word = base(command_word(toks) or "")
    if word in INTERPRETERS or re.match(r"python3(\.\d+)?$", word):
        return "interp"
    piped = re.search(r"(^|[^|])\|(?!\|)", suffix)
    if word in DATA_READERS and not piped:
        return "data"
    return "shell"


def strip_heredocs(cmd):
    """(shell_text, program_bodies). Scanned line by line with quote state carried
    across lines, so a `<<X` inside quotes is text and swallows nothing. A body
    read by a non-executing reader (`cat > f <<EOF`, `git commit -F -`) is file
    content and is dropped; one read by an interpreter is returned for the text
    scans; every other body stays inline and is analysed as shell. Parsed as
    shell, an unbalanced quote in Python failed shlex and the raw fallback
    flagged any `>`. An unterminated heredoc runs to the end, as the shell reads it."""
    lines = cmd.split("\n")
    out, programs, quote, i = [], [], None, 0
    while i < len(lines):
        line = lines[i]
        i += 1
        out.append(line)
        markers, j = [], 0
        while j < len(line):
            c = line[j]
            if quote:
                if c == "\\" and quote == '"':
                    j += 2
                    continue
                if c == quote:
                    quote = None
            elif c == "\\":
                j += 2
                continue
            elif c in ("'", '"'):
                quote = c
            elif line.startswith("<<", j) and not line.startswith("<<<", j) and line[j - 1:j] != "<":
                m = _HEREDOC_AT.match(line, j)
                if m:
                    markers.append((m.group(1) == "-", m.group(3), _heredoc_kind(line[:j], line[m.end():])))
                    j = m.end()
                    continue
            j += 1
        for strip_tabs, delim, kind in markers:
            body = []
            while i < len(lines):
                cand = lines[i].lstrip("\t") if strip_tabs else lines[i]
                i += 1
                if cand == delim:
                    break
                body.append(lines[i - 1])
            if kind == "shell":
                out.extend(body)
            elif kind == "interp":
                programs.append("\n".join(body))
    return "\n".join(out), programs


_ASSIGN = re.compile(r"^(?:export\s+)?([A-Za-z_]\w*)=(.*)$", re.S)
_MKTEMP = re.compile(r"""^["']?(\$\(\s*mktemp\b[^)]*\)|`\s*mktemp\b[^`]*`)["']?$""")
# Anything in the command that could make `mktemp` run something else: a
# function or alias of that name, a PATH change, a hashed path.
_MKTEMP_SHADOW = re.compile(r"""(?<![\w-])mktemp\s*\(\s*\)|\bfunction\s+mktemp\b|\balias\b[^;&|\n]*\bmktemp=|(?<![\w$])PATH\+?=|\bhash\s+-p\b""")


def track_env(segs, shell):
    """Per segment, the variables this command provably holds before it runs, so
    `SP=/tmp/claude-501/x/scratchpad; rm -rf "$SP/out"` reads as the path it is.
    Only an unconditional top-level assignment counts. A name assigned any other
    way anywhere in the command (after `||`, in a pipeline, a subshell, a loop,
    `read`, `declare`, `unset`) is dropped everywhere, so it reads as unresolved
    and fails closed. A value from $(mktemp ...) becomes the MKTEMP marker,
    unless the command could have redefined what `mktemp` runs."""
    env, snaps, tracked, poisoned = {}, [], {}, set()
    real_mktemp = not _MKTEMP_SHADOW.search(shell)
    for k, (toks, raw, before) in enumerate(segs):
        snaps.append(dict(env))
        m = _ASSIGN.match(raw)
        if not m:
            continue
        name, val = m.group(1), m.group(2).strip()
        tracked[name] = tracked.get(name, 0) + 1
        piped_after = k + 1 < len(segs) and segs[k + 1][2] == "|"
        if before in ("||", "|", "&") or piped_after:
            poisoned.add(name)
            continue
        if _MKTEMP.match(val):
            if real_mktemp:
                env[name] = MKTEMP_MARK
            else:
                env.pop(name, None)
        elif re.search(r"\s|\$\(|`", val.strip("'\"")):
            env.pop(name, None)
        else:
            env[name] = expand(val.strip("'\""), env)
    # Builtins that set a name, as the command word of a segment (not the word
    # `local` inside `fr90-local.config.ts`). An unparseable segment that starts
    # with one poisons every name it mentions.
    setters = {"for", "select", "read", "declare", "local", "typeset", "readonly", "unset", "mapfile", "readarray", "getopts"}
    for toks, raw, _ in segs:
        words = toks if toks is not None else raw.split()
        lead = [w for w in words if w not in SHELL_KEYWORDS][:1]
        if lead and lead[0] in setters:
            poisoned.update(n for n in tracked if re.search(r"\b%s\b" % re.escape(n), raw))
    for name in tracked:
        if len(re.findall(r"(?<![\w$])%s=" % re.escape(name), shell)) != tracked[name]:
            poisoned.add(name)
    return [{k: v for k, v in snap.items() if k not in poisoned} for snap in snaps]


def _tmpdir():
    t = os.environ.get("TMPDIR", "").rstrip("/")
    return t if t.startswith("/") and os.path.isdir(t) else ""


def expand(word, env):
    """Expand $NAME / ${NAME} from what this command assigned, and $TMPDIR to a
    marker when the hook's own TMPDIR is a real directory (unset, it expands to
    nothing and `$TMPDIR/x` is `/x`). Anything unknown stays as written."""
    def sub(m):
        name = m.group(1) or m.group(2)
        if name in env:
            return env[name]
        if name == "TMPDIR" and _tmpdir():
            return TMPDIR_MARK
        return m.group(0)
    return re.sub(r"\$\{([A-Za-z_]\w*)\}|\$([A-Za-z_]\w*)", sub, word)


def _safe_below(root, rel):
    """No symlink anywhere from the root down to the deepest part of the path
    that exists, and the root, if it exists, is ours and not writable by group
    or other. A link in scratch pointing at $HOME makes `rm -rf link/` or
    `> link` act outside it. The root itself is checked before it is resolved:
    /tmp/claude-<uid> planted as a link to a directory of ours would pass every
    check once followed. Only its parent is resolved, since /tmp and /var are
    system links on macOS."""
    real = os.path.join(os.path.realpath(os.path.dirname(root)), os.path.basename(root))
    if os.path.islink(real):
        return False
    if os.path.lexists(real):
        try:
            st = os.lstat(real)
        except OSError:
            return False
        if st.st_uid != os.getuid() or st.st_mode & 0o022:
            return False
    cur = real
    for comp in rel:
        cur = os.path.join(cur, comp)
        if os.path.islink(cur):
            return False
        if not os.path.exists(cur):
            break
    return True


def owned_temp(word, env):
    """True when the path is temp space the agent owns: Claude Code's session
    scratch for this uid (/tmp/claude-<uid>/..., /tmp/claude/... on older
    versions), Ensemble's run directories (/tmp/ensemble/...), a path written as
    $TMPDIR/..., or one under a variable this command set from $(mktemp ...).
    Always below the root, never through `..`, a glob, or a symlink. A literal
    /var/folders/... path is not owned: nothing says the agent made it."""
    p = expand(word, env)
    if any(ch in p for ch in "$`*?[~"):
        return False
    if p.startswith(MKTEMP_MARK):
        rest = [c for c in p[len(MKTEMP_MARK):].split("/") if c]
        return ".." not in rest
    if p.startswith(TMPDIR_MARK):
        root, rest = _tmpdir(), [c for c in p[len(TMPDIR_MARK):].split("/") if c]
        return bool(root) and bool(rest) and ".." not in rest and _safe_below(root, rest)
    p = re.sub(r"^/private(?=/tmp/)", "", p)
    for root in ("/tmp/claude-%d" % os.getuid(), "/tmp/claude", "/tmp/ensemble"):
        if p.startswith(root + "/"):
            rest = [c for c in p[len(root):].split("/") if c]
            return bool(rest) and ".." not in rest and "." not in rest and _safe_below(root, rest)
    return False


def rm_recursive_unsafe(tokens, env=None):
    env = env or {}
    start = command_index(tokens) or 0
    recursive, targets, ddash = False, [], False
    for tok in tokens[start + 1:]:
        if tok == "--":
            ddash = True; continue
        if not ddash and tok.startswith("-"):
            if tok == "--recursive" or (not tok.startswith("--") and "r" in tok):
                recursive = True
            continue
        targets.append(tok)
    if not recursive:
        return (False, False)
    for t in targets:
        if owned_temp(t, env):
            continue
        if t.startswith("/") or t.startswith("~") or any(ch in t for ch in "$`*?["):
            return (True, True)
        parts = [p for p in t.rstrip("/").split("/") if p]
        if ".." in parts or not parts or parts[-1] not in ARTIFACTS:
            return (True, True)
    return (True, False)


_RAW_REDIR = re.compile(r"""(?<![<>&\d])(?:\d*|&)>(?![>&])\s*("[^"]*"|'[^']*'|[^\s;|&()<>]+)""")


def redir_truncates(tokens, raw, env=None):
    env = env or {}
    if tokens is None:
        # Unparseable segment: find what the redirections write to. Owned temp
        # targets are fine; any other target, or a `>` we cannot pin to one,
        # fails closed.
        if not re.search(r"(^|[^>])>(?![>&])", raw):
            return False
        targets = [t.strip("'\"") for t in _RAW_REDIR.findall(raw)]
        return not targets or any(not owned_temp(t, env) for t in targets)
    for i, tok in enumerate(tokens):
        m = re.match(r"^([0-9]*|&)>(?!>)(.*)$", tok)
        if not m:
            continue
        target = m.group(2) or (tokens[i + 1] if i + 1 < len(tokens) else "")
        if not target or target.startswith("&"):
            continue
        if owned_temp(target, env):
            continue
        # Expansion only ever proves a target is owned temp. Anything else under
        # a variable stays unresolved, as before: `git show HEAD:$P > $P`
        # overwrites a tracked file, and its relative path means nothing from
        # the hook's working directory once the command has `cd`'d away.
        if any(ch in target for ch in "$`*?"):
            return True
        if os.path.islink(target) or os.path.isfile(target):
            return True
    return False


def sql_args(cmds):
    args = []
    for toks, _ in cmds:
        if not toks:
            continue
        for i, tok in enumerate(toks):
            if tok in SQL_FLAGS and i + 1 < len(toks):
                args.append(toks[i + 1])
            elif tok.startswith("--command="):
                args.append(tok.split("=", 1)[1])
            elif tok.startswith("--execute="):
                args.append(tok.split("=", 1)[1])
            elif tok.startswith("-c") and len(tok) > 2 and not tok.startswith("--"):
                args.append(tok[2:])
            elif tok.startswith("-e") and len(tok) > 2 and not tok.startswith("--"):
                args.append(tok[2:])
    return args


def seg_invokes_client(tokens):
    # A DB client appears as a bareword in the segment (conservative: wrappers
    # like `timeout 30 psql` and `env X=1 psql` consume args, so scan all tokens).
    # A lookup names the client without running it: `command -v psql`.
    if not tokens:
        return False
    if tokens[0] in ("which", "type", "whereis", "hash") or (tokens[0] == "command" and tokens[1:2] in (["-v"], ["-V"])):
        return False
    return any(base(t) in DB_CLIENTS for t in tokens)


def sql_from_uninspectable(segs):
    for toks, raw, before in segs:
        if not seg_invokes_client(toks):
            continue
        for i, tok in enumerate(toks):
            if tok in ("-f", "--file") or tok.startswith("--file=") or (tok.startswith("-f") and len(tok) > 2 and not tok.startswith("--")):
                return True
        if before == "|":                                  # receives a pipe
            return True
        if re.search(r"(^|[^<])<(?!<)\s*\S", raw) or "<<" in raw:
            return True
    return False


TOOL_PATTERNS = [
    # (name, regex, message). The name is EXPLICIT because it is the analytics
    # label: it used to be derived as pat.split(chr(92))[0][:20], which collapsed
    # every `(^|\s)...` pattern to `(^|` and all six git rules to `git`, so the
    # recorded data could not tell a force-push from a reset --hard.
    ("find_delete", r"(^|\s)find\s+.*(-delete\b|-exec\s+rm\b)",
     "find -delete / -exec rm removes matched files."),
    ("rsync_delete", r"(^|\s)rsync\s+.*--delete",
     "rsync --delete removes destination files."),
    ("shred", r"(^|\s)shred(\s|$)",
     "shred irrecoverably destroys file contents."),
    ("truncate_zero", r"(^|\s)truncate\s+.*-s[\s=]*0(\b|$)",
     "truncate -s 0 empties a file."),
    ("unlink", r"(^|\s)unlink(\s|$)",
     "unlink removes a file."),
    ("git_force_push", r"git\s+push\s+.*(-f\b|--force)",
     "git force-push rewrites remote history."),
    ("git_reset_hard", r"git\s+reset\s+--hard",
     "git reset --hard discards uncommitted changes."),
    ("git_checkout_dot", r"git\s+(checkout|restore)\s+\.",
     "discards all uncommitted working-tree changes."),
    ("git_branch_force_delete", r"git\s+branch\s+(-[a-zA-Z]*D|--delete\s+--force)",
     "git branch -D force-deletes an unmerged branch."),
    ("git_tag_delete", r"git\s+tag\s+(-[a-zA-Z]*d|--delete)",
     "git tag -d removes a tag."),
    ("git_worktree_force_remove", r"git\s+worktree\s+remove\s+(-[a-zA-Z]*f|--force)",
     "git worktree remove --force discards changes."),
    ("kubectl_delete", r"kubectl\s+delete",
     "kubectl delete removes Kubernetes resources."),
    ("docker_force_remove", r"docker\s+(rm\s+-f|system\s+prune)",
     "Docker force-remove or prune."),
    ("terraform_destroy", r"terraform\s+destroy",
     "terraform destroy tears down infrastructure."),
    ("aws_s3_rm_recursive", r"aws\s+s3\s+rm\s+.*--recursive",
     "aws s3 rm --recursive bulk-deletes objects."),
    ("gcloud_delete", r"gcloud(\s+[a-z-]+)+\s+delete\b",
     "gcloud delete removes a cloud resource."),
    ("orm_destructive_migration", r"(prisma\s+migrate\s+reset|rails\s+db:(drop|reset)|drizzle-kit\s+push|sequelize\s+db:drop|php\s+artisan\s+migrate:(fresh|reset)|alembic\s+downgrade\s+base)",
     "ORM destructive migration can wipe the database."),
]


_SQL_TEXT = re.compile(r"""\bdrop\s+(table|database|schema)\b|\btruncate\s+(table\s+)?["`\w]""", re.I)
_NESTED_RM = re.compile(r"\brm\b\s+(-[a-zA-Z]*r|--recursive)")
_SUBST = re.compile(r"\$\(([^()]*)\)|`([^`]*)`|[<>]\(([^()]*)\)")


def analyze_shell(cmd):
    shell, programs = strip_heredocs(cmd)
    segs = split_ops(shell)
    envs = track_env(segs, shell)
    cmds = [(toks, raw) for toks, raw, _ in segs]
    substs = ["".join(g) for g in _SUBST.findall(shell)]
    interp = {"python", "python3", "node", "ruby", "perl", "php", "deno", "bun", "tsx", "ts-node"}

    # Text that may run: every simple command except one positively known never
    # to run its arguments (grep, echo, `git commit`, ...), plus command and
    # process substitutions and interpreter heredocs. Unresolved, unknown and
    # function-call commands are scanned, which is how the whole-command scan
    # treated them before D128.
    def word(toks):
        return base(command_word(toks) or "") if toks else ""
    live = [(toks, raw) for toks, raw in cmds if not is_inert(toks)]

    for (toks, raw), env in zip(cmds, envs):
        if toks and word(toks) == "rm":
            rec, unsafe = rm_recursive_unsafe(toks, env)
            if rec and unsafe:
                emit("rm_recursive", "recursive delete (rm -r) of a non-artifact / out-of-tree path.")
    # rm -r that this command does not run directly: ssh "rm -rf /data",
    # bash -c "...", find -exec, $(...), an alias or function, a program body.
    nested = [raw for toks, raw in live if word(toks) != "rm"] + substs + programs
    if any(_NESTED_RM.search(t) for t in nested):
        emit("rm_recursive", "recursive delete (rm -r) inside a nested/quoted command.")

    for (toks, raw), env in zip(cmds, envs):
        if ">" in raw and redir_truncates(toks, raw, env):
            emit("redir_truncate", "output redirection (>) truncates an existing file or symlink.")

    # Per simple command, so `.*` cannot run across `&&` into the next one:
    # `git push origin x && gh pr edit -f` is not a force-push. Interpreter
    # bodies are scanned whole: `os.system("git reset --hard")` runs it.
    for name, pat, msg in TOOL_PATTERNS:                   # case-sensitive on raw (preserves -D vs -d)
        if any(re.search(pat, t) for t in [raw for _, raw in live] + substs + programs):
            emit(name, msg)

    all_toks = [t for toks, _ in cmds if toks for t in toks]
    local = targets_local_testdev(all_toks)

    # SQL we can read (-c/-e), de-quoted. Skipped for commands whose -c/-e mean
    # something else: `python3 -c` and `node -e` carry code, `git switch -c` a
    # branch name (`fix-crm-update-...` read as an unparseable UPDATE).
    not_sql = interp | {"git", "sed", "awk", "perl", "ruby", "make", "npm", "pnpm", "yarn", "npx", "bunx", "cargo", "go", "curl"}
    sql_cmds = [(toks, raw) for toks, raw in live if word(toks) not in not_sql and not re.match(r"python3\.\d+$", word(toks))]
    for sa in sql_args(sql_cmds):
        d = sql_destructive(sa)
        if d and not local:
            emit(d[0], d[1])
    # DROP/TRUNCATE we couldn't extract as a -c arg (e.g. ssh "psql -c 'DROP ...'").
    if any(_SQL_TEXT.search(t) for t in [raw for _, raw in live] + substs + programs) and not local:
        emit("drop", "SQL DROP/TRUNCATE detected; confirm the target.")

    if sql_from_uninspectable(segs) and not local:
        emit("sql_from_file", "SQL from a file / stdin / pipe can't be inspected; may be destructive.")


# ------------------------------------------------------------------ MCP
ADAPTERS = {
    "mcp__Neon__run_sql":                    ("sql",            ["project", "projectId", "branch", "branchId"], False),
    "mcp__Neon__run_sql_transaction":        ("sql_statements", ["project", "projectId", "branch", "branchId"], False),
    "mcp__Neon__prepare_database_migration": ("migration_sql",  ["project", "projectId"],                       False),
    "mcp__Postgres__query":                  ("sql",            ["connectionString", "connection", "database"], True),
    "mcp__Postgres__execute":                ("sql",            ["connectionString", "connection", "database"], True),
}
WRITE_NAME = re.compile(r"^mcp__.+__(run_sql|run_sql_transaction|execute_sql|apply_migration|prepare_database_migration)(_.*)?$", re.I)


def _getf(obj, name):
    if isinstance(obj, dict):
        if name in obj:
            return obj[name]
        p = obj.get("params")
        if isinstance(p, dict) and name in p:
            return p[name]
    return None


def analyze_mcp(tool, ti):
    if tool not in ADAPTERS:
        if WRITE_NAME.match(tool):
            emit("mcp_db_write", "MCP DB-writing tool with no adapter; confirm it is not destructive.")
        allow()
    stmt_field, ctrl_fields, local_capable = ADAPTERS[tool]
    stmt = _getf(ti, stmt_field)
    if stmt is None:
        emit("mcp_db_write", "MCP DB tool statement could not be resolved; confirm.")
    if isinstance(stmt, list):
        stmt = " ; ".join(str(x) for x in stmt)
    d = sql_destructive(str(stmt))
    if not d:
        allow()
    if not local_capable:
        emit("mcp_db_write", "MCP DB tool: destructive statement on a remote provider.")
    for f in ctrl_fields:                                  # controlling target field ONLY (not SQL text)
        v = _getf(ti, f)
        if not isinstance(v, str):
            continue
        host, db = parse_target(v)
        if host is None and re.match(r"^[\w.-]+$", v):
            host = v                                        # a bare host value
        if _is_loopback(host) and _testdev(db or v):
            allow()
    emit("mcp_db_write", "MCP DB tool: destructive statement whose target is not provably local test/dev.")


def main():
    try:
        d = json.loads(sys.stdin.read())
    except Exception:
        allow()
    ti = d.get("tool_input", {})
    if not isinstance(ti, dict):
        ti = {}
    cmd = ti.get("command", "")
    cmd = cmd if isinstance(cmd, str) else ""
    tool = d.get("tool_name", "") or ""
    if cmd.strip():
        analyze_shell(cmd)
        allow()
    if tool.startswith("mcp__"):
        analyze_mcp(tool, ti)
    allow()


if __name__ == "__main__":
    main()
