#!/usr/bin/env bash
# tests/dev.sh — the dev commands (lib/dev.sh) on tiny real programs.
#
#   bash tests/dev.sh
#
# Everything is built inside one temp folder that is deleted at the end; the
# build-skip stamps go there too (XDG_CACHE_HOME). A check that needs a tool the
# machine lacks (cargo, clang) prints "skip" instead of failing.
# Exit status is non-zero on any failure, so smoke.sh, CI and the pre-push hook can run it.
# The tests write many small scripts and Makefiles whose $... must stay literal
# (a directive before the first command covers the whole file).
# shellcheck disable=SC2016
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
    [[ -x sq && $out == *-std=gnu17* && $out == *-fsanitize=address,undefined* && $out == *-lm* ]]
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
    [[ -x a && $out == *-std=gnu++20* ]]
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
    # The program aborts on purpose. Its name starts with omarchy-crash- so the
    # laptop's "Process crashed" notice (and the Claude session it opens) skips it,
    # whatever the build flags; ASan alone only hides the core in the run build.
    fresh rcr; printf '#include <stdio.h>\n#include <stdlib.h>\nint main(void) { puts("ok"); fflush(stdout); abort(); }\n' > omarchy-crash-c.c
    t1 a "" "ok"
    local out rc; out=$(rut omarchy-crash-c.c 2>&1); rc=$?
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

# ── gaps found by mutation testing (2026-10-23): each check below fails when the named bug is put into lib/dev.sh
# fails_with MSG CMD...: CMD must fail and its output must contain MSG.
fails_with() { local out; ! out=$("${@:2}" 2>&1) && [[ $out == *"$1"* ]]; }
# vgstub NAME BODY: a valgrind stand-in that runs BODY; echoes the folder to put on PATH.
vgstub() { local d=$T/vg-$1; mkdir -p "$d"; printf '#!/bin/sh\n%s\n' "$2" > "$d/valgrind"; chmod +x "$d/valgrind"; echo "$d"; }
# argse FILE: a C program that prints its arguments to stderr, as [a][b].
argse() { printf '#include <stdio.h>\nint main(int c, char **v) { for (int i = 1; i < c; i++) fprintf(stderr, "[%%s]", v[i]); fputs("\\n", stderr); return 0; }\n' > "$1"; }

# detection and naming
t_detect_makefile_names() { fresh dmn; touch a.c makefile; [[ $(_dev_detect) == make ]] || return 1; rm makefile; touch GNUmakefile; [[ $(_dev_detect) == make ]]; }
t_detect_cc_cxx()  { fresh dcx; touch a.cc; [[ $(_dev_detect) == cpp ]] || return 1; rm a.cc; touch b.cxx; [[ $(_dev_detect) == cpp ]]; }
t_unknown_file()   { fresh unf; touch notes.txt; fails_with "don't know how to build 'notes.txt'" ru notes.txt; }
t_name_dots()      { fresh nd; sq my.prog.c; ru my.prog.c >/dev/null 2>&1 && [[ -x my.prog ]]; }

# C and C++ builds
t_c_compile_error() {
    fresh cce; printf 'int main(void) { return 7; }\n' > e.c
    run e.c >/dev/null 2>&1; [[ $? == 7 ]] || return 1            # a good build first
    printf 'int main(void) { return 8 }\n' > e.c; later e.c        # now a syntax error
    local out rc; out=$(run e.c 2>&1); rc=$?
    [[ $rc != 0 && $out != *"exit "* ]] || { echo "the old binary ran"; return 1; }
    ! ru e.c >/dev/null 2>&1
}
t_c_missing_source() { fresh cms; fails_with "'nofile.c' not found" ru nofile.c; }
t_c_default_flags()  { fresh cdf; sq sq.c; local out; out=$(ru sq.c 2>&1); [[ $out == *" -g "* && $out == *"-Wall -Wextra "* ]]; }
t_c_warn_list()      { fresh cwl; printf 'int main(void) { int unused; return 0; }\n' > w.c; local out; ! out=$(ru -W all,error w.c 2>&1) && [[ $out == *"-Wall -Werror"* ]]; }
t_parse_W() {
    fresh pw; sq sq.c
    local out; out=$(ru sq.c -W -O 2 2>&1) || return 1             # -W before a flag means no warnings
    [[ $out == *-O2* && $out != *-Wall* && $out != *"-W-O"* ]] || return 1
    out=$(ru -W sq.c 2>&1) || return 1                              # -W before a file means no warnings
    [[ $out != *-Wsq.c* && -x sq ]]
}
t_parse_errors() {
    fresh pe; sq sq.c; sq b.c
    fails_with "-f requires" ru -f || return 1
    fails_with "-O requires" ru sq.c -O -W || return 1
    fails_with "name one file" ru sq.c b.c
}
t_ru_python()   { fresh rpy; sqpy a.py; local out; out=$(ru a.py 2>&1) && [[ $out == *"Nothing to build for Python"* ]]; }

