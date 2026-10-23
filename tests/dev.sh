#!/usr/bin/env bash
# tests/dev.sh — the dev commands (lib/dev.sh) on tiny real programs.
#
#   bash tests/dev.sh
#
# Everything is built inside one temp folder that is deleted at the end; the
# build-skip stamps go there too (XDG_CACHE_HOME). A check that needs a tool the
# machine lacks (cargo, clang) prints "skip" instead of failing.
# Exit status is non-zero on any failure, so smoke.sh, CI and the pre-push hook can run it.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../lib/dev.sh
. "$here/lib/dev.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/dev-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
export XDG_CACHE_HOME=$T/cache

pass=0 fail=0
ok()    { pass=$((pass + 1)); echo "ok   $1"; }
bad()   { fail=$((fail + 1)); echo "FAIL $1"; }
skip()  { echo "skip $1"; }
# check NAME FUNC: runs FUNC (a t_* function below) and records ok/FAIL by its status.
check() { if "$2" >"$T/last.out" 2>&1; then ok "$1"; else bad "$1"; sed 's/^/     /' "$T/last.out" | tail -15; fi; }
# fresh NAME: cd into a new empty folder called NAME.
fresh() { rm -rf "${T:?}/w/$1"; mkdir -p "$T/w/$1" && cd "$T/w/$1" || exit 2; }

# ── detection and naming
t_detect_c()       { fresh dc;  touch a.c;   [[ $(_dev_detect) == c ]]; }
t_detect_cpp()     { fresh dcc; touch a.cpp; [[ $(_dev_detect) == cpp ]]; }
t_detect_py()      { fresh dp;  touch a.py;  [[ $(_dev_detect) == python ]]; }
t_detect_make()    { fresh dm;  touch a.c Makefile; [[ $(_dev_detect) == make ]]; }
t_detect_rust()    { fresh dr;  touch Cargo.toml;   [[ $(_dev_detect) == rust ]]; }
t_file_beats_make(){ fresh fm;  touch sq.c Makefile; [[ $(_dev_detect sq.c) == c ]]; }
t_detect_none()    { fresh dn;  ! _dev_detect 2>/dev/null; }
t_mixed() {
    fresh mx; touch a.c b.py
    local out rc
    out=$(_dev_detect 2>&1); rc=$?
    [[ $rc == 1 && $out == *"This folder has C and Python files; name one: run a.c"* ]]
}
t_name_file()      { fresh nf;  [[ $(_dev_name c sq.c) == sq ]]; }
t_name_folder()    { fresh proj; touch a.c b.c; [[ $(_dev_name c) == proj ]]; }

check detect_c        t_detect_c
check detect_cpp      t_detect_cpp
check detect_py       t_detect_py
check detect_make     t_detect_make
check detect_rust     t_detect_rust
check file_beats_make t_file_beats_make
check detect_none     t_detect_none
check mixed           t_mixed
check name_file       t_name_file
check name_folder     t_name_folder

echo "$pass passed, $fail failed"
(( fail == 0 ))
