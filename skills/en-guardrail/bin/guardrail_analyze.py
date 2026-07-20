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
SQL_FLAGS = ("-c", "--command", "-e", "--execute")
LOOPBACK = {"localhost", "127.0.0.1", "::1"}


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
def split_simple(cmd):
    segs, buf, i, quote = [], "", 0, None
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
            segs.append(buf); buf = ""
        elif cmd[i:i + 2] in ("&&", "||"):
            segs.append(buf); buf = ""; i += 2; continue
        elif c == "|":
            segs.append(buf); buf = ""
        else:
            buf += c
        i += 1
    segs.append(buf)
    out = []
    for seg in segs:
        seg = seg.strip()
        if not seg:
            continue
        try:
            toks = shlex.split(seg, comments=False, posix=True)
        except ValueError:
            toks = None
        out.append((toks, seg))
    return out


def base(tok):
    return tok.rsplit("/", 1)[-1]


def command_word(tokens):
    """First token that is not an env-assignment or a known wrapper."""
    for tok in tokens:
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
            continue
        if base(tok) in WRAPPERS:
            continue
        return tok
    return None


def rm_recursive_unsafe(tokens):
    start = 0
    for idx, tok in enumerate(tokens):
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok) or base(tok) in WRAPPERS:
            continue
        start = idx
        break
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
        if t.startswith("/") or t.startswith("~") or any(ch in t for ch in "$`*?["):
            return (True, True)
        parts = [p for p in t.rstrip("/").split("/") if p]
        if ".." in parts or not parts or parts[-1] not in ARTIFACTS:
            return (True, True)
    return (True, False)


def redir_truncates(tokens, raw):
    if tokens is None:
        return bool(re.search(r"(^|[^>])>(?!>)", raw))
    for i, tok in enumerate(tokens):
        m = re.match(r"^([0-9]*|&)>(?!>)(.*)$", tok)
        if not m:
            continue
        target = m.group(2) or (tokens[i + 1] if i + 1 < len(tokens) else "")
        if not target:
            continue
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
    return bool(tokens) and any(base(t) in DB_CLIENTS for t in tokens)


def sql_from_uninspectable(cmds):
    for idx, (toks, raw) in enumerate(cmds):
        if not seg_invokes_client(toks):
            continue
        for i, tok in enumerate(toks):
            if tok in ("-f", "--file") or tok.startswith("--file=") or (tok.startswith("-f") and len(tok) > 2 and not tok.startswith("--")):
                return True
        if idx > 0:                                        # receives a pipe
            return True
        if re.search(r"(^|[^<])<(?!<)\s*\S", raw) or "<<" in raw:
            return True
    return False


TOOL_PATTERNS = [
    (r"(^|\s)find\s+.*(-delete\b|-exec\s+rm\b)", "find -delete / -exec rm removes matched files."),
    (r"(^|\s)rsync\s+.*--delete", "rsync --delete removes destination files."),
    (r"(^|\s)shred(\s|$)", "shred irrecoverably destroys file contents."),
    (r"(^|\s)truncate\s+.*-s[\s=]*0(\b|$)", "truncate -s 0 empties a file."),
    (r"(^|\s)unlink(\s|$)", "unlink removes a file."),
    (r"git\s+push\s+.*(-f\b|--force)", "git force-push rewrites remote history."),
    (r"git\s+reset\s+--hard", "git reset --hard discards uncommitted changes."),
    (r"git\s+(checkout|restore)\s+\.", "discards all uncommitted working-tree changes."),
    (r"git\s+branch\s+(-[a-zA-Z]*D|--delete\s+--force)", "git branch -D force-deletes an unmerged branch."),
    (r"git\s+tag\s+(-[a-zA-Z]*d|--delete)", "git tag -d removes a tag."),
    (r"git\s+worktree\s+remove\s+(-[a-zA-Z]*f|--force)", "git worktree remove --force discards changes."),
    (r"kubectl\s+delete", "kubectl delete removes Kubernetes resources."),
    (r"docker\s+(rm\s+-f|system\s+prune)", "Docker force-remove or prune."),
    (r"terraform\s+destroy", "terraform destroy tears down infrastructure."),
    (r"aws\s+s3\s+rm\s+.*--recursive", "aws s3 rm --recursive bulk-deletes objects."),
    (r"gcloud(\s+[a-z-]+)+\s+delete\b", "gcloud delete removes a cloud resource."),
    (r"(prisma\s+migrate\s+reset|rails\s+db:(drop|reset)|drizzle-kit\s+push|sequelize\s+db:drop|php\s+artisan\s+migrate:(fresh|reset)|alembic\s+downgrade\s+base)", "ORM destructive migration can wipe the database."),
]


def analyze_shell(cmd):
    cmds = split_simple(cmd)

    rm_seen = False
    for toks, raw in cmds:
        if toks and base(command_word(toks) or "") == "rm":
            rm_seen = True
            rec, unsafe = rm_recursive_unsafe(toks)
            if rec and unsafe:
                emit("rm_recursive", "recursive delete (rm -r) of a non-artifact / out-of-tree path.")
    # nested/embedded rm (e.g. ssh "rm -rf /data", bash -c "rm -rf x") — fail closed
    if not rm_seen and re.search(r"\brm\b\s+(-[a-zA-Z]*r|--recursive)", cmd):
        emit("rm_recursive", "recursive delete (rm -r) inside a nested/quoted command.")

    for toks, raw in cmds:
        if ">" in raw and redir_truncates(toks, raw):
            emit("redir_truncate", "output redirection (>) truncates an existing file or symlink.")

    for pat, msg in TOOL_PATTERNS:                         # case-sensitive on raw (preserves -D vs -d)
        if re.search(pat, cmd):
            emit(pat.split(chr(92))[0][:20], msg)

    all_toks = [t for toks, _ in cmds if toks for t in toks]
    local = targets_local_testdev(all_toks)

    for sa in sql_args(cmds):                              # SQL we can read (-c/-e), de-quoted
        d = sql_destructive(sa)
        if d and not local:
            emit(d[0], d[1])
    # nested DROP/TRUNCATE we couldn't extract as a -c arg (e.g. ssh "psql -c 'DROP ...'")
    if re.search(r"\bdrop\s+(table|database|schema)\b|\btruncate\b", cmd, re.I) and not local:
        emit("drop", "SQL DROP/TRUNCATE detected; confirm the target.")

    if sql_from_uninspectable(cmds) and not local:
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