# build skipping: what the fingerprint must notice, and what it must still let skip
t_c_same_mtime_edit() {
    fresh csm; printf 'int main(void) { return 5; }\n' > r.c; touch -d '2001-01-01' r.c
    run r.c >/dev/null 2>&1
    printf 'int main(void) { return 55; }\n' > r.c; touch -d '2001-01-01' r.c   # another size, same date (cp -p, git checkout)
    run r.c >/dev/null 2>&1; [[ $? == 55 ]]
}
t_c_binary_replaced() {
    fresh cbr; sq sq.c; ru sq.c >/dev/null 2>&1 || return 1
    command cp -f /bin/true sq                                         # say a Makefile rebuilt ./sq with other flags (a real program: a script there is refused)
    [[ $(ru sq.c 2>&1) == *'[compile]'* ]]
}
t_c_obj_change() {
    local cc; cc=$(command -v clang || command -v gcc) || { echo "no cc"; return 0; }
    fresh cob; printf 'int f(void) { return 1; }\n' > f.c; printf 'int f(void);\nint main(void) { return f(); }\n' > m.c
    "$cc" -c f.c -o f.o && { run -f m.c f.o >/dev/null 2>&1; [[ $? == 1 ]]; } || return 1
    printf 'int f(void) { return 2; }\n' > f.c; "$cc" -c f.c -o f.o; later f.o
    run -f m.c f.o >/dev/null 2>&1; [[ $? == 2 ]]
}
t_c_skip_with_I() {
    fresh csi; mkdir inc; echo '#define K 3' > inc/k.h; printf '#include "k.h"\nint main(void) { return K; }\n' > k.c
    run k.c -- -Iinc >/dev/null 2>&1; [[ $(run k.c -- -Iinc 2>&1) != *'[compile]'* ]]
}
t_c_skip_space_header() {
    fresh csh; echo '#define K 3' > 'my hdr.h'; printf '#include "my hdr.h"\nint main(void) { return K; }\n' > s.c
    run s.c >/dev/null 2>&1; [[ $(run s.c 2>&1) != *'[compile]'* ]] || return 1
    echo '#define K 4' > 'my hdr.h'; later 'my hdr.h'; run s.c >/dev/null 2>&1; [[ $? == 4 ]]
}
t_c_skip_many_headers() {
    fresh cmh; local i inc=""
    for i in 1 2 3 4 5 6 7 8; do echo "#define K$i $i" > "a_long_header_name_number_$i.h"; inc+="#include \"a_long_header_name_number_$i.h\""$'\n'; done
    printf '%sint main(void) { return K8; }\n' "$inc" > m.c
    run m.c >/dev/null 2>&1; [[ $(run m.c 2>&1) != *'[compile]'* ]]   # cc -MM wraps a long list over several lines
}

# run: Python and Makefile corners, the exit line
t_py_several()      { fresh psv; touch a.py b.py; fails_with "several Python files" run; }
t_make_run_spaced() { fresh mrs; printf 'all:\n\t@true\nrun :\n\t@echo MADE\n' > Makefile; [[ $(run 2>&1) == *MADE* ]]; }
t_make_run_var() {
    fresh mrv; sq main.c; printf 'run := nothing\nmrv: main.c\n\tcc -o mrv main.c\n' > Makefile   # a variable called run is not a target
    [[ $(echo 4 | run 2>&1) == *"4 squared is 16"* ]]
}
t_make_run_stderr() { fresh mrse; printf 'all:\n\t@true\nrun:\n\t@echo ERRMSG >&2\n' > Makefile; [[ $(run 2>&1 >/dev/null) == *ERRMSG* ]]; }
t_make_run_quiet()  { fresh mrq; printf 'all:\n\t@true\nrun:\n\techo MADE\n' > Makefile; local out; out=$(run 2>&1); [[ $out == *MADE* && $out != *"echo MADE"* ]]; }
t_make_run_no_tmp_leak() {
    fresh mtl; printf 'all:\n\t@true\nrun:\n\t@echo hi\n' > Makefile; mkdir "$T/tl"
    TMPDIR=$T/tl run >/dev/null 2>&1; [[ -z $(ls -A "$T/tl") ]]
}
t_make_missing_prog() { fresh mmp; printf 'all:\n\t@true\n' > Makefile; fails_with "can't tell which program the Makefile builds" run; }
t_exit_secs()   { fresh esc; printf 'int main(void) { return 0; }\n' > z.c; [[ $(run z.c 2>&1) =~ exit\ 0,\ [0-9]+\.[0-9][0-9]\ s ]]; }
t_rust_lone_opt() {
    command -v rustc >/dev/null || { echo "no rustc"; return 0; }
    fresh rlo; printf 'fn main() {}\n' > a.rs; [[ $(run -O 2 a.rs 2>&1) == *"-Copt-level=2"* ]]
}

# rud and rund
t_rud_gdb_args() { fresh dga; argsc a.c; local p; p=$(nolldb); [[ $(PATH=$p rud a.c -a 5 2>&1) == *"GDB --args ./a 5"* ]]; }
t_rud_py_args()  { fresh dpa; sqpy a.py; [[ $(PATH=$stub:$PATH rud a.py -a 5 2>&1) == *"PY -m pdb a.py 5"* ]]; }
t_rud_ignores_O(){ fresh dio; sq sq.c; local out; out=$(PATH=$stub:$PATH rud sq.c -O 2 2>&1); [[ $out == *" -O0 "* && $out != *" -O2 "* ]]; }
t_rund_result() {
    fresh rrs; sq sq.c; local d out
    d=$(vgstub ok 'echo "==1== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)" >&2')
    PATH=$d:$PATH rund sq.c >/dev/null 2>&1 || { echo "a clean run returned non-zero"; return 1; }
    d=$(vgstub err 'echo "==1== ERROR SUMMARY: 2 errors from 1 contexts (suppressed: 0 from 0)" >&2')
    ! PATH=$d:$PATH rund sq.c >/dev/null 2>&1 || { echo "errors returned 0"; return 1; }
    d=$(vgstub leak 'echo "==1==    definitely lost: 16 bytes in 1 blocks" >&2; echo "==1== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)" >&2')
    ! out=$(PATH=$d:$PATH rund sq.c 2>&1) && [[ $out == *LEAKS* ]]
}
t_rund_missing_input() { fresh rmi; sq sq.c; PATH=$stub:$PATH fails_with "input file 'nope.txt' not found" rund -i nope.txt sq.c; }

# rut
t_rut_segv() {
    fresh rsg; ulimit -c 0
    printf '#include <stdio.h>\nint main(void) { puts("ok"); fflush(stdout); *(volatile int *)0 = 1; return 0; }\n' > omarchy-crash-seg.c
    t1 a "" "ok"
    local out rc; out=$(rut omarchy-crash-seg.c -- -fno-sanitize=address,undefined 2>&1); rc=$?   # without ASan, which would turn the SEGV into exit 1
    [[ $rc != 0 && $out == *"signal 11"* ]]
}
t_rut_stderr() {
    fresh rse; printf '#include <stdio.h>\nint main(void) { fputs("oops\\n", stderr); return 0; }\n' > e.c
    t1 a "" oops; rut e.c 2>&1 | grep -q "All tests passed"
}
t_rut_args()    { fresh rta; argsc a.c; t1 a "" "[5][6]"; echo "5 6" > a.args; rut a.c 2>&1 | grep -q "All tests passed"; }
t_rut_verbose() { fresh rtv; sq sq.c; t1 a 3 "Give me a number: 3 squared is 9"; [[ $(rut sq.c -v 2>&1) == *Expected:* && $(rut sq.c 2>&1) != *Expected:* ]]; }
t_rut_dir() {
    fresh rtd; sq sq.c; mkdir tests; t1 tests/a 3 "Give me a number: 3 squared is 9"
    [[ $(rut sq.c -d tests 2>&1) == *"All tests passed"*"1/1"* ]]
}
t_rut_errors() {
    fresh rte; sq sq.c
    fails_with "no *.in files" rut sq.c || return 1
    fails_with "test directory 'nope' not found" rut sq.c -d nope || return 1
    echo 3 > a.in; fails_with "missing or unreadable expected output" rut sq.c
}
t_rut_refuses_a() { fresh rra2; sq sq.c; t1 a 3 "Give me a number: 3 squared is 9"; fails_with "rut takes arguments from" rut sq.c -a 5; }

