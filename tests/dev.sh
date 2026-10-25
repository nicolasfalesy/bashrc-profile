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
    [[ -x sq && $out == *-std=gnu17* && $out == *"$(_dev_san "$(_t_cc)")"* && $out == *-lm* ]]
}
# The C compiler the dev commands pick (clang first), and the sanitizer flag they probe for it.
_t_cc() { if command -v clang >/dev/null; then echo clang; else echo gcc; fi; }
# A compiler whose AddressSanitizer programs cannot run (the Pi's kernel): only -fsanitize=undefined is used.
t_san_fallback() {
    fresh sf; local real; real=$(command -v "$(_t_cc)")
    printf '#!/bin/sh\ncase "$*" in *address*) exit 1;; esac\nexec %s "$@"\n' "$real" > noasan-cc
    chmod +x noasan-cc
    [[ $(_dev_san "$PWD/noasan-cc" 2>/dev/null) == -fsanitize=undefined ]] && [[ $(_dev_san "$real") == -fsanitize=address* || $(uname -m) == aarch64 ]]
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
check san_fallback   t_san_fallback
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
    [[ $(_dev_san "$(_t_cc)" 2>/dev/null) == *address* ]] || { echo "no AddressSanitizer here (the Pi)"; return 0; }
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
    [[ $(make -n 2>&1) == *"-std=gnu17 -Wall -Wextra -g -O0 $(_dev_san "$(_t_cc)") main.c -o msb -lm"* ]]
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

# ── hardening round 2 (2026-10-23): gaps found by mutation testing (361 single-line bugs put into lib/dev.sh; 183 survived the suite)
# Each check below fails when the bug named in its comment is put into lib/dev.sh.
# inlib CMD...: run CMD in a fresh bash with the library loaded, killed after 20 s (a loop bug must fail the test, not hang it).
inlib() { timeout 20 bash -c '. "$0"; "$@"' "$here/lib/dev.sh" "$@"; }
# toolpath NAME GLOB...: a PATH folder holding all of /usr/bin except the programs matching GLOB (case patterns); echoes it.
toolpath() {
    local d=$T/tp-$1 f g skip; shift
    if [[ ! -d $d ]]; then
        mkdir -p "$d"
        for f in /usr/bin/*; do
            skip=""
            # shellcheck disable=SC2254  # $g is a glob on purpose
            for g in "$@"; do case ${f##*/} in $g) skip=1 ;; esac; done
            [[ -n $skip ]] || ln -s "$f" "$d/"
        done
    fi
    echo "$d"
}
# retc NAME CODE: a C program that prints ok and exits with CODE (a fake crash code: nothing really crashes).
retc() { printf '#include <stdio.h>\nint main(void) { puts("ok"); return %s; }\n' "$2" > "$1"; }

