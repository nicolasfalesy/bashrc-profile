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

# ── run: every language, the exit line
sqpy() { printf 'n = int(input("Give me a number: "))\nprint(f"{n} squared is {n * n}")\n' > "$1"; }
sqrs() {
    cat >"$1" <<'RS'
use std::io::{self, Write};
fn main() {
    print!("Give me a number: ");
    io::stdout().flush().unwrap();
    let mut line = String::new();
    io::stdin().read_line(&mut line).unwrap();
    let n: i64 = line.trim().parse().unwrap();
    println!("{n} squared is {}", n * n);
}
RS
}
t_run_c()         { fresh rc; sq sq.c; local out; out=$(echo 12 | run sq.c 2>&1); [[ $out == *"12 squared is 144"* && $out == *"exit 0, "*" s"* ]]; }
t_stdin()         { fresh si; sq sq.c; [[ $(echo 7 | run sq.c 2>&1) == *"7 squared is 49"* ]]; }
t_run_exit_code() {
    fresh ec; printf 'int main(void) { return 3; }\n' > e.c
    local out rc; out=$(run e.c 2>&1); rc=$?
    [[ $rc == 3 && $out == *"exit 3, "* ]]
}
t_run_py()        { fresh rp; sqpy a.py; [[ $(echo 5 | run a.py 2>&1) == *"5 squared is 25"* ]]; }
t_py_venv() {
    fresh pv; sqpy a.py; mkdir -p .venv/bin
    printf '#!/bin/sh\necho VENV "$@"\n' > .venv/bin/python; chmod +x .venv/bin/python
    [[ $(run a.py 2>&1) == *"VENV a.py"* ]]
}
t_py_main()       { fresh pm; sqpy main.py; sqpy other.py; [[ $(echo 3 | run 2>&1) == *"3 squared is 9"* ]]; }
t_run_make_target(){ fresh mt; printf 'all:\n\t@true\nrun:\n\t@echo MADE\n' > Makefile; [[ $(run 2>&1) == *MADE* ]]; }
t_run_make_plain() {
    fresh mkp; sq main.c
    printf 'mkp: main.c\n\tcc -o mkp main.c\n' > Makefile
    [[ $(echo 4 | run 2>&1) == *"4 squared is 16"* ]]
}
t_rust_run() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rr; cargo new -q --vcs none sqr && cd sqr && sqrs src/main.rs || return 1
    [[ $(echo 6 | run 2>&1) == *"6 squared is 36"* ]]
}
t_rust_subdir() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rsd; cargo new -q --vcs none sqr && cd sqr && sqrs src/main.rs && cd src || return 1
    [[ $(echo 6 | run 2>&1) == *"6 squared is 36"* ]]
}
t_rust_lone() {
    command -v rustc >/dev/null || { echo "no rustc"; return 0; }
    fresh rl; printf 'fn main() { println!("RS"); }\n' > a.rs
    [[ $(run a.rs 2>&1) == *RS* && -x a ]]
}
t_rust_refuses_W() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rw; cargo new -q --vcs none sqr && cd sqr || return 1
    ! ru -W all 2>/dev/null
}
t_compat_o()      { fresh co; sq sq.c; [[ $(echo 2 | run -o x sq.c 2>&1) == *"2 squared is 4"* && -x x ]]; }

check run_c           t_run_c
check stdin           t_stdin
check run_exit_code   t_run_exit_code
check run_py          t_run_py
check py_venv         t_py_venv
check py_main         t_py_main
check run_make_target t_run_make_target
check run_make_plain  t_run_make_plain
if command -v cargo >/dev/null; then
    check rust_run       t_rust_run
    check rust_subdir    t_rust_subdir
    check rust_refuses_W t_rust_refuses_W
else
    skip "rust (no cargo)"
fi
if command -v rustc >/dev/null; then check rust_lone t_rust_lone; else skip "rust_lone (no rustc)"; fi
check compat_o        t_compat_o