# mkt
t_mkt_files() { fresh mk; mkt a >/dev/null && [[ -e a.in && -e a.expect && ! -e a.args ]] && mkt -a b >/dev/null && [[ -e b.in && -e b.expect && -e b.args ]]; }

# mkmake
t_mkmake_same_build() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh msb; sq main.c; mkmake >/dev/null 2>&1 || return 1
    [[ $(make -n 2>&1) == *"-std=gnu17 -Wall -Wextra -g -O0 -fsanitize=address,undefined main.c -o msb -lm"* ]]
}
t_mkmake_header_rebuild() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh mhr; echo '#define K 3' > k.h; printf '#include "k.h"\nint main(void) { return K; }\n' > main.c
    mkmake >/dev/null 2>&1 && make -s >/dev/null 2>&1 || return 1
    later k.h; [[ $(make -n 2>&1) == *"-o mhr"* ]]
}
t_mkmake_debug_lldb() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh mdl; sq main.c; mkmake >/dev/null 2>&1 || return 1
    [[ $(PATH=$stub:$PATH make debug ARGS=5 2>&1) == *"LLDB -- ./mdl 5"* ]]
}
t_mkmake_test_args_stderr() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh mta; argse main.c; mkmake >/dev/null 2>&1 || return 1
    t1 a "" "[5][6]"; echo "5 6" > a.args; make -s test >/dev/null 2>&1
}
t_mkmake_phony_clean() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh mpc; sq main.c; mkmake >/dev/null 2>&1 && make -s >/dev/null 2>&1 && [[ -x mpc ]] || return 1
    t1 a 3 "Give me a number: 3 squared is 9"; touch test       # a file called test must not stop make test
    [[ $(make -s test 2>&1) == *"1 passed, 0 failed"* ]] || return 1
    make -s clean >/dev/null 2>&1; [[ ! -e mpc ]]
}
t_mkmake_cpp() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh mcp; printf '#include <iostream>\nint main() { std::cout << "hi\\n"; }\n' > a.cc
    mkmake >/dev/null 2>&1 || return 1
    [[ $(make -n 2>&1) == *"-std=gnu++20"* ]] && make -s >/dev/null 2>&1 && [[ $(./mcp) == hi ]]
}
t_mkmake_refuses_names() {
    fresh mrn; sq main.c; touch makefile; fails_with "already exists" mkmake || return 1
    rm makefile; touch GNUmakefile; fails_with "already exists" mkmake
}
t_mkmake_python_refused() { fresh mpy; touch a.py; fails_with "C and C++" mkmake; }

check detect_makefile_names  t_detect_makefile_names
check detect_cc_cxx          t_detect_cc_cxx
check unknown_file           t_unknown_file
check name_dots              t_name_dots
check c_compile_error        t_c_compile_error
check c_missing_source       t_c_missing_source
check c_default_flags        t_c_default_flags
check c_warn_list            t_c_warn_list
check parse_W                t_parse_W
check parse_errors           t_parse_errors
check ru_python              t_ru_python
check c_same_mtime_edit      t_c_same_mtime_edit
check c_binary_replaced      t_c_binary_replaced
check c_obj_change           t_c_obj_change
check c_skip_with_I          t_c_skip_with_I
check c_skip_space_header    t_c_skip_space_header
check c_skip_many_headers    t_c_skip_many_headers
check py_several             t_py_several
check make_run_spaced        t_make_run_spaced
check make_run_var           t_make_run_var
check make_run_stderr        t_make_run_stderr
check make_run_quiet         t_make_run_quiet
check make_run_no_tmp_leak   t_make_run_no_tmp_leak
check make_missing_prog      t_make_missing_prog
check exit_secs              t_exit_secs
if command -v rustc >/dev/null; then check rust_lone_opt t_rust_lone_opt; fi
check rud_gdb_args           t_rud_gdb_args
check rud_py_args            t_rud_py_args
check rud_ignores_O          t_rud_ignores_O
check rund_result            t_rund_result
check rund_missing_input     t_rund_missing_input
check rut_segv               t_rut_segv
check rut_stderr             t_rut_stderr
check rut_args               t_rut_args
check rut_verbose            t_rut_verbose
check rut_dir                t_rut_dir
check rut_errors             t_rut_errors
check rut_refuses_a          t_rut_refuses_a
check mkt_files              t_mkt_files
if command -v make >/dev/null; then
    check mkmake_same_build        t_mkmake_same_build
    check mkmake_header_rebuild    t_mkmake_header_rebuild
    check mkmake_debug_lldb        t_mkmake_debug_lldb
    check mkmake_test_args_stderr  t_mkmake_test_args_stderr
    check mkmake_phony_clean       t_mkmake_phony_clean
    check mkmake_cpp               t_mkmake_cpp
fi
check mkmake_refuses_names   t_mkmake_refuses_names
check mkmake_python_refused  t_mkmake_python_refused