# ── detection, naming, listing
# lang_of: every extension spelling (.C, .CC, .C++ and .CXX are C++, .c is C), non-sources and plain folders
t_lang_of_exts() {
    local p f want
    for p in a.c=c a.C=cpp a.cc=cpp a.CC=cpp a.cpp=cpp a.CPP=cpp a.cxx=cpp a.CXX=cpp 'a.c++=cpp' 'a.C++=cpp' a.rs=rust a.py=python a.h= a.txt= a.cs= a.pyc= a=; do
        f=${p%%=*}; want=${p#*=}
        [[ $(_dev_lang_of "$f") == "$want" ]] || { echo "$f: got '$(_dev_lang_of "$f")', want '$want'"; return 1; }
    done
}
t_lang_of_folder() {
    fresh lof; mkdir plain pkg; touch pkg/__main__.py
    [[ -z $(_dev_lang_of plain) && $(_dev_lang_of pkg) == python ]] && fails_with "don't know how to build 'plain'" ru plain
}
# _dev_list: this folder only, files only, sorted; a folder called x.py and files in sub-folders are not sources
t_list_shallow_sorted() {
    fresh lss; local i; mkdir sub dir.py; touch sub/x.py sub/y.c
    for i in 5 3 9 1 7 2 8 4 6 10 12 11; do touch "$(printf 'f%02d.c' "$i")"; done
    [[ $(_dev_list | tr '\0' ' ') == "$(printf './f%02d.c ' {1..12})" ]] || { _dev_list | tr '\0' ' '; return 1; }
    [[ $(_dev_detect) == c ]]
}
# __main__.py and Cargo.toml together: Cargo wins; __main__.py and a .c file: the package wins, not "mixed"
t_detect_package_order() {
    fresh dpo; touch Cargo.toml __main__.py; [[ $(_dev_detect) == rust ]] || return 1
    fresh dpo2; touch __main__.py a.c; [[ $(_dev_detect) == python ]]
}
# a lone .o with -f means C
t_f_obj_only() {
    local cc; cc=$(command -v clang || command -v gcc) || { echo "no cc"; return 0; }
    fresh fob; printf 'int main(void) { return 7; }\n' > m.c; "$cc" -c m.c -o m.o; rm m.c
    run -f m.o >/dev/null 2>&1; [[ $? == 7 ]]
}
# the named file's language beats -f's: main.cpp -f b.c is C++
t_file_lang_beats_f() {
    fresh flb; printf 'int main() { return 0; }\n' > main.cpp; printf 'int g(void) { return 1; }\n' > b.c
    local out; out=$(ru main.cpp -f b.c 2>&1) && [[ $out == *"-std=gnu++20"* ]]
}
# a stray .rs next to C sources is not compiled by the C compiler
t_stray_rs_in_c_folder() { fresh srf; sq sq.c; echo 'fn main() {}' > notes.rs; ru >/dev/null 2>&1 && [[ -x sq ]]; }

# ── options
# -f stops at the next option
t_f_stops_at_option() {
    fresh fso; printf 'int f(void);\nint main(void) { return f(); }\n' > a.c; printf 'int f(void) { return 0; }\n' > b.c
    local out; out=$(ru -f a.c b.c -O 2 2>&1) && [[ $out == *-O2* ]]
}
# a missing value after -o, -i, -d is an error (-i with nothing used to be a candidate for an endless loop: inlib times out)
t_option_value_errors() {
    fresh ove; sq sq.c
    fails_with "-o requires" ru sq.c -o -O || return 1
    fails_with "-i requires" inlib run sq.c -i || return 1
    fails_with "-d requires" rut sq.c -d -v || return 1
    fails_with "-d requires" rut sq.c -d
}
t_glued_warn_list() { fresh gwl; printf 'int main(void) { int unused; return 0; }\n' > w.c; local out; ! out=$(ru w.c -Wall,error 2>&1) && [[ $out == *"-Wall -Werror"* ]]; }
# the -a note names each option, and appears once
t_args_note_each() {
    fresh ane; argsc a.c; local o out
    for o in -O -W -o -f -i -d -v; do
        out=$(run a.c -a 1 $o 2>&1)
        [[ $out == *"everything after -a goes to the program, including '$o'"* ]] || { echo "no note for $o"; return 1; }
    done
    out=$(run a.c -a -O -W 2>&1); [[ $(grep -c '^Note: everything' <<<"$out") == 1 ]]
}
# which command refuses which option, and its reason
t_refuse_messages() {
    fresh rfm; sq sq.c; echo 3 > in.txt; local p=$stub:$PATH
    local A="-a is for run, rud and rund" I="-i is for run and rund"
    PATH=$p fails_with "$A (ru only builds)" ru sq.c -a 5 || return 1
    PATH=$p fails_with "$I (ru only builds)" ru sq.c -i in.txt || return 1
    PATH=$p fails_with "-v is for rut" ru sq.c -v || return 1
    PATH=$p fails_with "-d is for rut" ru sq.c -d x || return 1
    PATH=$p fails_with "-v is for rut" run sq.c -v || return 1
    PATH=$p fails_with "-d is for rut" run sq.c -d x || return 1
    PATH=$p fails_with "$I (in rud, type the input in the debugger)" rud sq.c -i in.txt || return 1
    PATH=$p fails_with "-v is for rut" rud sq.c -v || return 1
    PATH=$p fails_with "-d is for rut" rud sq.c -d x || return 1
    PATH=$p fails_with "-v is for rut" rund sq.c -v || return 1
    PATH=$p fails_with "-d is for rut" rund sq.c -d x || return 1
    PATH=$p fails_with "$A (rut takes arguments from <stem>.args and input from <stem>.in)" rut sq.c -a 5 || return 1
    PATH=$p fails_with "$I (rut takes arguments from <stem>.args and input from <stem>.in)" rut sq.c -i in.txt
}
t_show_quoting() {
    [[ $(_dev_show plain 'a b' 'x;y') == 'plain a\ b x\;y' ]] || return 1
    [[ $(_dev_show ./a/b-c_d.e=f:g,h+i@j%k) == './a/b-c_d.e=f:g,h+i@j%k' ]]
}

# ── build skipping
# an in-place edit of the same size within the same second: only the nanoseconds differ
t_c_same_second_inplace() {
    fresh csp; printf 'int main(void) { return 1; }\n' > a.c; touch -d @1700000000.100000000 a.c
    run a.c >/dev/null 2>&1; [[ $? == 1 ]] || return 1
    printf 'int main(void) { return 2; }\n' | dd of=a.c conv=notrunc status=none; touch -d @1700000000.900000000 a.c
    run a.c >/dev/null 2>&1; [[ $? == 2 ]]
}
# another file of the same size and modification time moved into place: only the inode differs
t_c_swapped_same_stat() {
    fresh csw; printf 'int main(void) { return 1; }\n' > a.c; touch -d @1700000000.500000000 a.c
    run a.c >/dev/null 2>&1; [[ $? == 1 ]] || return 1
    printf 'int main(void) { return 2; }\n' > b.c; touch -r a.c b.c; mv b.c a.c
    run a.c >/dev/null 2>&1; [[ $? == 2 ]]
}
# header names make escapes: # and $ (cc -M prints a\#b.h and a$$b.h)
t_c_skip_special_header() {
    local n
    for n in 'a#b.h' 'a$b.h'; do
        fresh csx; echo '#define K 3' > "$n"; printf '#include "%s"\nint main(void) { return K; }\n' "$n" > s.c
        run s.c >/dev/null 2>&1; [[ $(run s.c 2>&1) != *'[compile]'* ]] || { echo "$n: not skipped"; return 1; }
        echo '#define K 4' > "$n"; later "$n"; run s.c >/dev/null 2>&1; [[ $? == 4 ]] || { echo "$n: edit not noticed"; return 1; }
    done
}
# a header whose name has glob characters is not expanded against the folder
t_c_header_with_glob_chars() {
    fresh chg; echo '#define K 3' > '[xy].h'; echo '/* unrelated */' > x.h; printf '#include "[xy].h"\nint main(void) { return K; }\n' > g.c
    run g.c >/dev/null 2>&1; echo '#define K 4' > '[xy].h'; later '[xy].h'; run g.c >/dev/null 2>&1; [[ $? == 4 ]]
}
# the stamp write survives set -C: after an edit, the next run is skipped again
t_noclobber_stamp_skips() {
    fresh nss; echo 'int main(void) { return 1; }' > a.c
    ( set -C; run a.c ) >/dev/null 2>&1; echo 'int main(void) { return 2; }' > a.c; later a.c
    ( set -C; run a.c ) >/dev/null 2>&1
    [[ $( set -C; run a.c 2>&1 ) != *'[compile]'* ]]
}
# two folders with a program of the same name keep separate stamps
t_stamps_per_folder() {
    fresh sp1; sq sq.c; ru sq.c >/dev/null 2>&1 || return 1
    fresh sp2; sq sq.c; ru sq.c >/dev/null 2>&1 || return 1
    cd "$T/w/sp1" && [[ $(ru sq.c 2>&1) != *'[compile]'* ]]
}

# ── C and C++ builds
t_o_folder_refused()  { fresh ofr; sq sq.c; mkdir out; fails_with "is a folder" ru sq.c -o out; }
# a named file and -f files: the program is named after the file, not the folder
t_file_plus_f_name() {
    fresh fpn; printf 'int f(void);\nint main(void) { return f(); }\n' > a.c; printf 'int f(void) { return 0; }\n' > b.c
    ru a.c -f b.c >/dev/null 2>&1 && [[ -x a && ! -e fpn ]]
}
# no compiler at all: the message names the package
t_no_compiler() {
    local d; d=$(toolpath nocc 'clang*' 'gcc*' 'g++*' cc c++ 'x86_64-*')
    fresh ncc; sq sq.c; PATH=$d fails_with "gcc not found" ru sq.c || return 1
    fresh ncp; printf 'int main() {}\n' > a.cpp; PATH=$d fails_with "g++ not found" ru a.cpp || return 1
    PATH=$d fails_with "g++ not found" mkmake || return 1
    fresh ncm; sq main.c; PATH=$d fails_with "gcc not found" mkmake
}

# ── Rust
t_rust_main_named_default_run() {   # run src/main.rs runs main even when default-run names another program
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rmd; rsproj p && cd p || return 1; sed -i 's/^\[package\]/[package]\ndefault-run = "zebra"/' Cargo.toml
    [[ $(run src/main.rs 2>&1) == *MAIN* ]]
}
t_rust_bin_folder() {   # src/bin/NAME/main.rs
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rbf; rsproj p && cd p || return 1; mkdir src/bin/zed; echo 'fn main() { println!("ZED"); }' > src/bin/zed/main.rs
    [[ $(run src/bin/zed/main.rs 2>&1) == *ZED* ]]
}
t_rust_single_other_bin() {   # the only program is not called like the package
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rso; rsproj p && cd p || return 1; rm src/main.rs
    [[ $(run 2>&1) == *ZEBRA* ]]
}
t_rust_named_not_built() {   # a file cargo does not build (a scratch .rs in the project) is built on its own with rustc
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rnn; rsproj p && cd p || return 1
    sed -i 's/^\[package\]/[package]\nautobins = false/' Cargo.toml; printf '\n[[bin]]\nname = "other"\npath = "src/main.rs"\n' >> Cargo.toml
    local out; out=$(run src/bin/zebra.rs 2>&1); [[ $out == *"rustc "*ZEBRA* && $out != *MAIN* ]]
}
t_rust_cargo_refusals() {   # -f and compiler flags don't apply to a Cargo project
    command -v cargo >/dev/null || { echo "no cargo"; return 0; }
    fresh rcr2; cargo new -q --vcs none p && cd p || return 1; touch a.rs
    fails_with "don't apply to Rust" ru -f a.rs || return 1
    fails_with "don't apply to Rust" ru -- -DX
}
t_rust_lone_refusals() {
    command -v rustc >/dev/null || { echo "no rustc"; return 0; }
    fresh rlr; echo 'fn main() {}' > a.rs
    fails_with "don't apply to Rust" ru -W all a.rs || return 1
    fails_with "don't apply to Rust" ru a.rs -- -DX || return 1
    fails_with "name the .rs file to build" ru -f a.rs
}
t_rust_lone_abs_o() {
    command -v rustc >/dev/null || { echo "no rustc"; return 0; }
    fresh rla; echo 'fn main() { println!("RS"); }' > a.rs; mkdir out
    [[ $(run a.rs -o "$PWD/out/p" 2>&1) == *RS* ]]
}

# ── Makefiles
# PROG named as `=` and `:=`, and the first target would clean/test/...: build PROG, never that target
t_make_prog_forms() {
    local op
    for op in = :=; do
        fresh mpf; sq main.c
        printf 'clean:\n\t@touch CLEANED\nPROG %s sq\nsq: main.c\n\tcc -o sq main.c\n' "$op" > Makefile
        [[ $(echo 5 | run 2>&1) == *"5 squared is 25"* && ! -e CLEANED ]] || { echo "PROG $op"; return 1; }
    done
}
t_make_dangerous_goals() {
    local g
    for g in clean test check debug install distclean; do
        fresh mdg; sq main.c
        printf '%s:\n\t@touch RAN\nPROG = sq\nsq: main.c\n\tcc -o sq main.c\n' "$g" > Makefile
        ru >/dev/null 2>&1; [[ -x sq && ! -e RAN ]] || { echo "first target $g"; return 1; }
    done
}
t_make_dangerous_no_prog() { fresh mdn; sq main.c; printf 'clean:\n\t@touch RAN\n' > Makefile; fails_with "building would run it" ru && [[ ! -e RAN ]]; }
# an all that depends on run: building does not run it (ru), run runs it once
t_make_all_needs_run() {
    fresh man; printf 'all: run\nrun:\n\t@echo ran >> log\n' > Makefile
    ru >/dev/null 2>&1; [[ ! -e log ]] || { echo "ru ran the run target"; return 1; }
    run >/dev/null 2>&1; [[ $(wc -l < log) == 1 ]]
}
# a prerequisite merely containing "run" in its name is not the run target
t_make_prereq_rerun() {
    fresh mpr; sq main.c; printf 'all: sq rerun\nsq: main.c\n\tcc -o sq main.c\nrerun:\n\t@true\n' > Makefile
    [[ $(echo 4 | run 2>&1) == *"4 squared is 16"* ]]
}
# rund builds PROG even when the first target is run (run's recipe would not be valgrinded)
t_rund_make_run_goal() {
    fresh rmg; sq main.c; printf 'run: sq\n\t./sq\nPROG := sq\nsq: main.c\n\tcc -o sq main.c\n' > Makefile
    [[ $(PATH=$stub:$PATH rund 2>&1) == *"VG -s --leak-check=full --track-origins=yes ./sq"* ]]
}
# make's own output goes to stderr (default build and PROG build)
t_make_build_output_stderr() {
    fresh mbo; sq main.c; printf 'all: sq\nsq: main.c\n\t@echo BUILDMSG\n\tcc -o sq main.c\n' > Makefile
    local out; out=$(echo 3 | run 2>/dev/null); [[ $out == *"3 squared is 9"* && $out != *BUILDMSG* && $out != *"cc -o"* ]] || { echo "default: $out"; return 1; }
    fresh mbo2; sq main.c; printf 'clean:\n\t@true\nPROG = sq\nsq: main.c\n\t@echo BUILDMSG\n\tcc -o sq main.c\n' > Makefile
    out=$(echo 3 | run 2>/dev/null); [[ $out == *"3 squared is 9"* && $out != *BUILDMSG* && $out != *"cc -o"* ]] || { echo "PROG: $out"; return 1; }
}
t_make_run_double_colon() {
    fresh mdc2; printf 'all:\n\t@true\nrun::\n\t@echo DOUBLE\n' > Makefile; [[ $(run 2>&1) == *DOUBLE* ]] || return 1
    fresh mdc3; printf 'all:\n\t@true\nrun:: dep\n\t@echo DOUBLE2\ndep:\n\t@true\n' > Makefile; [[ $(run 2>&1) == *DOUBLE2* ]]
}
# an existing FILE called run that the Makefile only names as a prerequisite is not a run target
t_make_run_file_prereq() {
    fresh mrp; printf 'all: run\n' > Makefile; printf '#!/bin/sh\necho NOT-THIS\n' > run; chmod +x run
    local out; ! out=$(run 2>&1) && [[ $out != *NOT-THIS* && $out == *"building would run it"* ]]
}
# the program is a prerequisite of the default target (all: sq)
t_make_prereq_program() {
    fresh mpp; sq main.c; printf 'all: sq\nsq: main.c\n\tcc -o sq main.c\n' > Makefile
    [[ $(echo 5 | run 2>&1) == *"5 squared is 25"* ]]
}
t_make_prereq_plain_file() {   # a plain file among the prerequisites is not a program
    fresh mpf2; sq main.c; printf 'all: sq main.c\nsq: main.c\n\tcc -o sq main.c\n' > Makefile
    [[ $(echo 5 | run 2>&1) == *"5 squared is 25"* ]]
}
t_make_two_programs() {   # two programs: ask; -o picks one; a missing -o program is an error
    fresh mtp; sq main.c; printf 'all: sq sq2\nsq: main.c\n\tcc -o sq main.c\nsq2: sq\n\tcp sq sq2\n' > Makefile
    fails_with "can't tell which program" run || return 1
    [[ $(echo 5 | run -o sq 2>&1) == *"5 squared is 25"* ]] || return 1
    fails_with "make didn't build ./ghost" run -o ghost || return 1
    [[ $(echo 6 | run -o "$PWD/sq" 2>&1) == *"6 squared is 36"* ]]   # an absolute -o
}
t_make_goal_not_program() {   # the default target is a data file, not a program
    fresh mgn; sq main.c; printf 'data.txt: main.c\n\tcp main.c data.txt\n' > Makefile
    fails_with "can't tell which program" run
}
t_make_signal_names() {
    fresh mig; ulimit -c 0; local sh=$T/omarchy-crash-sh pair sig want rc shell
    [[ -x $sh ]] || cp /usr/bin/bash "$sh"   # a renamed bash: a core from it is named omarchy-crash-*
    # A suite started in the background has SIGINT ignored, and a shell cannot undo that: for INT, perl resets it, then runs the same bash.
    printf '#!/usr/bin/perl\n$SIG{INT} = "DEFAULT";\nexec q(%s), @ARGV;\n' "$sh" > "$T/omarchy-crash-intsh"; chmod +x "$T/omarchy-crash-intsh"
    for pair in ABRT:134 SEGV:139 BUS:135 FPE:136 ILL:132 KILL:137 TERM:143 INT:130; do
        sig=${pair%:*}; want=${pair#*:}; shell=$sh
        if [[ $sig == INT ]]; then command -v perl >/dev/null || continue; shell=$T/omarchy-crash-intsh; fi
        printf 'SHELL = %s\nall:\n\t@true\nrun:\n\t@kill -%s $$$$\n' "$shell" "$sig" > Makefile
        run >/dev/null 2>&1; rc=$?
        [[ $rc == "$want" ]] || { echo "$sig: exit $rc, want $want"; return 1; }
    done
}
t_make_first_target_prefix() {   # targets whose names start with the default target's (make prints rules in hash order, so use several) do not replace its prerequisites
    fresh mfp; sq main.c; printf 'all: sq\nall-a: main.c\nall-b: main.c\nall-c: main.c\nall-d: main.c\nall-e: main.c\nall-f: main.c\nsq: main.c\n\tcc -o sq main.c\n' > Makefile
    [[ $(echo 5 | run 2>&1) == *"5 squared is 25"* ]]
}

# ── Python
t_py_venv_plain_name() { fresh pvn; sqpy a.py; mkdir -p venv/bin; printf '#!/bin/sh\necho VENV "$@"\n' > venv/bin/python; chmod +x venv/bin/python; [[ $(run a.py 2>&1) == *"VENV a.py"* ]]; }
t_py_venv_no_python() {   # a .venv/bin without python: say so, use python3
    fresh pvx; echo 'print("RAN")' > a.py; mkdir -p .venv/bin
    local out; out=$(run a.py 2>&1); [[ $out == *RAN* && $out == *".venv/bin/python is broken or missing"* ]]
}
t_py_venv_not_executable() {
    fresh pvq; echo 'print("RAN")' > a.py; mkdir -p .venv/bin; printf '#!/bin/sh\necho VENV\n' > .venv/bin/python
    local out; out=$(run a.py 2>&1); [[ $out == *RAN* && $out != *VENV* && $out == *"broken or missing"* ]]
}
t_py_no_python3() {
    local d; d=$(toolpath nopy 'python*'); fresh pnp; echo 'print(1)' > a.py
    PATH=$d fails_with "python3 not found" run a.py
}
t_py_package_pythonpath() {   # the caller's PYTHONPATH stays
    fresh ppp; mkdir pkg lib; echo 'X = "LIBOK"' > lib/helper.py; printf 'import helper\nprint(helper.X)\n' > pkg/__main__.py
    [[ $(PYTHONPATH=$PWD/lib run pkg 2>&1) == *LIBOK* ]]
}
t_py_package_odd_name() {   # my.pkg and "my pkg" are no module names: run the folder's __main__.py itself; pkg/ with a slash works
    fresh ppo; mkdir my.pkg pkg "my pkg"; echo 'print("DOTTED")' > my.pkg/__main__.py; echo 'print("SLASHED")' > pkg/__main__.py; echo 'print("SPACED")' > "my pkg/__main__.py"; echo 'print("OTHER")' > "my pkg/other.py"
    [[ $(run my.pkg 2>&1) == *DOTTED* && $(run pkg/ 2>&1) == *SLASHED* ]] || return 1
    cd "my pkg" && [[ $(run 2>&1) == *SPACED* ]]
}
t_py_ignores_other_files() { fresh pio; echo 'print("ONLY")' > a.py; echo x > notes.txt; [[ $(run 2>&1) == *ONLY* ]]; }
t_rud_py_package_env() {   # rud passes PYTHONPATH to the debugger
    fresh rpe; mkdir pkg; echo 'print(1)' > pkg/__main__.py; unset PYTHONPATH
    # The stand-in answers the module lookup (python3 -c CODE NAME) with this folder, as a real python would.
    local d=$T/stubpp; mkdir -p "$d"
    printf '#!/bin/sh\n[ "$1" = -c ] && { echo "$(pwd -P)/$3"; exit 0; }\necho "PP=$PYTHONPATH $*"\n' > "$d/python3"; chmod +x "$d/python3"
    [[ $(PATH=$d:$PATH rud pkg 2>&1) == *"PP=$PWD -m pdb -m pkg"* ]]
}
t_rut_py_package() {   # rut passes PYTHONPATH to the program (run from inside the package, where the parent folder is not on the path)
    fresh rpp; mkdir pkg; touch pkg/__init__.py; echo 'X = "PKG"' > pkg/util.py; printf 'from .util import X\nprint(X)\n' > pkg/__main__.py
    cd pkg && t1 a "" PKG && rut 2>&1 | grep -q "All tests passed"
}

# ── run, rud, rund
t_exit_line_decimal_comma() {   # a locale writing 12,5: both the start and the end
    local out EPOCHREALTIME=1700000002,50
    out=$(_dev_exit_line 0 1700000000,25 2>&1); [[ $out == *"exit 0, 2.25 s"* ]]
}
t_run_missing_input() { fresh rmi2; sq sq.c; fails_with "input file 'nope.txt' not found" run sq.c -i nope.txt; }
t_rud_no_debugger() {
    local d; d=$(toolpath nodbg 'lldb*' 'gdb*'); fresh rnd; sq sq.c
    PATH=$d fails_with "gdb not found" rud sq.c
}
t_rund_no_valgrind() {
    local d; d=$(toolpath novg 'valgrind*'); fresh rnv; sq sq.c
    PATH=$d fails_with "valgrind not found" rund sq.c
}
t_rund_ignores_O() { fresh rio; sq sq.c; local out; out=$(PATH=$stub:$PATH rund sq.c -O 2 2>&1); [[ $out == *" -O0 "* && $out != *" -O2 "* ]]; }
t_rund_survives_set_e() {   # valgrind exiting 1 must still end in the report, under set -e
    fresh rse2; sq sq.c; local d out
    d=$(vgstub e1 'echo "==1== ERROR SUMMARY: 3 errors from 1 contexts (suppressed: 0 from 0)" >&2; exit 1')
    out=$(bash -c 'set -e; . "$1"; PATH="$2:$PATH"; rund sq.c' _ "$here/lib/dev.sh" "$d" 2>&1)
    [[ $out == *"RESULT: FAIL"* ]]
}
t_rund_interrupted_forms() {   # Ctrl-C is told by the exit status alone, or by valgrind's own line alone
    fresh rif2; sq sq.c; local d out
    d=$(vgstub i1 'echo "==1== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)" >&2; exit 130')
    if out=$(PATH=$d:$PATH rund sq.c 2>&1) || [[ $out != *interrupted* ]]; then echo "status only: $out"; return 1; fi
    d=$(vgstub i2 'echo "==1== Process terminating with default action of signal 2 (SIGINT)" >&2; echo "==1== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)" >&2')
    ! out=$(PATH=$d:$PATH rund sq.c 2>&1) && [[ $out == *interrupted* ]]
}
t_rund_leak_kinds() {
    fresh rlk; sq sq.c; local d out k
    for k in indirectly possibly; do
        d=$(vgstub "lk$k" "echo '==1==    $k lost: 8 bytes in 1 blocks' >&2; echo '==1== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)' >&2")
        if out=$(PATH=$d:$PATH rund sq.c 2>&1) || [[ $out != *LEAKS* ]]; then echo "$k lost: $out"; return 1; fi
    done
}
t_rund_cleans_up() {   # no temp file left, no RETURN trap left, the log saved
    fresh rcu; sq sq.c; mkdir tl xc
    XDG_CACHE_HOME=$PWD/xc TMPDIR=$PWD/tl PATH=$stub:$PATH rund sq.c >/dev/null 2>&1
    [[ -z $(find tl xc/bashrc-profile/tmp -mindepth 1 2>/dev/null) ]] || { echo "temp left: $(ls -R tl xc)"; return 1; }
    [[ -z $(trap -p RETURN) ]] || { echo "trap left"; return 1; }
    compgen -G 'valgrind_*.log' >/dev/null
}

# ── rut and _run_suite
# exit codes that mean "killed by a signal" fail the case, as programs; nothing really crashes (the program just exits with that code)
t_rut_signal_codes() {
    fresh rsc; local n out
    for n in 131 132 134 135 136 137 139; do
        retc e.c "$n"; t1 a "" ok
        if out=$(rut e.c 2>&1) || [[ $out != *"crashed, signal $((n - 128))"* ]]; then echo "$n: $out"; return 1; fi
    done
    for n in 1 130 255; do
        retc e.c "$n"
        if ! out=$(rut e.c 2>&1) || [[ $out != *"All tests passed"* ]]; then echo "$n: $out"; return 1; fi
    done
}
t_rut_failure_details() {
    fresh rfd; sq sq.c; t1 a 3 wrong
    local out; ! out=$(rut sq.c 2>&1) && [[ $out == *"Args:"*"(none)"*"Input:"*"Expected:"*"Actual:"* && $out != *"No such file"* ]]
}
t_rut_set_e_summary() {   # failing and crashing cases still end in the summary under set -e
    fresh rsm; sq sq.c; t1 a 3 wrong
    local out; out=$(bash -c 'set -e; . "$1"; rut sq.c' _ "$here/lib/dev.sh" 2>&1); [[ $out == *"Some tests failed:"*"1/1"* ]] || { echo "fail: $out"; return 1; }
    fresh rsm2; retc e.c 139; t1 a "" ok
    out=$(bash -c 'set -e; . "$1"; rut e.c' _ "$here/lib/dev.sh" 2>&1); [[ $out == *"Some tests failed:"*"1/1"* ]]
}
t_rut_cleans_up() {   # temp files live in the cache's tmp folder (round 3); none left there or in TMPDIR
    fresh rcl; sq sq.c; t1 a 3 "Give me a number: 3 squared is 9"; mkdir tl xc
    XDG_CACHE_HOME=$PWD/xc TMPDIR=$PWD/tl rut sq.c >/dev/null 2>&1
    [[ -z $(find tl xc/bashrc-profile/tmp -mindepth 1 2>/dev/null) ]]
}
# _run_suite itself: a suite file without a final newline, blank lines, a missing program, one argument, a case without .in under set -C
t_suite_direct() {
    fresh sud; printf '#!/bin/sh\necho hi\n' > p; chmod +x p; echo hi > a.expect
    printf 'a' > s1; [[ $(_run_suite s1 ./p 2>&1) == *"All tests passed"*"1/1"* ]] || { echo "no final newline"; return 1; }
    printf '\na\n\n' > s2; [[ $(_run_suite s2 ./p 2>&1) == *"All tests passed"*"1/1"* ]] || { echo "blank lines"; return 1; }
    fails_with "not found or not executable" _run_suite s1 ./nope || return 1
    fails_with "_run_suite expects" _run_suite s1 || return 1
    [[ $( set -C; _run_suite s1 ./p 2>&1 ) == *"All tests passed"* ]]
}

# ── mkt
t_mkt_more() {
    fresh mkm
    [[ $(mkt a b) == *"--- 2 test stems created ---"* && $(mkt solo) != *"---"* ]] || return 1
    mkt -a x y >/dev/null; [[ -e x.args && -e y.args ]] || return 1
    fails_with "provide at least one" mkt || return 1
    fails_with "provide at least one" mkt -a || return 1
    mkt -dash >/dev/null && [[ -e ./-dash.in ]] || return 1
    mkt -a -dash2 >/dev/null && [[ -e ./-dash2.args ]]
}
t_mkt_args_readonly() { fresh mra; chmod 555 .; local out; out=$(mkt -a t 2>&1); local rc=$?; chmod 755 .; [[ $rc != 0 && $out == *"couldn't create the files for 't'"* ]]; }

# ── mkmake
t_mkmake_names() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    local n
    fresh ".hid"; sq main.c; mkmake >/dev/null 2>&1; grep -q '^PROG    = hid$' Makefile || { echo "leading dot"; return 1; }
    fresh "..."; sq main.c; mkmake >/dev/null 2>&1; grep -q '^PROG    = program$' Makefile || { echo "only dots"; return 1; }
    for n in all run debug test clean; do
        fresh "$n"; sq main.c; mkmake >/dev/null 2>&1; grep -q "^PROG    = $n-prog\$" Makefile || { echo "folder $n"; return 1; }
    done
}
t_mkmake_bad_chars() {
    local c
    for c in '#' '$' ':' '%' "\\"; do
        fresh mbc; sq "x${c}y.c"; fails_with "rename" mkmake || { echo "char $c"; return 1; }
    done
    fresh mbc2; sq main.c; echo notes > 'my notes.txt'; mkmake >/dev/null 2>&1   # a bad name on a non-source is fine
}
t_mkmake_cpp_exts() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    local e
    for e in cpp cc cxx C CPP Cpp CC CXX c++ C++; do   # every spelling _dev_lang_of calls C++
        fresh "mce$e"; printf 'int main() { return 0; }\n' > "a.$e"; mkmake >/dev/null 2>&1 || return 1
        [[ $(make -n 2>&1) == *"a.$e"* ]] || { echo "a.$e not in the build"; return 1; }
    done
}
t_mkmake_hpp_dep() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh mhd; echo '#define K 3' > k.hpp; printf '#include "k.hpp"\nint main() { return K; }\n' > main.cpp
    mkmake >/dev/null 2>&1 && make -s >/dev/null 2>&1 || return 1
    later k.hpp; [[ $(make -n 2>&1) == *"-o mhd"* ]]
}
t_mkmake_test_crash_codes() {   # fake crash codes (the program exits with them; nothing crashes)
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh mtc; local n
    for n in 131 132 134 135 136 137 139; do
        retc main.c "$n"; rm -f Makefile mtc; mkmake >/dev/null 2>&1 && t1 a "" ok
        ! make -s test >/dev/null 2>&1 || { echo "$n passed"; return 1; }
    done
    for n in 1 130 255; do
        retc main.c "$n"; rm -f Makefile mtc; mkmake >/dev/null 2>&1 && t1 a "" ok
        make -s test >/dev/null 2>&1 || { echo "$n failed"; return 1; }
    done
}
t_mkmake_test_details() {
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh mtd; argse main.c; mkmake >/dev/null 2>&1 || return 1
    local out; if out=$(make -s test 2>&1) || [[ $out != *"no .in files here"* ]]; then echo "$out"; return 1; fi
    touch x1 x2; echo '*' > a.args; t1 a "" "[*]"; make -s test >/dev/null 2>&1   # an argument * stays *
}
t_mkmake_phony_clean_file() { command -v make >/dev/null || { echo "no make"; return 0; }; fresh mpf3; sq main.c; mkmake >/dev/null 2>&1 && make -s >/dev/null 2>&1 && touch clean && make -s clean >/dev/null 2>&1 && [[ ! -e mpf3 ]]; }
t_mkmake_run_builds() { command -v make >/dev/null || { echo "no make"; return 0; }; fresh mrb; sq main.c; mkmake >/dev/null 2>&1; [[ $(echo 3 | make -s run 2>&1) == *"3 squared is 9"* ]]; }
t_mkmake_compiler_var() {   # CC / CXX are the Makefile's compiler variables
    command -v make >/dev/null || { echo "no make"; return 0; }
    fresh mcv; sq main.c; mkmake >/dev/null 2>&1; ! make -s CC=false >/dev/null 2>&1 || return 1
    fresh mcv2; printf 'int main() { return 0; }\n' > a.cpp; mkmake >/dev/null 2>&1; ! make -s CXX=false >/dev/null 2>&1
}
t_lazy_all() { local c; for c in ru run rud rund rut mkt mkmake; do grep -q "^_bashrc_lazy dev .*\\b$c\\b" "$here/bashrc" || { echo "$c missing from the lazy line"; return 1; }; done; }

