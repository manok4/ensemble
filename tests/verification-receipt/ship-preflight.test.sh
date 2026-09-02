#!/usr/bin/env bash
# Tests for skills/en-ship/scripts/ensemble-ship-preflight (EN15 U5).
#
# The five-case staging machine exists because the skill defined what to SHOW and
# never how files reach the index, and its failure protocol offered "stage all" on
# a dirty tree. The cases that matter most here are the two that lose work when
# wrong: an unrelated file must never land in scope, and a state the helper cannot
# resolve must exit non-zero rather than report a plausible zero.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ship preflight"

P="$REPO_ROOT/skills/en-ship/scripts/ensemble-ship-preflight"
assert_file_exists "$P" "the preflight helper exists"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

new_repo() {
  d="$WORK/$1"; mkdir -p "$d"
  ( cd "$d" && git init -q . && git config user.email t@e.com && git config user.name t \
      && printf 'a\n' > src.txt && git add . && git commit -qm init && git branch -q base ) >/dev/null 2>&1
  printf '%s\n' "$d"
}
field() {  # $1=repo $2=key $3..=args
  d="$1"; k="$2"; shift 2
  ( cd "$d" && "$P" --json "$@" 2>/dev/null ) | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: print('UNPARSEABLE'); raise SystemExit
v=d.get('$k')
print(','.join(v) if isinstance(v,list) else v)"
}

# --- clean branch already ahead: push, commit nothing ------------------------
A=$(new_repo ahead)
( cd "$A" && printf 'b\n' > two.txt && git add . && git commit -qm second ) >/dev/null
assert_eq "push-existing" "$(field "$A" staging_case --base base)" "clean branch ahead of base pushes existing commits"
assert_eq "1" "$(field "$A" ahead --base base)" "ahead count is reported"
assert_eq "" "$(field "$A" scope_matched --base base)" "nothing is staged when the tree is clean"

# --- unrelated work is preserved, never staged -------------------------------
# The case that loses work when wrong.
B=$(new_repo mixed)
printf 'edit\n' >> "$B/src.txt"; printf 'junk\n' > "$B/unrelated.txt"
assert_eq "stage-scoped" "$(field "$B" staging_case --base base)" "tracked in-scope changes select the staging case"
assert_eq "src.txt" "$(field "$B" scope_matched --base base)" "only the tracked change is in scope"
assert_eq "unrelated.txt" "$(field "$B" excluded --base base)" "the untracked file is excluded"
assert_eq "unrelated.txt" "$(field "$B" untracked_inventory --base base)" "the untracked file is inventoried"

# An explicit --scope must narrow, and must not pull untracked files in with it.
C=$(new_repo scoped)
mkdir -p "$C/lib" "$C/other"
printf 'x\n' > "$C/lib/a.txt"; printf 'y\n' > "$C/other/b.txt"
( cd "$C" && git add . && git commit -qm files ) >/dev/null
printf 'edit\n' >> "$C/lib/a.txt"; printf 'edit\n' >> "$C/other/b.txt"
assert_eq "lib/a.txt" "$(field "$C" scope_matched --base base --scope lib/)" "--scope narrows to the named prefix"
assert_eq "other/b.txt" "$(field "$C" excluded --base base --scope lib/)" "out-of-scope tracked changes are excluded, not staged"

# --- nothing to do is not a failure ------------------------------------------
D=$(new_repo noop)
assert_eq "no-op" "$(field "$D" staging_case --base base)" "nothing ahead and nothing in scope is a no-op"

# --- states it must refuse ---------------------------------------------------
# Each must exit non-zero AND say why. A caller reading only the JSON must not be
# able to proceed by ignoring the status.
E=$(new_repo detached)
( cd "$E" && git checkout -q --detach HEAD ) >/dev/null 2>&1
( cd "$E" && "$P" --json >/dev/null 2>&1 ); assert_eq "1" "$?" "a detached HEAD exits non-zero"
assert_eq "detached-head" "$(field "$E" blocked)" "a detached HEAD says why"

# An unresolvable base must never read as "0 behind" — that is the shape of a
# silent lie, where the caller believes it checked freshness and did not.
F=$(new_repo badbase)
( cd "$F" && "$P" --base does-not-exist --json >/dev/null 2>&1 ); assert_eq "1" "$?" "an unresolvable base exits non-zero"
assert_eq "base-unresolvable:does-not-exist" "$(field "$F" blocked --base does-not-exist)" "an unresolvable base names the ref"

G=$(new_repo conflicted)
( cd "$G" && git checkout -q -b other base && printf 'theirs\n' > src.txt && git commit -qam theirs \
    && git checkout -q - && printf 'ours\n' > src.txt && git commit -qam ours \
    && git merge other ) >/dev/null 2>&1
( cd "$G" && "$P" --json >/dev/null 2>&1 ); assert_eq "1" "$?" "a conflicted tree exits non-zero"
assert_eq "merge-conflict" "$(field "$G" blocked)" "a conflicted tree says why"

# --- published branches are reported, not rewritten --------------------------
# The helper only reports the fact; never rewriting a published branch is the
# caller's rule, and it needs this fact to apply it.
H=$(new_repo unpublished)
assert_eq "False" "$(python3 -c "print($(field "$H" published --base base | sed 's/true/True/;s/false/False/'))")" \
  "a branch with no remote counterpart is reported unpublished"

report