# ── hardening round 1 (2026-10-23): adversarial C/C++, Rust/Python/Make and shell-safety findings
# cshim NAME SCRIPT: a stand-in C compiler folder; SCRIPT runs after the real clang/gcc.
cshim() {
    local d=$T/cshim-$1 real; real=$(command -v clang || command -v gcc); mkdir -p "$d"
    printf '#!/bin/sh\n"%s" "$@"; rc=$?\n%s\nexit $rc\n' "$real" "$2" > "$d/clang"; chmod +x "$d/clang"; echo "$d"
}
t_c_symlink_source() {
    fresh csl; echo 'int main(void) { return 1; }' > real.c; ln -s real.c a.c
    run a.c >/dev/null 2>&1; echo 'int main(void) { return 2; }' > real.c; later real.c
    run a.c >/dev/null 2>&1; [[ $? == 2 ]]
}
t_c_same_second_edit() {
    fresh css; echo 'int main(void) { return 1; }' > a.c; run a.c >/dev/null 2>&1
    sed -i 's/return 1/return 2/' a.c; run a.c >/dev/null 2>&1; [[ $? == 2 ]]   # same size, same second
}
t_c_edit_during_compile() {
    fresh cdc; echo 'int main(void) { return 1; }' > a.c
    local d; d=$(cshim edit "sed -i 's/return 1/return 2/' \"$T/w/cdc/a.c\"")   # the user saves while it compiles
    PATH=$d:$PATH run a.c >/dev/null 2>&1                                         # built from the old text
    run a.c >/dev/null 2>&1; [[ $? == 2 ]]
}
t_c_o_refuses_source()   { fresh cor; sq a.c; fails_with "would overwrite" ru a.c -o a.c && grep -q main a.c; }
t_c_refuses_nonprogram() { fresh crn; sq notes.c; echo "my notes" > notes; fails_with "isn't a program" ru notes.c && [[ $(cat notes) == "my notes" ]]; }
t_compile_line_stderr()  { fresh cls; sq sq.c; echo 3 | run sq.c > out.txt 2>/dev/null; ! grep -q compile out.txt && grep -q "9" out.txt; }
t_dashdash_then_a() {
    fresh dda; printf '#include <stdio.h>\nint main(int c, char **v) { printf("%%d %%s\\n", X, c > 1 ? v[1] : "-"); return 0; }\n' > a.c
    [[ $(run a.c -- -DX=7 -a five 2>&1) == *"7 five"* ]]
}
t_abs_o()        { fresh abo; sq sq.c; mkdir out; [[ $(echo 2 | run sq.c -o "$T/w/abo/out/p" 2>&1) == *"2 squared is 4"* ]]; }
t_dash_name()    { fresh dsh; sq ./-x.c; [[ $(echo 3 | run 2>&1) == *"3 squared is 9"* ]]; }
t_gnu_functions() {
    fresh gnu; printf '#include <string.h>\n#include <stdlib.h>\n#include <math.h>\nint main(void) { char *s = strdup("hi"); int r = (int)M_PI; free(s); return r; }\n' > g.c
    run g.c >/dev/null 2>&1; [[ $? == 3 ]]
}
t_file_plus_f() {
    fresh fpf; printf 'int f(void);\nint main(void) { return f(); }\n' > a.c; printf 'int f(void) { return 4; }\n' > b.c
    run a.c -f b.c >/dev/null 2>&1; [[ $? == 4 ]]
}
t_f_obj_first() {
    local cc; cc=$(command -v clang || command -v gcc) || { echo "no cc"; return 0; }
    fresh fof; printf 'int f(void) { return 6; }\n' > f.c; "$cc" -c f.c -o f.o; rm f.c
    printf 'int f(void);\nint main(void) { return f(); }\n' > m.c; touch helper.py
    run -f f.o m.c >/dev/null 2>&1; [[ $? == 6 ]]
}
t_upper_ext()    { fresh uex; printf '#include <iostream>\nint main() { std::cout << "UP\\n"; }\n' > Main.CPP; [[ $(run Main.CPP 2>&1) == *UP* ]]; }
t_isystem_stale() {
    fresh isy; mkdir inc; echo '#define K 3' > inc/k.h; printf '#include <k.h>\nint main(void) { return K; }\n' > k.c
    run k.c -- -isystem inc >/dev/null 2>&1; echo '#define K 4' > inc/k.h; later inc/k.h
    run k.c -- -isystem inc >/dev/null 2>&1; [[ $? == 4 ]]
}
t_glued_options() { fresh glo; sq sq.c; local out; out=$(ru sq.c -O2 -Wall 2>&1) && [[ $out == *-O2* && $out == *-Wall* ]]; }
t_run_input_file() { fresh rif; sq sq.c; echo 6 > in.txt; [[ $(run sq.c -i in.txt 2>&1) == *"6 squared is 36"* ]]; }
t_ru_refuses_i()   { fresh rri; sq sq.c; echo 6 > in.txt; fails_with "-i" ru sq.c -i in.txt; }

# Rust: which program, named files, symlinked folders, editions
rsproj() {   # rsproj NAME: a Cargo project NAME with main printing MAIN and src/bin/zebra.rs printing ZEBRA
    cargo new -q --vcs none "$1" && mkdir -p "$1/src/bin" || return 1
    echo 'fn main() { println!("MAIN"); }' > "$1/src/main.rs"; echo 'fn main() { println!("ZEBRA"); }' > "$1/src/bin/zebra.rs"
}
t_rust_main_preferred() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rmp; rsproj p && cd p || return 1; local i; for i in 1 2 3; do touch src/main.rs src/bin/zebra.rs; [[ $(run 2>&1) == *MAIN* ]] || return 1; done
}
t_rust_default_run() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rdr; rsproj p && cd p || return 1; sed -i 's/^\[package\]/[package]\ndefault-run = "zebra"/' Cargo.toml
    [[ $(run 2>&1) == *ZEBRA* ]]
}
t_rust_named_bin() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rnb; rsproj p && cd p || return 1; [[ $(run src/bin/zebra.rs 2>&1) == *ZEBRA* ]]
}
t_rust_ambiguous() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh ram; cargo new -q --vcs none p && cd p && mkdir src/bin && rm src/main.rs || return 1
    echo 'fn main() { println!("A"); }' > src/bin/a.rs; echo 'fn main() { println!("B"); }' > src/bin/b.rs
    fails_with "several programs" run
}
t_rust_named_module() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rnm; rsproj p && cd p || return 1; echo 'fn main() { println!("SCRATCH"); }' > src/scratch.rs
    [[ $(run src/scratch.rs 2>&1) == *SCRATCH* ]]
}
t_rust_named_missing() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rnx; rsproj p && cd p || return 1; fails_with "not found" run src/nope.rs
}
t_rust_symlink_dir() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rsd2; rsproj real || return 1; ln -s real link; cd link || return 1
    [[ $(run src/main.rs 2>&1) == *MAIN* && ! -e main ]]
}
t_rust_lone_edition() {
    command -v rustc >/dev/null || { echo "no rustc"; return 0; }
    fresh rle; echo 'fn main() { let x = u8::try_from(5i32).unwrap(); println!("ED{x}"); }' > e.rs
    [[ $(run e.rs 2>&1) == *ED5* ]]
}
t_rust_refuses_o() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rro; cargo new -q --vcs none p && cd p || return 1; fails_with "don't apply to Rust" ru -o x
}