check lang_of_exts           t_lang_of_exts
check lang_of_folder         t_lang_of_folder
check list_shallow_sorted    t_list_shallow_sorted
check detect_package_order   t_detect_package_order
check f_obj_only             t_f_obj_only
check file_lang_beats_f      t_file_lang_beats_f
check stray_rs_in_c_folder   t_stray_rs_in_c_folder
check f_stops_at_option      t_f_stops_at_option
check option_value_errors    t_option_value_errors
check glued_warn_list        t_glued_warn_list
check args_note_each         t_args_note_each
check refuse_messages        t_refuse_messages
check show_quoting           t_show_quoting
check c_same_second_inplace  t_c_same_second_inplace
check c_swapped_same_stat    t_c_swapped_same_stat
check c_skip_special_header  t_c_skip_special_header
check c_header_with_glob_chars t_c_header_with_glob_chars
check noclobber_stamp_skips  t_noclobber_stamp_skips
check stamps_per_folder      t_stamps_per_folder
check o_folder_refused       t_o_folder_refused
check file_plus_f_name       t_file_plus_f_name
check no_compiler            t_no_compiler
if command -v cargo >/dev/null; then
    check rust_main_named_default_run t_rust_main_named_default_run
    check rust_bin_folder         t_rust_bin_folder
    check rust_single_other_bin   t_rust_single_other_bin
    check rust_named_not_built    t_rust_named_not_built
    check rust_cargo_refusals     t_rust_cargo_refusals
