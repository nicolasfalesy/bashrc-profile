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
# check NAME FUNC: runs FUNC (a t_* function below) in a subshell, so one test's cd, exit or
# unset variable cannot break the next, and records ok/FAIL by its status.
check() { if ( "$2" ) >"$T/last.out" 2>&1; then ok "$1"; else bad "$1"; sed 's/^/     /' "$T/last.out" | tail -15; fi; }
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

# ── C and C++ builds (ru)
# sq FILE: write the "square a number" program to FILE.
sq() {
    cat >"$1" <<'C'
#include <stdio.h>
int main(void) {
    long long n;
    printf("Give me a number: ");
    if (scanf("%lld", &n) != 1) return 1;
    printf("%lld squared is %lld\n", n, n * n);
    return 0;
}
C
}
# later FILE: push FILE's time 5 s into the future, so it counts as newer than any build.
later() { touch -d "@$(( $(date +%s) + 5 ))" "$1"; }

t_c_build() {
    fresh cb; sq sq.c
    local out; out=$(ru sq.c 2>&1) || return 1
    [[ -x sq && $out == *-std=c17* && $out == *-fsanitize=address,undefined* && $out == *-lm* ]]
}
t_c_skip()         { fresh cs; sq sq.c; ru sq.c >/dev/null 2>&1 || return 1; [[ $(ru sq.c 2>&1) != *'[compile]'* ]]; }
t_c_header()       { fresh ch; sq sq.c; ru sq.c >/dev/null 2>&1 || return 1; touch x.h; later x.h; [[ $(ru sq.c 2>&1) == *'[compile]'* ]]; }
t_c_flags_change() { fresh cf; sq sq.c; ru sq.c >/dev/null 2>&1 || return 1; [[ $(ru sq.c -O 2 2>&1) == *'[compile]'*-O2* ]]; }
t_cpp_build() {
    fresh cpp
    printf '#include <iostream>\nint main() { std::cout << "hi\\n"; }\n' > a.cpp
    local out; out=$(ru a.cpp 2>&1) || return 1
    [[ -x a && $out == *-std=c++20* ]]
}
t_gcc_fallback() {
    command -v gcc >/dev/null || { echo "no gcc"; return 0; }
    # A PATH with everything from /usr/bin except clang.
    local nb=$T/noclang f
    if [[ ! -d $nb ]]; then
        mkdir -p "$nb"
        for f in /usr/bin/*; do [[ ${f##*/} == clang* ]] || ln -s "$f" "$nb/"; done
    fi
    fresh gf; sq sq.c
    local out; out=$(PATH=$nb ru sq.c 2>&1) || { echo "$out"; return 1; }
    [[ $out == *'[compile]'*gcc* && -x sq ]]
}
t_spaces()     { fresh "My Course"; sq "sq 1.c"; ru "sq 1.c" >/dev/null 2>&1 && [[ -x "sq 1" ]]; }
t_one_source() { fresh one; sq sq.c; ru >/dev/null 2>&1 && [[ -x sq ]]; }
t_compat_f() {
    fresh multi
    printf 'int f(void);\nint main(void) { return f(); }\n' > a.c
    printf 'int f(void) { return 0; }\n' > b.c
    ru -f a.c b.c >/dev/null 2>&1 && [[ -x multi ]]
}
t_compat_W()   { fresh cw; sq sq.c; local out; out=$(ru -W sq.c 2>&1) || return 1; [[ -x sq && $out != *-Wall* ]]; }
t_unknown_opt(){ fresh uo; sq sq.c; ! ru -q sq.c 2>/dev/null; }

check c_build        t_c_build
check c_skip         t_c_skip
check c_header       t_c_header
check c_flags_change t_c_flags_change
check cpp_build      t_cpp_build
check gcc_fallback   t_gcc_fallback
check spaces         t_spaces
check one_source     t_one_source
check compat_f       t_compat_f
check compat_W       t_compat_W
check unknown_opt    t_unknown_opt

echo "$pass passed, $fail failed"
(( fail == 0 ))