# Makefiles: which program, the default goal, run targets, exit codes, mkmake names
t_make_stale_folder_binary() {
    fresh m5; printf 'int main(void) { return 9; }\n' > old.c; cc -o m5 old.c
    printf 'int main(void) { return 3; }\n' > main.c; printf 'main: main.c\n\tcc -o main main.c\n' > Makefile
    run >/dev/null 2>&1; [[ $? == 3 ]]
}
t_make_run_first_target() {
    fresh mrf2; printf 'run:\n\t@read x; echo "hi $$x"\n' > Makefile
    local out; out=$(echo Bob | run 2>&1)
    [[ $out == *"hi Bob"* && $(grep -c '^hi' <<<"$out") == 1 ]]   # once, not twice
}
t_make_default_clean() {
    fresh mdc; sq main.c; touch keep.me
    printf 'clean:\n\trm -f keep.me\nmdc: main.c\n\tcc -o mdc main.c\nrun: mdc\n\t./mdc\n' > Makefile
    echo 2 | run >/dev/null 2>&1; [[ -e keep.me ]]
}
t_make_run_multi()   { fresh mrm; printf 'all:\n\t@true\nrun test:\n\t@echo MULTI\n' > Makefile; [[ $(run 2>&1) == *MULTI* ]]; }
t_make_run_include() { fresh mri; printf 'all:\n\t@true\ninclude extra.mk\n' > Makefile; printf 'run:\n\t@echo INCLUDED\n' > extra.mk; [[ $(run 2>&1) == *INCLUDED* ]]; }
t_make_recursive_exit() {
    fresh mrx; mkdir sub; printf 'run:\n\t@exit 6\n' > sub/Makefile; printf 'all:\n\t@true\nrun:\n\t@$(MAKE) -s -C sub run\n' > Makefile
    run >/dev/null 2>&1; [[ $? == 6 ]]
}
t_make_run_segv() {
    fresh omarchy-crash-mseg; ulimit -c 0
    printf 'int main(void) { *(volatile int *)0 = 1; return 0; }\n' > main.c
    printf 'omarchy-crash-mseg: main.c\n\tcc -o omarchy-crash-mseg main.c\nrun: omarchy-crash-mseg\n\t./omarchy-crash-mseg\n' > Makefile
    run >/dev/null 2>&1; [[ $? == 139 ]]
}
t_make_prog_colon() { fresh mpc2; sq main.c; printf 'PROG := sq\nall: $(PROG)\n$(PROG): main.c\n\tcc -o $(PROG) main.c\n' > Makefile; [[ $(echo 5 | run 2>&1) == *"5 squared is 25"* ]]; }
t_mkmake_reserved_folder() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh test; sq main.c; mkmake >/dev/null 2>&1 && make -s >/dev/null 2>&1 || return 1
    [[ $(echo 3 | run 2>&1) == *"3 squared is 9"* ]]
}
t_mkmake_weird_folder() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh "Lab 3 (final) #2"; sq main.c; mkmake >/dev/null 2>&1 && make -s >/dev/null 2>&1 || return 1
    [[ $(echo 3 | run 2>&1) == *"3 squared is 9"* ]] && t1 a 2 "Give me a number: 2 squared is 4" && rut 2>&1 | grep -q "All tests passed"
}
t_mkmake_spaced_source() { fresh mss; sq "my prog.c"; fails_with "rename" mkmake; }
t_mkmake_test_crash() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh omarchy-crash-mt; ulimit -c 0
    printf '#include <stdio.h>\n#include <stdlib.h>\nint main(void) { puts("ok"); fflush(stdout); abort(); }\n' > main.c
    mkmake >/dev/null 2>&1 && make -s SANITIZE= >/dev/null 2>&1 || return 1; t1 a "" ok
    ! make -s test >/dev/null 2>&1
}
t_mkmake_test_no_in() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh mtn; sq main.c; mkmake >/dev/null 2>&1 || return 1; ! make -s test >/dev/null 2>&1
}
t_mkmake_mixed()   { fresh mmx; touch a.c b.cpp; fails_with "not both" mkmake; }

# Python: packages, a .venv in a parent folder
t_py_package() {
    fresh ppk; mkdir pkg; touch pkg/__init__.py; echo 'X = "PKG"' > pkg/util.py
    printf 'from .util import X\nprint(X)\n' > pkg/__main__.py
    [[ $(run pkg 2>&1) == *PKG* ]] && cd pkg && [[ $(run 2>&1) == *PKG* ]]
}
t_py_parent_venv() {
    fresh ppv; mkdir -p .venv/bin src; printf '#!/bin/sh\necho VENV "$@"\n' > .venv/bin/python; chmod +x .venv/bin/python
    sqpy src/main.py; cd src && [[ $(run 2>&1) == *"VENV main.py"* ]]
}