fi
if command -v rustc >/dev/null; then
    check rust_lone_refusals      t_rust_lone_refusals
    check rust_lone_abs_o         t_rust_lone_abs_o
fi
if command -v make >/dev/null; then
    check make_prog_forms         t_make_prog_forms
    check make_dangerous_goals    t_make_dangerous_goals
    check make_dangerous_no_prog  t_make_dangerous_no_prog
    check make_all_needs_run      t_make_all_needs_run
    check make_prereq_rerun       t_make_prereq_rerun
    check rund_make_run_goal      t_rund_make_run_goal
    check make_build_output_stderr t_make_build_output_stderr
    check make_run_double_colon   t_make_run_double_colon
    check make_run_file_prereq    t_make_run_file_prereq
    check make_prereq_program     t_make_prereq_program
    check make_prereq_plain_file  t_make_prereq_plain_file
    check make_two_programs       t_make_two_programs
    check make_goal_not_program   t_make_goal_not_program
    check make_signal_names       t_make_signal_names
    check make_first_target_prefix t_make_first_target_prefix
    check mkmake_names            t_mkmake_names
    check mkmake_cpp_exts         t_mkmake_cpp_exts
    check mkmake_hpp_dep          t_mkmake_hpp_dep
    check mkmake_test_crash_codes t_mkmake_test_crash_codes
    check mkmake_test_details     t_mkmake_test_details
    check mkmake_phony_clean_file t_mkmake_phony_clean_file
    check mkmake_run_builds       t_mkmake_run_builds
    check mkmake_compiler_var     t_mkmake_compiler_var
