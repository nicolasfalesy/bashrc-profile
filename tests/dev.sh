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
# Cargo's builds go to each test project's own target/ (some tests look there).
unset CARGO_TARGET_DIR

pass=0 fail=0
ok()    { pass=$((pass + 1)); echo "ok   $1"; }
bad()   { fail=$((fail + 1)); echo "FAIL $1"; }
skip()  { echo "skip $1"; }
# check NAME FUNC: runs FUNC (a t_* function below) in a subshell, so one test's cd, exit or
# unset variable cannot break the next, with stdin from /dev/null (a test that wants input pipes
# its own), and records ok/FAIL by its status.
check() { if ( "$2" ) </dev/null >"$T/last.out" 2>&1; then ok "$1"; else bad "$1"; sed 's/^/     /' "$T/last.out" | tail -15; fi; }
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
t_c_header() {
    fresh ch; echo '#define K 3' > x.h; printf '#include "x.h"\nint main(void) { return K; }\n' > h.c
    ru h.c >/dev/null 2>&1 || return 1
    [[ $(ru h.c 2>&1) != *'[compile]'* ]] || return 1   # unchanged: skipped
    echo '#define K 4' > x.h; later x.h; [[ $(ru h.c 2>&1) == *'[compile]'* ]]
}
t_c_unrelated_header() { fresh cu; sq sq.c; ru sq.c >/dev/null 2>&1 || return 1; touch other.h; later other.h; [[ $(ru sq.c 2>&1) != *'[compile]'* ]]; }
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
t_unknown_opt(){ fresh uo; sq sq.c; local out; ! out=$(ru -q sq.c 2>&1) && [[ $out == *"unknown option '-q'"* ]]; }

check c_build        t_c_build
check c_skip         t_c_skip
check c_header       t_c_header
check c_unrelated_header t_c_unrelated_header
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
t_py_main()       { fresh pm; echo 'print("MAIN")' > main.py; echo 'print("OTHER")' > other.py; local out; out=$(run 2>&1); [[ $out == *MAIN* && $out != *OTHER* ]]; }
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
    local out; ! out=$(ru -W all 2>&1) && [[ $out == *"don't apply to Rust"* ]]
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
# The valgrind stand-in echoes its arguments and its stdin, then the summary line rund needs.
# shellcheck disable=SC2016  # $* and $(cat) belong to the stand-in script, written literally
printf '#!/bin/sh\necho "VG $*" >&2\necho "STDIN:$(cat)" >&2\necho "==1== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)" >&2\n' > "$stub/valgrind"
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
    local out; out=$(PATH=$stub:$PATH rund -i in.txt sq.c -- 1 2 2>&1)
    [[ $out == *"./sq 1 2"* && $out == *"STDIN:5"* ]]
}
t_rund_py_refuses(){ fresh vgy; sqpy a.py; local out; ! out=$(PATH=$stub:$PATH rund a.py 2>&1) && [[ $out == *"valgrind is for compiled programs"* ]]; }

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