# your shell: noclobber, set -e, aliases, globbing, traps
t_noclobber_rut() {
    fresh ncr; sq sq.c; t1 a 3 "Give me a number: 3 squared is 9"; t1 b 4 "wrong"
    local out; out=$(set -C; rut sq.c 2>&1); [[ $out == *"1/2"* ]]
}
t_noclobber_stamp() {
    fresh ncs; echo 'int main(void) { return 1; }' > a.c
    ( set -C; run a.c ) >/dev/null 2>&1; echo 'int main(void) { return 22; }' > a.c; later a.c
    ( set -C; run a.c ) >/dev/null 2>&1; ( set -C; run a.c ) >/dev/null 2>&1; [[ $? == 22 ]]
}
t_rund_interrupted() {
    fresh rni; sq sq.c; local d
    d=$(vgstub int 'echo "==1== Process terminating with default action of signal 2 (SIGINT)" >&2; echo "==1== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)" >&2; exit 130')
    local out; ! out=$(PATH=$d:$PATH rund sq.c 2>&1) && [[ $out == *interrupted* ]]
}
t_alias_rm_safe() {
    fresh ars; echo 'int main(void) { return 0 }' > bad.c
    local out; out=$(bash -c 'shopt -s expand_aliases; alias rm="echo RMALIAS"; alias mkdir="echo MKALIAS"; . "$1"; ru bad.c' _ "$here/lib/dev.sh" 2>&1)
    [[ $out != *RMALIAS* && $out != *MKALIAS* ]]
}
t_args_no_glob()  { fresh ang; argsc a.c; touch x1 x2; echo '*' > a.args; t1 a "" "[*]"; rut a.c 2>&1 | grep -q "All tests passed"; }
t_set_e_survives() {
    fresh ses; sq sq.c; t1 a 3 "Give me a number: 3 squared is 9"
    local out; out=$(bash -c 'set -e; . "$1"; rut sq.c >/dev/null 2>&1; mkt x >/dev/null; echo SURVIVED' _ "$here/lib/dev.sh" 2>&1)
    [[ $out == *SURVIVED* ]]
}
t_mkt_fails_readonly() { fresh mro; chmod 555 .; ! mkt t >/dev/null 2>&1; local rc=$?; chmod 755 .; [[ $rc == 0 ]]; }
t_no_trap_leak()  { fresh ntl; sq sq.c; t1 a 3 "Give me a number: 3 squared is 9"; rut sq.c >/dev/null 2>&1; [[ -z $(trap -p RETURN) ]]; }
t_failglob_safe() { fresh fgs; sqpy a.py; [[ $(shopt -s failglob; echo 2 | run 2>&1) == *"2 squared is 4"* ]]; }

check c_symlink_source       t_c_symlink_source
check c_same_second_edit     t_c_same_second_edit
check c_edit_during_compile  t_c_edit_during_compile
check c_o_refuses_source     t_c_o_refuses_source
check c_refuses_nonprogram   t_c_refuses_nonprogram
check compile_line_stderr    t_compile_line_stderr
check dashdash_then_a        t_dashdash_then_a
check abs_o                  t_abs_o
check dash_name              t_dash_name
check gnu_functions          t_gnu_functions
check file_plus_f            t_file_plus_f
check f_obj_first            t_f_obj_first
check upper_ext              t_upper_ext
check isystem_stale          t_isystem_stale
check glued_options          t_glued_options
check run_input_file         t_run_input_file
check ru_refuses_i           t_ru_refuses_i
if command -v cargo >/dev/null; then
    check rust_main_preferred t_rust_main_preferred
    check rust_default_run    t_rust_default_run
    check rust_named_bin      t_rust_named_bin
    check rust_ambiguous      t_rust_ambiguous
    check rust_named_module   t_rust_named_module
    check rust_named_missing  t_rust_named_missing
    check rust_symlink_dir    t_rust_symlink_dir
    check rust_refuses_o      t_rust_refuses_o
fi
if command -v rustc >/dev/null; then check rust_lone_edition t_rust_lone_edition; fi
if command -v make >/dev/null; then
    check make_stale_folder_binary t_make_stale_folder_binary
    check make_run_first_target    t_make_run_first_target
    check make_default_clean       t_make_default_clean
    check make_run_multi           t_make_run_multi
    check make_run_include         t_make_run_include
    check make_recursive_exit      t_make_recursive_exit
    check make_run_segv            t_make_run_segv
    check make_prog_colon          t_make_prog_colon
    check mkmake_reserved_folder   t_mkmake_reserved_folder
    check mkmake_weird_folder      t_mkmake_weird_folder
    check mkmake_test_crash        t_mkmake_test_crash
    check mkmake_test_no_in        t_mkmake_test_no_in
fi
check mkmake_spaced_source   t_mkmake_spaced_source
check mkmake_mixed           t_mkmake_mixed
check py_package             t_py_package
check py_parent_venv         t_py_parent_venv
check noclobber_rut          t_noclobber_rut
check noclobber_stamp        t_noclobber_stamp
check rund_interrupted       t_rund_interrupted
check alias_rm_safe          t_alias_rm_safe
check args_no_glob           t_args_no_glob
check set_e_survives         t_set_e_survives
check mkt_fails_readonly     t_mkt_fails_readonly
check no_trap_leak           t_no_trap_leak
check failglob_safe          t_failglob_safe