fi
check mkmake_bad_chars       t_mkmake_bad_chars
check py_venv_plain_name     t_py_venv_plain_name
check py_venv_no_python      t_py_venv_no_python
check py_venv_not_executable t_py_venv_not_executable
check py_no_python3          t_py_no_python3
check py_package_pythonpath  t_py_package_pythonpath
check py_package_odd_name    t_py_package_odd_name
check py_ignores_other_files t_py_ignores_other_files
check rud_py_package_env     t_rud_py_package_env
check rut_py_package         t_rut_py_package
check exit_line_decimal_comma t_exit_line_decimal_comma
check run_missing_input      t_run_missing_input
check rud_no_debugger        t_rud_no_debugger
check rund_no_valgrind       t_rund_no_valgrind
check rund_ignores_O         t_rund_ignores_O
check rund_survives_set_e    t_rund_survives_set_e
check rund_interrupted_forms t_rund_interrupted_forms
check rund_leak_kinds        t_rund_leak_kinds
check rund_cleans_up         t_rund_cleans_up
check rut_signal_codes       t_rut_signal_codes
check rut_failure_details    t_rut_failure_details
check rut_set_e_summary      t_rut_set_e_summary
check rut_cleans_up          t_rut_cleans_up
check suite_direct           t_suite_direct
check mkt_more               t_mkt_more
check mkt_args_readonly      t_mkt_args_readonly
check lazy_all               t_lazy_all