# ── review fixes (2026-10-22): build skipping, exit line, detection order, rund, make, mkmake
t_c_source_edit()  { fresh se; sq sq.c; ru sq.c >/dev/null 2>&1 || return 1; later sq.c; [[ $(ru sq.c 2>&1) == *'[compile]'* ]]; }
t_c_multi_skip() {
    fresh ms; printf 'int f(void);\nint main(void) { return f(); }\n' > a.c; printf 'int f(void) { return 0; }\n' > b.c
    ru -f a.c b.c >/dev/null 2>&1 || return 1
    [[ $(ru -f a.c b.c 2>&1) != *'[compile]'* ]] || return 1
    later b.c; [[ $(ru -f a.c b.c 2>&1) == *'[compile]'* ]]
}
t_c_subdir_header() {
    fresh sh; mkdir inc; echo '#define K 3' > inc/k.h
    printf '#include "k.h"\nint main(void) { return K; }\n' > k.c
    run k.c -- -Iinc >/dev/null 2>&1; echo '#define K 4' > inc/k.h; later inc/k.h
    run k.c -- -Iinc >/dev/null 2>&1; [[ $? == 4 ]]
}
t_c_older_restore() {
    fresh ro; printf 'int main(void) { return 5; }\n' > r.c; touch -d '2001-01-01' r.c
    run r.c >/dev/null 2>&1
    printf 'int main(void) { return 6; }\n' > r.c; touch -d '2000-01-01' r.c   # older than the first copy
    run r.c >/dev/null 2>&1; [[ $? == 6 ]]
}
t_exit_red()       { fresh er; printf 'int main(void) { return 3; }\n' > e.c; [[ $(run e.c 2>&1) == *$'\033[0;31mexit 3, '* ]]; }
t_exit_dim()       { fresh ed; sq sq.c; [[ $(echo 1 | run sq.c 2>&1) == *$'\033[2mexit 0, '* ]]; }
t_exit_on_stderr() { fresh es; sq sq.c; [[ $(echo 1 | run sq.c 2>/dev/null) != *"exit 0"* ]]; }
t_make_beats_cargo(){ fresh mbc; touch Makefile Cargo.toml; [[ $(_dev_detect) == make ]]; }
t_cargo_here_beats_c(){ fresh chc; touch Cargo.toml a.c; [[ $(_dev_detect) == rust ]]; }
t_local_c_beats_cargo_above(){ fresh cab; touch Cargo.toml; mkdir ex && cd ex && touch a.c && [[ $(_dev_detect) == c ]]; }
t_rust_named_lone() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rnl; cargo new -q --vcs none sqr && cd sqr || return 1
    printf 'fn main() { println!("SCRATCH"); }\n' > scratch.rs
    local out; out=$(run scratch.rs 2>&1); [[ $out == *SCRATCH* && $out != *"Hello, world"* ]]
}
t_rust_release() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rre; cargo new -q --vcs none sqr && cd sqr && ru -O 2 >/dev/null 2>&1 && [[ -x target/release/sqr ]]
}
t_rund_no_summary() {
    fresh rns; sq sq.c; local d=$T/vgsilent; mkdir -p "$d"
    printf '#!/bin/sh\nexit 1\n' > "$d/valgrind"; chmod +x "$d/valgrind"
    local out rc; out=$(PATH=$d:$PATH rund sq.c 2>&1); rc=$?
    [[ $rc != 0 && $out == *"valgrind could not run"* ]]
}
t_rund_asan_make() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh ram; sq main.c; mkmake >/dev/null 2>&1 || return 1
    local out rc; out=$(PATH=$stub:$PATH rund 2>&1); rc=$?
    [[ $rc != 0 && $out == *AddressSanitizer* ]]
}
t_make_run_exit() {
    fresh mre; printf 'all:\n\t@true\nrun:\n\t@exit 3\n' > Makefile
    local out rc; out=$(run 2>&1); rc=$?
    [[ $rc == 3 && $out == *"exit 3, "* ]]
}
t_make_run_file() {
    fresh mrf; sq main.c; printf 'mrf: main.c\n\tcc -o mrf main.c\n' > Makefile
    printf '#!/bin/sh\necho NOT-THIS\n' > run; chmod +x run
    local out; out=$(echo 4 | run 2>&1); [[ $out == *"4 squared is 16"* && $out != *NOT-THIS* ]]
}
t_mkmake_spaces() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh "my dir"; sq main.c; mkmake >/dev/null 2>&1 && make -s >/dev/null 2>&1 || return 1
    t1 "a b" 2 "Give me a number: 2 squared is 4"
    make -s test >/dev/null 2>&1 && [[ $(echo 3 | run 2>&1) == *"3 squared is 9"* ]] && rut 2>&1 | grep -q "All tests passed"
}
t_mkmake_test_fails() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh mtf; sq main.c; mkmake >/dev/null 2>&1 || return 1; t1 a 3 wrong; ! make -s test >/dev/null 2>&1
}

check c_source_edit          t_c_source_edit
check c_multi_skip           t_c_multi_skip
check c_subdir_header        t_c_subdir_header
check c_older_restore        t_c_older_restore
check exit_red               t_exit_red
check exit_dim               t_exit_dim
check exit_on_stderr         t_exit_on_stderr
check make_beats_cargo       t_make_beats_cargo
check cargo_here_beats_c     t_cargo_here_beats_c
check local_c_beats_cargo_above t_local_c_beats_cargo_above
if command -v cargo >/dev/null; then
    check rust_named_lone t_rust_named_lone
    check rust_release    t_rust_release
fi
check rund_no_summary        t_rund_no_summary
if command -v make >/dev/null; then
    check rund_asan_make     t_rund_asan_make
    check mkmake_spaces      t_mkmake_spaces
    check mkmake_test_fails  t_mkmake_test_fails
fi
check make_run_exit          t_make_run_exit
check make_run_file          t_make_run_file