# ── hardening round 2 (2026-10-23): .PHONY run, make's own error line, libraries,
# stdlib-named packages, PROG through make, Rust src paths and examples, mkmake names
progmk() {   # progmk: main.c printing RAN, built by a "prog" target
    printf '#include <stdio.h>\nint main(void) { puts("RAN"); return 0; }\n' > main.c
}
t_make_phony_run_norecipe() {
    fresh mpn; progmk; printf '.PHONY: all clean run\nall: prog\nprog: main.c\n\tcc -o prog main.c\nclean:\n\trm -f prog\n' > Makefile
    [[ $(run 2>&1) == *RAN* ]]
}
t_make_run_prereq_only() {
    fresh mrp; progmk; printf 'all: prog\nprog: main.c\n\tcc -o prog main.c\nrun: prog\n' > Makefile
    [[ $(run 2>&1) == *RAN* ]]
}
t_make_exit_program_text() {
    fresh met; printf '#include <stdio.h>\nint main(void) { fputs("Syntax Error 9\\n", stderr); return 1; }\n' > main.c
    printf 'all: prog\nprog: main.c\n\tcc -o prog main.c\nrun: prog\n\t./prog\n' > Makefile
    run >/dev/null 2>&1; [[ $? == 1 ]]
}
t_c_static_lib() {
    local cc; cc=$(command -v clang || command -v gcc) || { echo "no cc"; return 0; }
    fresh csl2; printf 'int f(void) { return 1; }\n' > x.c; "$cc" -c x.c -o x.o && ar rcs libx.a x.o
    printf 'int f(void);\nint main(void) { return f(); }\n' > main.c
    run main.c -f libx.a >/dev/null 2>&1; [[ $? == 1 ]] || return 1
    printf 'int f(void) { return 2; }\n' > x.c; "$cc" -c x.c -o x.o && command rm -f libx.a && ar rcs libx.a x.o; later libx.a
    run main.c -f libx.a >/dev/null 2>&1; [[ $? == 2 ]]
}
t_c_lib_flag() {
    local cc; cc=$(command -v clang || command -v gcc) || { echo "no cc"; return 0; }
    fresh clf; printf 'int f(void) { return 1; }\n' > x.c; "$cc" -c x.c -o x.o && ar rcs libx.a x.o
    printf 'int f(void);\nint main(void) { return f(); }\n' > main.c
    local out; out=$(run main.c -- -L. -lx 2>&1); [[ $out == *"main.c"*"-lx"* ]] || return 1   # libraries after the sources
    printf 'int f(void) { return 3; }\n' > x.c; "$cc" -c x.c -o x.o && command rm -f libx.a && ar rcs libx.a x.o; later libx.a
    run main.c -- -L. -lx >/dev/null 2>&1; [[ $? == 3 ]]
}
t_py_stdlib_name() { fresh psn; mkdir calendar; echo 'print("MINE")' > calendar/__main__.py; [[ $(run calendar 2>&1) == *MINE* ]]; }
t_py_nested_pkg() {
    fresh pnp; mkdir -p pkg/sub; touch pkg/__init__.py pkg/sub/__init__.py; echo 'X = "NESTED"' > pkg/util.py
    printf 'from ..util import X\nprint(X)\n' > pkg/sub/__main__.py
    [[ $(run pkg/sub 2>&1) == *NESTED* ]]
}
t_make_o_overrides_run() {
    fresh moo; progmk; printf '#include <stdio.h>\nint main(void) { puts("OTHER"); return 0; }\n' > o.c
    printf 'all: prog other\nprog: main.c\n\tcc -o prog main.c\nother: o.c\n\tcc -o other o.c\nrun: prog\n\t./prog\n' > Makefile
    local out; out=$(run -o other 2>&1); [[ $out == *OTHER* && $out != *RAN* ]]
}
t_make_refuses_flags() { fresh mrf3; progmk; printf 'prog: main.c\n\tcc -o prog main.c\n' > Makefile; fails_with "Makefile" run -- -DX; }
t_make_prog_comment() { fresh mpcm; progmk; printf 'PROG = app # the program\nall: $(PROG)\n$(PROG): main.c\n\tcc -o $(PROG) main.c\n' > Makefile; [[ $(run 2>&1) == *RAN* ]]; }
t_make_prog_var()     { fresh mpv; progmk; printf 'NAME = app\nPROG = $(NAME)\nall: $(PROG)\n$(PROG): main.c\n\tcc -o $(PROG) main.c\n' > Makefile; [[ $(run 2>&1) == *RAN* ]]; }
t_make_env_prog_ignored() { fresh mep; progmk; printf 'main: main.c\n\tcc -o main main.c\n' > Makefile; [[ $(PROG=zzz run 2>&1) == *RAN* ]]; }
t_make_shell_evals() {
    fresh mse; progmk; printf 'X := $(shell echo x >> calls.log)\nall: prog\nprog: main.c\n\tcc -o prog main.c\nrun: prog\n\t./prog\n' > Makefile
    run >/dev/null 2>&1; [[ $(wc -l < calls.log) -le 3 ]]
}
# The Ctrl-C trap is put back exactly as it was (in a background job bash starts
# with Ctrl-C ignored, which also shows in trap -p).
t_make_no_int_trap() {
    fresh mnt; printf 'all:\n\t@true\nrun:\n\t@echo hi\n' > Makefile; sq sq.c
    local before; before=$(trap -p INT)
    run >/dev/null 2>&1; [[ $(trap -p INT) == "$before" ]] || return 1
    cd .. && mkdir mnt2 && cd mnt2 && sq sq.c && echo 1 | run sq.c >/dev/null 2>&1; [[ $(trap -p INT) == "$before" ]]
}
t_rust_renamed_main() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rrm; cargo new -q --vcs none r2 && cd r2 && mkdir -p src/bin/x || return 1
    printf '\n[[bin]]\nname = "renamed"\npath = "src/main.rs"\n' >> Cargo.toml
    echo 'fn main() { println!("RENAMED"); }' > src/main.rs; echo 'fn main() { println!("XBIN"); }' > src/bin/x/main.rs
    printf '\n[[bin]]\nname = "x"\npath = "src/bin/x/main.rs"\n' >> Cargo.toml
    [[ $(run src/main.rs 2>&1) == *RENAMED* ]]
}
t_rust_workspace_hint() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rwh; printf '[workspace]\nmembers = ["a", "b"]\nresolver = "2"\n' > Cargo.toml
    cargo new -q --vcs none a && cargo new -q --vcs none b || return 1
    fails_with "a/src/main.rs" run
}
t_rust_example() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rex; cargo new -q --vcs none --lib mylib && cd mylib && mkdir examples || return 1
    echo 'pub fn f() -> i32 { 7 }' > src/lib.rs; echo 'fn main() { println!("EX{}", mylib::f()); }' > examples/ex.rs
    [[ $(run examples/ex.rs 2>&1) == *EX7* ]]
}
t_rust_lone_project_edition() {
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rlpe; cargo new -q --vcs none --edition 2024 e24 && cd e24 && mkdir tools || return 1
    echo 'fn main() { if let Some(x) = Some(1) && x > 0 { println!("LC{x}"); } }' > tools/t.rs   # let chains: 2024 only
    [[ $(run tools/t.rs 2>&1) == *LC1* ]]
}
t_mkmake_upper_cpp() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh muc; printf '#include <iostream>\nint main() { std::cout << "UPCPP\\n"; }\n' > Main.CPP
    mkmake >/dev/null 2>&1 && make -s >/dev/null 2>&1 && [[ $(./muc 2>&1) == *UPCPP* ]]
}
t_mkmake_folder_like_source() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh demo.c; sq main.c; mkmake >/dev/null 2>&1 && make -s >/dev/null 2>&1 || return 1
    [[ $(echo 2 | run 2>&1) == *"2 squared is 4"* ]]
}