# ── hardening round 4 (2026-10-23): the confirming review of round 3
t_two_mains_ifdef() {   # a main() hidden behind #ifdef links fine: neither plain run nor -f may refuse it
    fresh tmi; printf 'int helper(void) { return 3; }\n#ifdef STANDALONE\nint main(void) { return helper(); }\n#endif\n' > lib.c
    printf 'int helper(void);\nint main(void) { return helper(); }\n' > app.c
    run >/dev/null 2>&1; [[ $? == 3 ]] || { echo "plain run"; return 1; }
    run app.c -f lib.c >/dev/null 2>&1; [[ $? == 3 ]] || { echo "run -f"; return 1; }
    local out; out=$(ru app.c -f app.c 2>&1); [[ $out != *"app.c and app.c"* ]]
}
t_cc_errors_readonly_cache() {   # an unwritable cache must not swallow the compiler's messages
    fresh cro; printf 'int main(void) { return nosuch; }\n' > e.c; mkdir ro; chmod 555 ro
    local out; out=$(XDG_CACHE_HOME=$PWD/ro/c run e.c 2>&1); chmod 755 ro; [[ $out == *nosuch* ]]
}
t_make_run_ignored_failure() {   # a failing - line before the program (top level and one make down)
    fresh mri; printf 'int main(void) { return 7; }\n' > main.c
    printf 'all: prog\nprog: main.c\n\tcc -o prog main.c\nrun: prog\n\t-@false\n\t./prog\n' > Makefile
    run >/dev/null 2>&1; [[ $? == 7 ]] || { echo "top"; return 1; }
    printf 'all: prog\nprog: main.c\n\tcc -o prog main.c\nrun: prog\n\t-@false\n\t@$(MAKE) -s inner\ninner:\n\t-@false\n\t./prog\n' > Makefile
    run >/dev/null 2>&1; [[ $? == 7 ]] || { echo "nested"; return 1; }
}
t_make_shell_flags() {   # SHELL with flags, and SHELL built from another variable
    fresh msf; printf 'SHELL := /bin/bash -o pipefail\nall:\n\t@true\nrun:\n\t@false | true\n' > Makefile
    run >/dev/null 2>&1; [[ $? == 1 ]] || { echo "flags"; return 1; }
    printf 'BASHX := $(shell command -v bash)\nSHELL = $(BASHX) -o pipefail\nall:\n\t@true\nrun:\n\t@false | true\n' > Makefile
    run >/dev/null 2>&1; [[ $? == 1 ]] || { echo "variable"; return 1; }
}
t_make_run_parallel() {   # many make runs at once share the stand-in shell
    fresh mrpl; printf 'all:\n\t@true\nrun:\n\t@exit 4\n' > Makefile
    local i
    for i in {1..12}; do ( for _ in {1..15}; do run >/dev/null 2>&1; echo $? >> "rc$i"; done ) & done; wait
    if cat rc* | grep -qvx 4; then sort rc* | uniq -c; return 1; fi
}
t_make_cache_space() {   # a cache path with a space: the program still runs
    fresh mcs; printf 'all:\n\t@true\nrun:\n\t@echo MARK\n' > Makefile
    local out; out=$(XDG_CACHE_HOME="$PWD/sp dir" run 2>&1); [[ $out == *MARK* ]]
}
t_tmp_keeps_recent() {   # an hour-old temp file may belong to a live run (rund waiting for input): only day-old ones go
    local d=$XDG_CACHE_HOME/bashrc-profile/tmp; mkdir -p "$d"; touch -d '2 hours ago' "$d/live"; touch -d '3 days ago' "$d/dead"
    command rm -f -- "$(_dev_tmp)"; [[ -e $d/live && ! -e $d/dead ]]
}
t_exit_line_narrow() {   # no COLUMNS and no TERM in a 12-column terminal: the padding fits the real width
    command -v script >/dev/null || { echo "no script"; return 0; }
    local out; out=$(env -u COLUMNS -u TERM script -qec "stty cols 12; bash -c '. \"$here/lib/dev.sh\"; _dev_exit_line 0 \$EPOCHREALTIME'" /dev/null 2>&1)
    if ! [[ $out =~ (\ +)$'\r' ]] || (( ${#BASH_REMATCH[1]} > 11 )); then echo "padding ${#BASH_REMATCH[1]}"; return 1; fi
}

check two_mains_ifdef        t_two_mains_ifdef
check cc_errors_readonly_cache t_cc_errors_readonly_cache
check tmp_keeps_recent       t_tmp_keeps_recent
check exit_line_narrow       t_exit_line_narrow
if command -v make >/dev/null; then
    check make_run_ignored_failure t_make_run_ignored_failure
    check make_shell_flags       t_make_shell_flags
    check make_run_parallel      t_make_run_parallel
    check make_cache_space       t_make_cache_space
fi

# ── crash line (2026-10-23): a crash under make run names the program, not the stand-in shell
t_make_crash_line() {   # a bash recipe shell: the line names the recipe (on any system: the stand-in itself is bash)
    fresh omarchy-crash-ml; ulimit -c 0
    printf 'int main(void) { *(volatile int *)0 = 1; return 0; }\n' > main.c
    printf 'SHELL := /bin/bash\nomarchy-crash-ml: main.c\n\tcc -o omarchy-crash-ml main.c\nrun: omarchy-crash-ml\n\t./omarchy-crash-ml 5\n' > Makefile
    local out rc; out=$(run 2>&1); rc=$?
    [[ $rc == 139 && $out == *"./omarchy-crash-ml 5: Segmentation fault"* && $out != *make-shell* ]] || { echo "bash: rc $rc: $out"; return 1; }
    # The default shell: dash (Ubuntu's sh) reports the crash itself, as plain make shows it; the stand-in is never named.
    sed -i 1d Makefile; out=$(run 2>&1); rc=$?
    [[ $rc == 139 && $out == *"Segmentation fault"* && $out != *make-shell* ]] || { echo "sh: rc $rc: $out"; return 1; }
}
t_make_shell_error_shown() {   # what the stand-in's own shell says that isn't a crash still reaches you
    fresh mse; printf 'SHELL := /nonexistent/sh\nall:\n\t@true\nrun:\n\t@true\n' > Makefile
    local out; if out=$(run 2>&1) || [[ $out != */nonexistent/sh* ]]; then echo "$out"; return 1; fi
}
if command -v make >/dev/null; then
    check make_crash_line        t_make_crash_line
    check make_shell_error_shown t_make_shell_error_shown
fi

echo "$pass passed, $fail failed"
(( fail == 0 ))