# ── polish (2026-10-22, his picks): rut crashes, program arguments, one cargo call, fallback notes
t_rut_crash() {
    fresh rcr; printf '#include <stdio.h>\n#include <stdlib.h>\nint main(void) { puts("ok"); fflush(stdout); abort(); }\n' > c.c
    t1 a "" "ok"
    local out rc; out=$(rut c.c 2>&1); rc=$?
    [[ $rc != 0 && $out == *crashed* ]]
}
argsc() { printf '#include <stdio.h>\nint main(int c, char **v) { for (int i = 1; i < c; i++) printf("[%%s]", v[i]); puts(""); return 0; }\n' > "$1"; }
t_run_args()   { fresh ra; argsc a.c; [[ $(run a.c -a 5 "x y" 2>&1) == *"[5][x y]"* ]]; }
t_rud_args()   { fresh rda; argsc a.c; [[ $(PATH=$stub:$PATH rud a.c -a 5 2>&1) == *"LLDB -- ./a 5"* ]]; }
t_rund_args()  { fresh rva; argsc a.c; [[ $(PATH=$stub:$PATH rund a.c -a 7 2>&1) == *"./a 7"* ]]; }
t_run_args_py(){ fresh rap; echo 'import sys; print(sys.argv[1:])' > a.py; [[ $(run a.py -a 5 2>&1) == *"['5']"* ]]; }
t_run_args_make() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh ram2; argsc main.c; mkmake >/dev/null 2>&1 || return 1
    [[ $(run -a 5 6 2>&1) == *"[5][6]"* ]]
}
t_rust_one_cargo() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    local real; real=$(command -v cargo)
    local d=$T/cargolog; mkdir -p "$d"
    printf '#!/bin/sh\necho call >> "%s/calls"\nexec "%s" "$@"\n' "$d" "$real" > "$d/cargo"; chmod +x "$d/cargo"
    fresh roc; "$real" new -q --vcs none sqr && cd sqr || return 1
    PATH=$d:$PATH run >/dev/null 2>&1 || return 1
    rm -f "$d/calls"; PATH=$d:$PATH run >/dev/null 2>&1
    [[ $(wc -l < "$d/calls") == 1 ]]
}
t_gdb_note()   { fresh gn; sq sq.c; local p; p=$(nolldb); [[ $(PATH=$p rud sq.c 2>&1) == *"lldb not found, using gdb"* ]]; }
t_venv_broken_note() {
    fresh vb; echo 'print("RAN")' > a.py; mkdir -p .venv/bin; ln -s /nonexistent/python .venv/bin/python
    local out; out=$(run a.py 2>&1); [[ $out == *RAN* && $out == *".venv/bin/python is broken"* ]]
}
t_mkmake_debug_gdb() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh mdg; sq main.c; mkmake >/dev/null 2>&1 && grep -q 'gdb --args' Makefile
}

check rut_crash        t_rut_crash
check run_args         t_run_args
check rud_args         t_rud_args
check rund_args        t_rund_args
check run_args_py      t_run_args_py
if command -v make >/dev/null; then
    check run_args_make    t_run_args_make
    check mkmake_debug_gdb t_mkmake_debug_gdb
fi
if command -v cargo >/dev/null; then check rust_one_cargo t_rust_one_cargo; fi
check gdb_note         t_gdb_note
# shellcheck disable=SC2016  # literal $HOME is the point: it must reach the program unexpanded
t_run_args_make_quoting() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh rmq; argsc main.c; mkmake >/dev/null 2>&1 || return 1
    local out; out=$(run -a 'x y' "it's" '$HOME' 'a;echo PWNED' 2>&1)
    [[ $out == *'[x y][it'"'"'s][$HOME][a;echo PWNED]'* && $out != *$'\nPWNED'* ]]
}
t_rut_exit255_ok() {
    fresh r255; printf '#include <stdio.h>\nint main(void) { puts("bad input"); return -1; }\n' > e.c
    t1 a "" "bad input"; rut e.c 2>&1 | grep -q "All tests passed"
}
t_args_swallow_note() { fresh asn; argsc a.c; [[ $(run a.c -a 5 -O 2 2>&1) == *"everything after -a goes to the program"* ]]; }
t_ru_refuses_a()  { fresh rra; sq sq.c; local out; ! out=$(ru sq.c -a 5 2>&1) && [[ $out == *"-a is for run, rud and rund"* ]]; }
# shellcheck disable=SC2016  # $(ARGS) is the literal text of the note
t_make_args_ignored_note() {
    fresh mai; printf 'all:\n\t@true\nrun:\n\t@echo RAN\n' > Makefile
    local out; out=$(run -a 5 2>&1); [[ $out == *RAN* && $out == *'does not use $(ARGS)'* ]]
}
t_lldb_no_note()  { fresh lnn; sq sq.c; [[ $(PATH=$stub:$PATH rud sq.c 2>&1) != *"using gdb"* ]]; }
t_rust_compile_error() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rce; cargo new -q --vcs none bad && cd bad || return 1
    printf 'fn main() { let x: i32 = "no"; println!("RAN {x}"); }\n' > src/main.rs
    local out rc; out=$(run 2>&1); rc=$?
    # No "exit" line means the program never ran (the error message itself quotes the source).
    [[ $rc == 1 && $out == *"mismatched types"* && $out != *"exit "* ]]
}
t_rust_library() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rlib; cargo new -q --vcs none --lib lb && cd lb || return 1
    local out; out=$(run 2>&1); [[ $out == *"built no program"* ]] || { echo "$out"; return 1; }
}
check run_args_make_quoting t_run_args_make_quoting
check rut_exit255_ok        t_rut_exit255_ok
check args_swallow_note     t_args_swallow_note
check ru_refuses_a          t_ru_refuses_a
check make_args_ignored_note t_make_args_ignored_note
check lldb_no_note          t_lldb_no_note
if command -v cargo >/dev/null; then
    check rust_compile_error t_rust_compile_error
    check rust_library       t_rust_library
fi
check venv_broken_note t_venv_broken_note

echo "$pass passed, $fail failed"
(( fail == 0 ))