# ── rud and rund, with stand-ins for the debugger and valgrind that print how they were called
stub=$T/stub; mkdir -p "$stub"
printf '#!/bin/sh\necho "LLDB $*"\n' > "$stub/lldb"
printf '#!/bin/sh\necho "GDB $*"\n' > "$stub/gdb"
printf '#!/bin/sh\necho "VG $*" >&2\n' > "$stub/valgrind"
printf '#!/bin/sh\necho "PY $*"\n' > "$stub/python3"
chmod +x "$stub"/*
# nolldb: /usr/bin without lldb and gdb, plus the gdb stand-in.
nolldb() {
    local d=$T/nolldb f
    if [[ ! -d $d ]]; then
        mkdir -p "$d"
        for f in /usr/bin/*; do case ${f##*/} in lldb*|gdb*) ;; *) ln -s "$f" "$d/" ;; esac; done
        cp "$stub/gdb" "$d/gdb"
    fi
    echo "$d"
}
t_rud_c()          { fresh dbc; sq sq.c; [[ $(PATH=$stub:$PATH rud sq.c 2>&1) == *"LLDB -- ./sq"* ]]; }
t_rud_gdb_fallback(){ fresh dbg; sq sq.c; local p; p=$(nolldb); [[ $(PATH=$p rud sq.c 2>&1) == *"GDB --args ./sq"* ]]; }
t_rud_py()         { fresh dbp; sqpy a.py; [[ $(PATH=$stub:$PATH rud a.py 2>&1) == *"PY -m pdb a.py"* ]]; }
t_rund_plain() {
    fresh vgp; sq sq.c
    local out; out=$(PATH=$stub:$PATH rund sq.c 2>&1)
    [[ $out == *'[compile]'* && $out != *fsanitize* && $out == *"VG -s --leak-check=full --track-origins=yes ./sq"* ]]
}
t_compat_rund() {
    fresh vgc; sq sq.c; echo 5 > in.txt
    [[ $(PATH=$stub:$PATH rund -i in.txt sq.c -- 1 2 2>&1) == *"./sq 1 2"* ]]
}
t_rund_py_refuses(){ fresh vgy; sqpy a.py; ! PATH=$stub:$PATH rund a.py 2>/dev/null; }

check rud_c            t_rud_c
check rud_gdb_fallback t_rud_gdb_fallback
check rud_py           t_rud_py
check rund_plain       t_rund_plain
check compat_rund      t_compat_rund
check rund_py_refuses  t_rund_py_refuses

# ── rut (tests), mkmake, the lazy-load line
# t1 STEM IN EXPECT: one .in/.expect test case.
t1() { printf '%s\n' "$2" > "$1.in"; printf '%s\n' "$3" > "$1.expect"; }
t_rut_c()     { fresh tc; sq sq.c; t1 a 3 "Give me a number: 3 squared is 9"; rut sq.c 2>&1 | grep -q "All tests passed"; }
t_rut_py()    { fresh tp; sqpy a.py; t1 b 4 "Give me a number: 4 squared is 16"; rut a.py 2>&1 | grep -q "All tests passed"; }
t_rut_fails() { fresh tf; sq sq.c; t1 a 3 "wrong"; ! rut sq.c >/dev/null 2>&1; }
t_compat_rut_flags() { fresh tx; sq sq.c; t1 a 2 "Give me a number: 2 squared is 4"; rut -- -DX >/dev/null 2>&1; }
t_mkmake_builds() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh mkb; sq main.c
    mkmake >/dev/null 2>&1 && make -s >/dev/null 2>&1 && [[ -x mkb ]] || return 1
    [[ $(echo 4 | make -s run 2>&1) == *"4 squared is 16"* ]] || return 1
    t1 a 5 "Give me a number: 5 squared is 25"; make -s test >/dev/null 2>&1
}
t_mkmake_refuses() { fresh mkr; sq main.c; touch Makefile; ! mkmake 2>/dev/null; }
t_lazy_line()  { grep -q '^_bashrc_lazy dev .*\bmkmake\b' "$here/bashrc"; }

check rut_c            t_rut_c
check rut_py           t_rut_py
check rut_fails        t_rut_fails
check compat_rut_flags t_compat_rut_flags
if command -v make >/dev/null; then
    check mkmake_builds  t_mkmake_builds
else
    skip "mkmake_builds (no make)"
fi
check mkmake_refuses   t_mkmake_refuses
check lazy_line        t_lazy_line

echo "$pass passed, $fail failed"
(( fail == 0 ))