check make_phony_run_norecipe  t_make_phony_run_norecipe
check make_run_prereq_only     t_make_run_prereq_only
check make_exit_program_text   t_make_exit_program_text
check c_static_lib             t_c_static_lib
check c_lib_flag               t_c_lib_flag
check py_stdlib_name           t_py_stdlib_name
check py_nested_pkg            t_py_nested_pkg
check make_o_overrides_run     t_make_o_overrides_run
check make_refuses_flags       t_make_refuses_flags
check make_prog_comment        t_make_prog_comment
check make_prog_var            t_make_prog_var
check make_env_prog_ignored    t_make_env_prog_ignored
check make_shell_evals         t_make_shell_evals
check make_no_int_trap         t_make_no_int_trap
if command -v cargo >/dev/null; then
    check rust_renamed_main          t_rust_renamed_main
    check rust_workspace_hint        t_rust_workspace_hint
    check rust_example               t_rust_example
    check rust_lone_project_edition  t_rust_lone_project_edition
fi
if command -v make >/dev/null; then
    check mkmake_upper_cpp           t_mkmake_upper_cpp
    check mkmake_folder_like_source  t_mkmake_folder_like_source
fi

# hostile aliases on every tool dev.sh uses: loaded with alias expansion on (the
# non-omarchy profiles), and used inside $(...) where aliases expand at run time.
t_alias_tools_safe() {
    fresh ats; sq sq.c; t1 a 3 "Give me a number: 3 squared is 9"
    mkdir mk && printf 'all:\n\t@true\nrun:\n\t@exit 3\n' > mk/Makefile
    local out
    out=$(timeout 120 bash -c '
        shopt -s expand_aliases
        alias find="echo FIND" mktemp="mktemp -d" stat="echo STAT" grep="grep --color=always -n" cut="cut -d x" \
              tail="tail -n 0" head="head -n 0" sort="sort -r" sed="echo SED" awk="echo AWK" make="echo MAKE" \
              env="echo ENV" cat="echo CAT" date="echo DATE" sha1sum="echo SHA" realpath="echo RP" pwd="echo PWD" diff="echo DIFF"
        . "$1"
        echo 2 | run >/dev/null 2>&1; echo "first=$?"
        out2=$(echo 2 | run 2>&1); [[ $out2 != *"[compile]"* ]] && echo SKIPPED
        rut >/dev/null 2>&1 && echo RUT_OK
        cd mk && run >/dev/null 2>&1; echo "make=$?"
    ' _ "$here/lib/dev.sh" 2>&1)
    [[ $out == *"first=0"* && $out == *SKIPPED* && $out == *RUT_OK* && $out == *"make=3"* ]] || { echo "$out"; return 1; }
}
check alias_tools_safe       t_alias_tools_safe

# ── hardening round 3 (2026-10-23): separate programs, link hints, parallel runs,
# live make output, the exit line after a partial line, temp files, small messages
t_two_mains() {
    fresh tm2; printf 'int main(void) { return 1; }\n' > a.c; printf 'int main(void) { return 2; }\n' > b.c
    local out; ! out=$(run 2>&1) && [[ $out == *"each have a main()"* && $(grep -c . <<<"$out") -le 2 ]]
}
t_undefined_hint() {
    fresh udh; printf 'int f(void);\nint main(void) { return f(); }\n' > main.c; printf 'int f(void) { return 0; }\n' > util.c
    local out; ! out=$(run main.c 2>&1) && [[ $out == *"build them together"* ]]
}
t_parallel_runs() {
    fresh par; printf '#include <unistd.h>\nint main(void) { usleep(200000); return 0; }\n' > r.c
    local i; for i in 1 2 3; do
        rm -f r; ( run r.c >"o1" 2>&1; echo "rc=$?" >>"o1" ) & ( run r.c >"o2" 2>&1; echo "rc=$?" >>"o2" ) & wait
        if ! grep -q "rc=0" o1 || ! grep -q "rc=0" o2; then cat o1 o2; return 1; fi
        ! grep -q "Text file busy" o1 o2 || { cat o1 o2; return 1; }
    done
}
t_make_run_live_stderr() {
    fresh mls; printf '#include <stdio.h>\n#include <unistd.h>\nint main(void) { fputs("PROMPT\\n", stderr); sleep(3); return 0; }\n' > main.c
    printf 'all: prog\nprog: main.c\n\tcc -o prog main.c\nrun: prog\n\t./prog\n' > Makefile; make -s >/dev/null 2>&1
    ( run > out.txt 2>&1 & ); sleep 1.5; grep -q PROMPT out.txt; local rc=$?; sleep 2; return $rc
}
t_exit_line_after_partial() {
    command -v script >/dev/null || { echo "no script"; return 0; }
    fresh elp; printf '#include <stdio.h>\nint main(void) { printf("answer: 42"); return 0; }\n' > nl.c
    local out; out=$(COLUMNS=40 script -qec "bash -c '. \"$here/lib/dev.sh\"; run nl.c'" /dev/null 2>&1)
    [[ $out =~ 42\ +$'\r' ]]
}
t_temp_files_in_cache() {
    fresh tfc; sq sq.c; t1 a 3 "Give me a number: 3 squared is 9"; mkdir "$T/tt"
    TMPDIR=$T/tt rut >/dev/null 2>&1; [[ -z $(ls -A "$T/tt") ]]
}
t_stale_temp_cleaned() {
    fresh stc; sq sq.c; t1 a 3 "Give me a number: 3 squared is 9"
    local d=$XDG_CACHE_HOME/bashrc-profile/tmp; mkdir -p "$d"; touch -d '2001-01-01' "$d/old.leftover"
    rut >/dev/null 2>&1; [[ ! -e $d/old.leftover ]]
}
t_refuses_script()  { fresh rsc; sq hello.c; printf '#!/bin/sh\necho mine\n' > hello; chmod +x hello; fails_with "isn't a program" ru hello.c && grep -q mine hello; }
t_py_missing()      { fresh pym; fails_with "'nosuch.py' not found" run nosuch.py; }
t_rut_hint_tests()  { fresh rht; sq sq.c; mkdir tests; t1 tests/a 3 x; fails_with "rut -d tests" rut sq.c; }

check two_mains              t_two_mains
check undefined_hint         t_undefined_hint
check parallel_runs          t_parallel_runs
if command -v make >/dev/null; then check make_run_live_stderr t_make_run_live_stderr; fi
check exit_line_after_partial t_exit_line_after_partial
check temp_files_in_cache    t_temp_files_in_cache
check stale_temp_cleaned     t_stale_temp_cleaned
check refuses_script         t_refuses_script
check py_missing             t_py_missing
check rut_hint_tests         t_rut_hint_tests

echo "$pass passed, $fail failed"
(( fail == 0 ))
