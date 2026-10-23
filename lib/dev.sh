#!/usr/bin/env bash
# lib/dev.sh — build, run, debug and test programs in C, C++, Rust, Python or a
# Makefile folder (lazy-loaded on first use). VS Code's Run button calls `run`.
#   ru      build (clang C17 / C++20 with sanitizers; cargo; make)
#   run     build when needed, then run; prints the exit code and time
#   rud     debug build, then lldb (gdb without lldb; pdb for Python)
#   rund    build without sanitizers, then valgrind with a colourised report
#   rut     build, then run the .in/.expect/.args test cases
#   mkt     create empty test case files
#   mkmake  write a Makefile for the C or C++ files here
# Dependencies: clang or gcc, make; optional cargo, python3, lldb or gdb, valgrind
#   (install.sh --with-dev installs gcc, make, gdb, valgrind and clang; the rest by hand)
#
# Each test case is <stem>.in (stdin; cases are found by their .in) and
# <stem>.expect (expected stdout and stderr together); <stem>.args is optional.
#
# Quirks:
#   • This file is never sourced at startup: bashrc installs stubs for the seven
#     public functions and the first call (or Tab) sources it — see
#     _bashrc_lazy in lib/core.sh. Adding a new public function here means adding
#     it to that `_bashrc_lazy dev …` line too, or it will not exist until
#     something else triggers the load.
#   • `run` is also the name of a helper inside install.sh; they never meet
#     (install.sh is executed, not sourced), but don't source install.sh.
#   • Colour codes are locals per function, not globals — keeps `set | grep`
#     and the environment clean.

# ── Languages ────────────────────────────────────────────────────────────────
# The private _dev_* helpers below let every command work on C, C++, Rust,
# Python and Makefile folders the same way VS Code's Run button does (it calls
# `run`). Spec: docs/superpowers/specs/2026-10-22-multi-language-run-design.md.

# _dev_lang_of FILE: the language of one source file by its extension, or nothing.
_dev_lang_of() {
    case "$1" in
        *.c)               echo c ;;
        *.cpp|*.cc|*.cxx)  echo cpp ;;
        *.rs)              echo rust ;;
        *.py)              echo python ;;
    esac
}

# _dev_cargo_root: the nearest folder at or above the current one with a
# Cargo.toml; status 1 when there is none.
_dev_cargo_root() {
    local d=$PWD
    while :; do
        [[ -f $d/Cargo.toml ]] && { echo "$d"; return 0; }
        [[ $d == / || -z $d ]] && return 1
        d=${d%/*}; [[ -z $d ]] && d=/
    done
}

# _dev_detect [FILE]: which language to build. First match wins: a named file,
# a Makefile here, a Cargo.toml here, the C/C++/Python sources here, then a
# Cargo.toml above (so src/ finds its project, but a C exercise folder inside a
# Rust repo still builds as C).
_dev_detect() {
    if [[ -n ${1:-} ]]; then
        local lang; lang=$(_dev_lang_of "$1")
        [[ -n $lang ]] && { echo "$lang"; return 0; }
        echo "Error: don't know how to build '$1' (C, C++, Rust or Python files only)" >&2
        return 1
    fi
    if [[ -f Makefile || -f makefile || -f GNUmakefile ]]; then echo make; return 0; fi
    if [[ -f Cargo.toml ]]; then echo rust; return 0; fi
    local -a kinds=() first=()
    local -A names=([c]=C [cpp]=C++ [python]=Python)
    local k f
    for k in c cpp python; do
        for f in *; do
            [[ -f $f && $(_dev_lang_of "$f") == "$k" ]] || continue
            kinds+=("$k"); first+=("$f"); break
        done
    done
    case ${#kinds[@]} in
        0)
            if _dev_cargo_root >/dev/null; then echo rust; return 0; fi
            echo "Error: no C, C++ or Python files here, and no Makefile or Cargo.toml (for a lone .rs file, name it: run x.rs)" >&2
            return 1
            ;;
        1) echo "${kinds[0]}" ;;
        *) echo "Error: This folder has ${names[${kinds[0]}]} and ${names[${kinds[1]}]} files; name one: run ${first[0]}" >&2; return 1 ;;
    esac
}

# _dev_name LANG [FILE]: the program's name: the named file without its
# extension, otherwise the folder's name.
_dev_name() {
    if [[ -n ${2:-} ]]; then local b=${2##*/}; echo "${b%.*}"; return; fi
    echo "${PWD##*/}"
}

# _dev_parse ARGS...: the options every command shares. It fills the CALLER's
# locals (bash dynamic scope), so each command declares these first:
#   local file="" opt=0 warn=default out="" in_file="" verbose="" test_dir=.
#   local -a srcs=() extra=() pargs=()   (+ local rust_exe="" where _dev_prog runs)
# `--` puts the rest in extra: compiler flags for ru/run/rud/rut, program
# arguments for rund (it reads extra that way).
_dev_parse() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f)
                shift
                while [[ $# -gt 0 && "$1" != -* ]]; do srcs+=("$1"); shift; done
                if [[ ${#srcs[@]} -eq 0 ]]; then
                    echo "Error: -f requires at least one source or .o file" >&2; return 1
                fi
                ;;
            -O)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: -O requires a level (0, 1, 2, 3, s, g)" >&2; return 1
                fi
                opt=$2; shift 2
                ;;
            -W)
                # -W alone (or before a flag or a source file) means no warning flags.
                if [[ -z "${2:-}" || "$2" == -* || -n $(_dev_lang_of "$2") ]]; then
                    warn=none; shift
                else
                    warn=$2; shift 2
                fi
                ;;
            -o)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: -o requires an output name" >&2; return 1
                fi
                out=$2; shift 2
                ;;
            -i)
                if [[ -z "${2:-}" ]]; then echo "Error: -i requires an input file" >&2; return 1; fi
                in_file=$2; shift 2
                ;;
            -v) verbose=-v; shift ;;
            -d)
                if [[ -z "${2:-}" || "$2" == -* ]]; then echo "Error: -d requires a directory" >&2; return 1; fi
                test_dir=$2; shift 2
                ;;
            --) shift; extra+=("$@"); break ;;
            # -a: everything after it goes to the program (so it comes last).
            -a) shift; pargs+=("$@"); break ;;
            -*) echo "Error: unknown option '$1'. Use -h for help." >&2; return 1 ;;
            *)
                if [[ -n $file ]]; then echo "Error: name one file at a time ('$file' and '$1')" >&2; return 1; fi
                file=$1; shift
                ;;
        esac
    done
}

# _dev_need TOOL PACKAGE: status 1 with one line naming the package when TOOL is missing.
_dev_need() {
    command -v "$1" &>/dev/null && return 0
    echo "Error: $1 not found. Install it with your package manager (package: $2)" >&2
    return 1
}

# Build stamps: the exact compiler command of the last good build of each
# program plus a fingerprint (path, mtime, size) of every file it was built
# from, so an unchanged re-run skips the compiler. Kept out of the project
# folders, in ${XDG_CACHE_HOME:-~/.cache}/bashrc-profile/run/, one file per program.
_dev_stamp_path() {
    local abs; abs=$(realpath -m -- "$1")
    echo "${XDG_CACHE_HOME:-$HOME/.cache}/bashrc-profile/run/$(printf '%s' "$abs" | sha1sum | cut -c1-40)"
}
_dev_stamp_ok()    { local s; s=$(_dev_stamp_path "$1"); [[ -f $s && $(<"$s") == "$2" ]]; }
_dev_stamp_write() { local s; s=$(_dev_stamp_path "$1"); mkdir -p "${s%/*}" && printf '%s' "$2" > "$s"; }

# _dev_fingerprint OUT CC STD SOURCES...: one line per file the program depends
# on (path, mtime, size): the headers the compiler itself lists (cc -MM, so -I
# folders and subfolders count), the sources, .o files, and the program. A
# changed file shows up even when restored with an OLDER date (cp -p, unzip).
# Status 1 when the compiler can't list them (a syntax error): then just build.
_dev_fingerprint() {
    local o=$1 cc=$2 std=$3; shift 3
    local -a csrc=() objs=() deps=()
    local f
    for f in "$@"; do [[ $f == *.o ]] && objs+=("$f") || csrc+=("$f"); done
    if [[ ${#csrc[@]} -gt 0 ]]; then
        local raw tok
        raw=$("$cc" -MM "$std" "${extra[@]}" "${csrc[@]}" 2>/dev/null) || return 1
        raw=${raw//\\$'\n'/ }          # join continued lines
        raw=${raw//\\ /$'\x01'}        # protect escaped spaces in paths
        local IFS=$' \n\t'
        for tok in $raw; do
            [[ $tok == *: ]] && continue  # the "x.o:" rule names
            deps+=("${tok//$'\x01'/ }")
        done
    fi
    stat -c '%n %Y %s' -- "${deps[@]}" "${objs[@]}" "$o" 2>/dev/null
}

# _dev_build_cc LANG MODE: build C or C++ into ./$out (sets out when empty).
# MODE run = the VS Code build (sanitizers on); MODE plain = no sanitizers (rund,
# since they clash with valgrind). Skips the compiler when the command and the
# fingerprint of every file it depends on are unchanged since the last build.
_dev_build_cc() {
    local lang=$1 mode=$2 cc std
    if [[ $lang == c ]]; then
        std=-std=c17
        if command -v clang &>/dev/null; then cc=clang; else _dev_need gcc gcc || return 1; cc=gcc; fi
    else
        std=-std=c++20
        if command -v clang++ &>/dev/null; then cc=clang++; else _dev_need g++ g++ || return 1; cc=g++; fi
    fi

    local -a sources=()
    if [[ ${#srcs[@]} -gt 0 ]]; then sources=("${srcs[@]}")
    elif [[ -n $file ]]; then sources=("$file")
    else
        local f
        for f in *; do [[ -f $f && $(_dev_lang_of "$f") == "$lang" ]] && sources+=("$f"); done
    fi
    local s
    for s in "${sources[@]}"; do
        [[ -f $s ]] || { echo "Error: '$s' not found" >&2; return 1; }
    done
    # One source counts as named, so `run` in a one-file folder and VS Code's
    # `run sq.c` make the same ./sq.
    if [[ -z $out ]]; then
        if [[ ${#sources[@]} -eq 1 ]]; then out=$(_dev_name "$lang" "${sources[0]}"); else out=$(_dev_name "$lang"); fi
    fi

    local -a cmd=("$cc" "$std" "-O$opt" -g)
    case $warn in
        default) cmd+=(-Wall -Wextra) ;;
        none)    ;;
        *)
            local w; local -a ws
            IFS=',' read -ra ws <<< "$warn"
            for w in "${ws[@]}"; do cmd+=("-W$w"); done
            ;;
    esac
    # shellcheck disable=SC2054  # one flag: the comma belongs to -fsanitize
    [[ $mode == run ]] && cmd+=(-fsanitize=address,undefined)
    cmd+=("${extra[@]}" "${sources[@]}" -o "$out" -lm)

    local key fp; key=$(printf '%q ' "${cmd[@]}")
    if [[ -x $out ]] && fp=$(_dev_fingerprint "$out" "$cc" "$std" "${sources[@]}") \
        && _dev_stamp_ok "$out" "$key"$'\n'"$fp"; then
        return 0
    fi
    echo -e "\033[0;34m[compile]\033[0m ${cmd[*]}"
    if "${cmd[@]}"; then
        fp=$(_dev_fingerprint "$out" "$cc" "$std" "${sources[@]}") && _dev_stamp_write "$out" "$key"$'\n'"$fp"
        return 0   # a stamp that can't be written only costs the next skip
    else
        rm -f "$(_dev_stamp_path "$out")"; return 1
    fi
}

# ru: build the program (C, C++, Rust; Python has nothing to build; a Makefile folder runs make)
ru() {
    case "${1:-}" in
        -h|--help|-H)
            cat <<'HELP'
Build a program in whatever language it is, the same way VS Code's Run does.

Usage: ru [FILE] [OPTIONS] [-- EXTRA_COMPILER_FLAGS...]

Picks the language from FILE, else from this folder (first match): a Makefile,
a Cargo.toml here or above, then .c, .cpp/.cc/.cxx or .py files.

  C     clang -std=c17 -Wall -Wextra -g -O0 -fsanitize=address,undefined ... -lm
        (gcc with the same flags where clang is missing)
  C++   clang++ -std=c++20, same flags
  Rust  cargo build (a lone .rs outside a Cargo project: rustc -g)
  Make  make
  Python  nothing to build

The program is named after FILE (ru sq.c makes ./sq), or after the folder when
several files are built. A re-run of C or C++ skips the compiler when nothing
it depends on changed.

Options:
  -h, --help, -H    Show this help message
  -f FILE [FILE2..] Build these .c/.cpp/.o files together
  -O LEVEL          Optimisation level (default 0; Cargo: anything but 0 = --release;
                    lone .rs: rustc -C opt-level; ignored for Python and make)
  -W [FLAGS]        Warnings: alone = none, comma list = only those (e.g. all,error)
  -o NAME           Program name
  -a ARGS...        Arguments for the program (run, rud, rund; put it last)

Anything after -- goes to the compiler (C and C++ only).

Examples:
  ru                Build whatever is in this folder
  ru sq.c           Build sq.c into ./sq
  ru -f main.c io.c Build two files into ./<folder name>
  ru -O 2           Optimised build
  ru -- -DDEBUG     Pass a flag to the compiler
HELP
            return 0
            ;;
    esac
    # shellcheck disable=SC2034  # filled by _dev_parse (dynamic scope); not every command reads all of them
    local file="" opt=0 warn=default out="" in_file="" verbose="" test_dir=.
    local -a srcs=() extra=() pargs=()
    _dev_parse "$@" || return 1
    local lang
    if [[ -z $file && ${#srcs[@]} -gt 0 ]]; then lang=$(_dev_lang_of "${srcs[0]}"); fi
    [[ -n ${lang:-} ]] || lang=$(_dev_detect "$file") || return 1
    if [[ $lang == python ]]; then echo "Nothing to build for Python; run it with: run ${file:-FILE.py}"; return 0; fi
    _dev_build "$lang" run
}

# _dev_use_cargo: Rust goes through cargo when there is a Cargo project here or
# above and either no file was named or the named file is part of it (under its
# src/). `run scratch.rs` next to Cargo.toml builds that one file instead.
_dev_use_cargo() {
    local root; root=$(_dev_cargo_root) || return 1
    [[ -z $file ]] && return 0
    [[ $(realpath -m -- "$file") == "$root"/src/* ]]
}

# _dev_make_has_run: the Makefile here has its own `run:` target. Read from the
# Makefile itself: `make -n run` also "succeeds" when a FILE called run exists.
_dev_make_has_run() {
    grep -Eqs '^run[[:space:]]*:([^=]|$)' Makefile makefile GNUmakefile
}

# _dev_make_run: `make run`, returning the program's own exit code. make turns any
# failing recipe into 2 and prints "Error N"; this reads N back from its stderr.
# shortcut: make's stderr (and so the program's) is collected and shown when make
# ends, not live; a live tee raced with the read (and $! is unset in $(...) under
# set -u). Upgrade if a `make run` program ever needs live stderr.
_dev_make_run() {
    local err rc=0
    err=$(mktemp)
    make --no-print-directory -s run ${pargs[@]+"ARGS=${pargs[*]}"} 2>"$err" || rc=$?
    cat "$err" >&2
    if [[ $rc == 2 ]]; then
        local n; n=$(grep -o 'Error [0-9]*$' "$err" | tail -1 | grep -o '[0-9]*$')
        [[ -n $n ]] && rc=$n
    fi
    command rm -f "$err"
    return "$rc"
}

# _dev_build LANG MODE: build for LANG. Sets out (the program's name) for C,
# C++ and a lone .rs. MODE run = VS Code's build; plain = no sanitizers (rund).
_dev_build() {
    case $1 in
        c|cpp) _dev_build_cc "$1" "$2" ;;
        rust)
            if [[ $warn != default || ${#extra[@]} -gt 0 ]]; then
                echo "Error: -W and compiler flags don't apply to Rust" >&2; return 1
            fi
            if _dev_use_cargo; then
                _dev_need cargo cargo || return 1
                # One cargo call: errors and warnings render on stderr as usual,
                # and stdout carries JSON with the program's path for _dev_prog
                # (rust_exe is the caller's local). grep, not jq, which not every
                # machine has.
                local -a c=(cargo build -q --message-format=json-render-diagnostics)
                [[ $opt != 0 ]] && c+=(--release)
                local json
                json=$("${c[@]}") || return 1
                rust_exe=$(grep -o '"executable":"[^"]*"' <<<"$json" | tail -1 | cut -d'"' -f4)
            else
                # A lone .rs file (outside a Cargo project, or not part of it).
                [[ -n $file ]] || { echo "Error: name the .rs file to build: run x.rs" >&2; return 1; }
                _dev_need rustc rust || return 1
                [[ -n $out ]] || out=$(_dev_name rust "$file")
                local -a c=(rustc -g -o "$out" "$file")
                [[ $opt != 0 ]] && c+=("-Copt-level=$opt")
                echo -e "\033[0;34m[compile]\033[0m ${c[*]}"
                "${c[@]}"
            fi
            ;;
        python) return 0 ;;
        make)
            _dev_need make make || return 1
            make
            ;;
    esac
}

# _dev_prog LANG: fill the caller's prog array with the command that runs the
# program just built (after _dev_build, which set out).
_dev_prog() {
    case $1 in
        c|cpp) prog=("./$out") ;;
        rust)
            if _dev_use_cargo; then
                # _dev_build already asked cargo for the program's path.
                [[ -n ${rust_exe:-} ]] || { echo "Error: cargo built no program here (a library crate?)" >&2; return 1; }
                prog=("$rust_exe")
            else
                prog=("./$out")
            fi
            ;;
        python)
            local f=$file py=python3
            if [[ -z $f ]]; then
                if [[ -f main.py ]]; then f=main.py
                else
                    local -a pys=(*.py)
                    if [[ ${#pys[@]} -eq 1 && -f ${pys[0]} ]]; then f=${pys[0]}
                    else echo "Error: several Python files here; name one: run ${pys[0]}" >&2; return 1; fi
                fi
            fi
            if [[ -x .venv/bin/python ]]; then py=.venv/bin/python
            else
                [[ -L .venv/bin/python ]] && echo "Note: .venv/bin/python is broken (what it points to is gone); using python3" >&2
                _dev_need python3 python3 || return 1
            fi
            prog=("$py" "$f")
            ;;
        make)
            # The Makefile's PROG (mkmake writes one), else the folder's name.
            [[ -n $out ]] || out=$(sed -n 's/^PROG[[:space:]]*=[[:space:]]*//p' Makefile makefile GNUmakefile 2>/dev/null | head -1)
            [[ -n $out ]] || out=$(_dev_name make)
            [[ -x $out ]] || { echo "Error: make didn't build ./$out; add a run target to the Makefile" >&2; return 1; }
            prog=("./$out")
            ;;
    esac
}

# _dev_exit_line RC START: one dim line after a run (red when RC isn't 0), on
# stderr so `run > out.txt` keeps only the program's own output.
_dev_exit_line() {
    local secs colour='\033[2m'
    secs=$(awk -v a="$2" -v b="$EPOCHREALTIME" 'BEGIN { printf "%.2f", b - a }')
    [[ $1 != 0 ]] && colour='\033[0;31m'
    echo -e "${colour}exit $1, ${secs} s\033[0m" >&2
}

# run: build (when needed) and run the program, in whatever language it is
run() {
    case "${1:-}" in
        -h|--help|-H)
            cat <<'HELP'
Build (when needed) and run the program, in whatever language it is. VS Code's
Run button calls this too.

Usage: run [FILE] [OPTIONS] [-- EXTRA_COMPILER_FLAGS...] [-a PROGRAM_ARGS...]

Same language rules and options as ru (see ru -h). Then:
  C, C++, lone .rs   ./<name>
  Rust (Cargo)       the project's program, from target/
  Python             .venv/bin/python FILE when the folder has a .venv, else python3 FILE
                     (no FILE: main.py, or the only .py)
  Makefile           make run when the Makefile has a run target, else its PROG or ./<folder name>

Afterwards one dim line shows the exit code and the time (red when it isn't 0),
and run returns the program's exit code.

Examples:
  run               Build and run whatever is in this folder
  run sq.c          Build sq.c into ./sq and run it
  run main.py       Run main.py
  run -O 2          Optimised build, then run
  run sq.c -a 5 10  Run ./sq 5 10 (a Makefile gets make run ARGS="5 10")
HELP
            return 0
            ;;
    esac
    # shellcheck disable=SC2034  # filled by _dev_parse (dynamic scope); not every command reads all of them
    local file="" opt=0 warn=default out="" in_file="" verbose="" test_dir=.
    local -a srcs=() extra=() prog=() pargs=()
    local rust_exe=""
    _dev_parse "$@" || return 1
    local lang
    if [[ -z $file && ${#srcs[@]} -gt 0 ]]; then lang=$(_dev_lang_of "${srcs[0]}"); fi
    [[ -n ${lang:-} ]] || lang=$(_dev_detect "$file") || return 1
    _dev_build "$lang" run || return 1
    if [[ $lang == make ]] && _dev_make_has_run; then
        prog=(_dev_make_run)
    else
        _dev_prog "$lang" || return 1
    fi
    local start=$EPOCHREALTIME rc=0
    "${prog[@]}" "${pargs[@]}" || rc=$?
    _dev_exit_line "$rc" "$start"
    return "$rc"
}

# rud: debug build, then open it in the debugger (lldb; gdb if lldb is missing; pdb for Python)
rud() {
    case "${1:-}" in
        -h|--help|-H)
            cat <<'HELP'
Build for debugging (no optimisation, debug info) and open the program in a
debugger, in whatever language it is.

Usage: rud [FILE] [OPTIONS] [-- EXTRA_COMPILER_FLAGS...] [-a PROGRAM_ARGS...]

Same language rules and options as ru (see ru -h); -O is ignored (always 0).
Where lldb is missing it says so and uses gdb.
  C, C++, Rust, Makefile   lldb (gdb where lldb is missing)
  Python                   python -m pdb

In lldb: b main (breakpoint), r (run), n (next line), s (step in), p n
(print n), c (continue), q (quit).

Examples:
  rud               Debug whatever is in this folder
  rud sq.c          Build sq.c and open it in lldb
  rud main.py       Step through main.py with pdb
  rud sq.c -a 5     Debug ./sq 5
HELP
            return 0
            ;;
    esac
    # shellcheck disable=SC2034  # filled by _dev_parse (dynamic scope); not every command reads all of them
    local file="" opt=0 warn=default out="" in_file="" verbose="" test_dir=.
    local -a srcs=() extra=() prog=() pargs=()
    local rust_exe=""
    _dev_parse "$@" || return 1
    opt=0
    local lang
    if [[ -z $file && ${#srcs[@]} -gt 0 ]]; then lang=$(_dev_lang_of "${srcs[0]}"); fi
    [[ -n ${lang:-} ]] || lang=$(_dev_detect "$file") || return 1
    _dev_build "$lang" run || return 1
    _dev_prog "$lang" || return 1
    if [[ $lang == python ]]; then
        "${prog[0]}" -m pdb "${prog[@]:1}" "${pargs[@]}"
    elif command -v lldb &>/dev/null; then
        lldb -- "${prog[@]}" "${pargs[@]}"
    else
        _dev_need gdb "lldb or gdb" || return 1
        echo "Note: lldb not found, using gdb" >&2
        gdb --args "${prog[@]}" "${pargs[@]}"
    fi
}

# rund: debug build without sanitizers, then run under valgrind with a colourised report
rund() {
    case "${1:-}" in
        -h|--help|-H)
            cat <<'HELP'
Build for debugging and run under valgrind with leak checking, in C, C++,
Rust or a Makefile folder.

Builds C and C++ without the sanitizers (they clash with valgrind), then runs
the program under valgrind --leak-check=full --track-origins=yes. Output is
colourised; the raw report is saved to valgrind_YYYYMMDD-HHMMSS.log. A Makefile
folder uses the Makefile's own flags: for a mkmake Makefile run
make clean && make SANITIZE= first. Returns 1 on errors, leaks, or when
valgrind could not run the program.

Usage: rund [FILE] [OPTIONS] [-- PROGRAM_ARGS...]   (or -a PROGRAM_ARGS..., last)

Options:
  -h, --help, -H    Show this help message
  -f FILE [FILE2..] Build these files together
  -i FILE           Feed FILE to the program's stdin
  -o NAME           Program name
  -a ARGS...        Arguments for the program (rund only; put it last)
  -W [FLAGS]        Warnings (see ru -h)

Program arguments go after --.

Examples:
  rund                       Build and valgrind
  rund sq.c                  Build sq.c and valgrind it
  rund -i input.txt -- 5 10  Stdin from a file, plus program arguments
HELP
            return 0
            ;;
    esac

    # shellcheck disable=SC2034  # filled by _dev_parse (dynamic scope); not every command reads all of them
    local file="" opt=0 warn=default out="" in_file="" verbose="" test_dir=.
    local -a srcs=() extra=() prog=() prog_args=() pargs=()
    local rust_exe=""
    _dev_parse "$@" || return 1
    # For rund, everything after -- is the program's arguments, not compiler flags.
    prog_args=("${extra[@]}"); extra=(); opt=0
    local input_file=$in_file

    if [[ -n "$input_file" && ! -f "$input_file" ]]; then
        echo "Error: input file '$input_file' not found" >&2
        return 1
    fi

    local lang
    if [[ -z $file && ${#srcs[@]} -gt 0 ]]; then lang=$(_dev_lang_of "${srcs[0]}"); fi
    [[ -n ${lang:-} ]] || lang=$(_dev_detect "$file") || return 1
    if [[ $lang == python ]]; then
        echo "Error: valgrind is for compiled programs (C, C++, Rust)" >&2
        return 1
    fi
    _dev_need valgrind valgrind || return 1

    # Compile
    _dev_build "$lang" plain || return 1
    _dev_prog "$lang" || return 1
    # A program built with AddressSanitizer (a Makefile's own flags, say) can't
    # run under valgrind; say so instead of printing an empty "PASS".
    if [[ -f ${prog[0]} ]] && grep -qa __asan_init "${prog[0]}"; then
        echo "Error: ${prog[0]} was built with AddressSanitizer, which clashes with valgrind." >&2
        echo "Build it without -fsanitize first (a mkmake Makefile: make clean && make SANITIZE=), then rund." >&2
        return 1
    fi

    # Prepare valgrind output
    local logfile
    logfile="valgrind_$(date +"%Y%m%d-%H%M%S").log"
    local tmpfile
    tmpfile="$(mktemp)"
    # shellcheck disable=SC2064
    trap "command rm -f '$tmpfile'" RETURN

    # Build valgrind command
    local -a vcmd=(valgrind -s --leak-check=full --track-origins=yes "${prog[@]}")
    vcmd+=("${prog_args[@]}" "${pargs[@]}")

    echo -e "\033[0;34m[valgrind]\033[0m ${vcmd[*]}"
    echo ""

    # Run valgrind — stderr has the report, stdout has program output
    if [[ -n "$input_file" ]]; then
        "${vcmd[@]}" < "$input_file" 2>"$tmpfile"
    else
        "${vcmd[@]}" 2>"$tmpfile"
    fi

    # Save raw output
    command cp "$tmpfile" "$logfile"

    # Colors for pretty output
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[0;33m'
    local BLUE='\033[0;34m'
    local MAGENTA='\033[0;35m'
    local CYAN='\033[0;36m'
    local BOLD='\033[1m'
    local DIM='\033[2m'
    local RESET='\033[0m'

    # Parse and colorize valgrind output
    echo ""
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════${RESET}"
    echo -e "${BLUE}${BOLD}  VALGRIND REPORT${RESET}"
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════${RESET}"

    # One pass over the report with bash pattern matching only — the previous
    # version spawned echo|sed and up to nine greps per line (thousands of forks
    # on a long report).
    local line content errors=0 leaks=0 summary=""
    while IFS= read -r line; do
        content=${line#==*== }                       # strip the ==PID== prefix

        # "ERROR SUMMARY: N errors from M contexts" is the line that proves valgrind
        # ran the program to the end; without it the result is a failure.
        if [[ $content =~ ^ERROR\ SUMMARY:\ ([0-9]+)\ errors? ]]; then
            errors=${BASH_REMATCH[1]}; summary=1
            if (( errors == 0 )); then echo; echo -e "${CYAN}${BOLD}── ${content} ──${RESET}"
            else                       echo; echo -e "${RED}${BOLD}── ${content} ──${RESET}"; fi
            continue
        fi
        case $content in
            'HEAP SUMMARY'*|'LEAK SUMMARY'*)
                echo; echo -e "${CYAN}${BOLD}── ${content} ──${RESET}"; continue ;;
        esac

        # "N errors from M contexts"
        if [[ $content =~ ^([0-9]+)\ errors?\ from\ [0-9]+\ contexts ]]; then
            errors=${BASH_REMATCH[1]}
            if (( errors == 0 )); then echo -e "  ${GREEN}${BOLD}${content}${RESET}"
            else                       echo -e "  ${RED}${BOLD}${content}${RESET}"; fi
            continue
        fi

        # "definitely lost: 0 bytes in 0 blocks" (also indirectly / possibly)
        if [[ ${content,,} =~ (definitely|indirectly|possibly)\ lost:\ *([0-9,]+)\ bytes ]]; then
            if [[ ${BASH_REMATCH[2]} == 0 ]]; then echo -e "  ${GREEN}${content}${RESET}"
            else echo -e "  ${RED}${BOLD}${content}${RESET}"; (( leaks++ )); fi
            continue
        fi

        case ${content,,} in
            *'still reachable:'*)          echo -e "  ${YELLOW}${content}${RESET}"; continue ;;
            *'suppressed:'*)               echo -e "  ${DIM}${content}${RESET}"; continue ;;
            *'invalid read'*|*'invalid write'*|*'invalid free'*)
                                           echo -e "  ${RED}${BOLD}${content}${RESET}"; continue ;;
            *uninitialised*|*uninitialized*)
                                           echo -e "  ${MAGENTA}${content}${RESET}"; continue ;;
            *'all heap blocks were freed'*) echo -e "  ${GREEN}${BOLD}${content}${RESET}"; continue ;;
        esac

        # stack frames: "at 0x…" / "by 0x…"
        if [[ $content =~ ^[[:space:]]*(at|by)\ 0x ]]; then echo -e "  ${DIM}${content}${RESET}"; continue; fi

        [[ -n $content ]] && echo -e "  ${DIM}${content}${RESET}"
    done < "$tmpfile"

    # Summary
    echo ""
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════${RESET}"
    local result=1
    if [[ -z $summary ]]; then
        echo -e "  ${RED}${BOLD}RESULT: FAIL${RESET} ${RED}— valgrind could not run the program to the end (no ERROR SUMMARY; see the log)${RESET}"
    elif [[ "$errors" -eq 0 && "$leaks" -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}RESULT: PASS${RESET} ${GREEN}— no errors, no leaks${RESET}"; result=0
    elif [[ "$errors" -eq 0 ]]; then
        echo -e "  ${YELLOW}${BOLD}RESULT: LEAKS${RESET} ${YELLOW}— no errors, but $leaks leak category(s) detected${RESET}"
    else
        echo -e "  ${RED}${BOLD}RESULT: FAIL${RESET} ${RED}— $errors error(s), $leaks leak category(s)${RESET}"
    fi
    echo -e "  ${DIM}Log saved: ${logfile}${RESET}"
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════${RESET}"
    return "$result"
}

# _run_suite [-v] SUITE_FILE PROG...: run each stem listed in SUITE_FILE through PROG
_run_suite_details() {   # <stem> — called from _run_suite; uses its locals (colours, TEMPFILE)
    local stem="$1"
    local args_file="${stem}.args"
    local in_file="${stem}.in"
    local expect_file="${stem}.expect"

    echo -e "${YELLOW}Args:${RESET}"
    if [[ -r "$args_file" ]]; then
        cat "$args_file"
        echo
    else
        echo -e "${ITALIC}(none)${RESET}"
    fi

    echo -e "${YELLOW}Input:${RESET}"
    if [[ -r "$in_file" ]]; then
        cat "$in_file"
        echo
    else
        echo -e "${ITALIC}(none)${RESET}"
    fi

    echo -e "${BLUE}${BOLD}Expected:${RESET}"
    cat "$expect_file"
    echo

    echo -e "${BLUE}${BOLD}Actual:${RESET}"
    cat "$TEMPFILE"
    echo
}

_run_suite() {
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[0;33m'
    local BLUE='\033[0;34m'
    local ITALIC='\033[3m'
    local BOLD='\033[1m'
    local UNDERLINE='\033[4m'
    local RESET='\033[0m'

    local total=0
    local failed=0
    local VERBOSE=0

    if [[ "${1:-}" == "-v" ]]; then
        VERBOSE=1
        shift
    fi

    if [[ "$#" -lt 2 ]]; then
        echo "Error: _run_suite expects: _run_suite [-v] <suite-file> <program> [program args...]" >&2
        return 1
    fi

    local SUITE_FILE="$1"; shift
    local -a PROGRAM=("$@")   # a command: ./prog, or python3 main.py

    if [[ ! -r "$SUITE_FILE" ]]; then
        echo "Error: suite file '$SUITE_FILE' not found or unreadable" >&2
        return 1
    fi

    if [[ ${#PROGRAM[@]} -eq 1 && ! -x "${PROGRAM[0]}" ]]; then
        echo "Error: program '${PROGRAM[0]}' not found or not executable" >&2
        return 1
    fi

    local TEMPFILE
    TEMPFILE="$(mktemp)"
    # shellcheck disable=SC2064
    trap "command rm -f '$TEMPFILE'" RETURN

    local stem expect_file args_file in_file
    local -a argv
    while IFS= read -r stem || [[ -n "$stem" ]]; do
        # Skip blank lines
        [[ -z "$stem" ]] && continue

        (( total++ ))
        expect_file="${stem}.expect"
        args_file="${stem}.args"
        in_file="${stem}.in"

        if [[ ! -r "$expect_file" ]]; then
            echo "Error: missing or unreadable expected output file: $expect_file" >&2
            return 1
        fi

        # Build argv array from .args if readable
        argv=()
        if [[ -r "$args_file" ]]; then
            # shellcheck disable=SC2207
            argv=($(cat "$args_file"))
        fi

        # Run program with optional stdin redirection
        local prc=0
        if [[ -r "$in_file" ]]; then
            "${PROGRAM[@]}" "${argv[@]}" < "$in_file" > "$TEMPFILE" 2>&1 || prc=$?
        else
            "${PROGRAM[@]}" "${argv[@]}" > "$TEMPFILE" 2>&1 || prc=$?
        fi

        # A program killed by a signal (a crash, abort) fails even when its
        # output matched up to that point; an ordinary non-zero exit doesn't.
        if (( prc > 128 )); then
            (( failed++ ))
            echo -e "${RED}${BOLD}x Test failed:${RESET} ${UNDERLINE}$stem${RESET} (crashed, signal $(( prc - 128 )))"
            _run_suite_details "$stem"
        elif diff "$TEMPFILE" "$expect_file" > /dev/null 2>&1; then
            echo -e "${GREEN}${BOLD}> Passed:${RESET} $stem"
            if [[ "$VERBOSE" -eq 1 ]]; then
                _run_suite_details "$stem"
            fi
        else
            (( failed++ ))
            echo -e "${RED}${BOLD}x Test failed:${RESET} ${UNDERLINE}$stem${RESET}"
            _run_suite_details "$stem"
        fi
    done < "$SUITE_FILE"

    echo -e "${BLUE}${BOLD}----------------------------${RESET}"
    if [[ "$failed" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}${UNDERLINE}All tests passed:${RESET} ${GREEN}${BOLD}$total/$total${RESET}"
    else
        echo -e "${RED}${BOLD}${UNDERLINE}Some tests failed:${RESET} ${RED}${BOLD}$failed/$total${RESET}"
        return 1
    fi
}

# rut: build, then run the program against every .in/.expect test case
rut() {
    case "${1:-}" in
        -h|--help|-H)
            cat <<'HELP'
Build the program (any language, see ru -h) and run every test case here.

Test cases are file stems: for a stem "foo", the runner looks for
  foo.in       (stdin input; cases are found by their .in)
  foo.expect   (expected stdout and stderr together, required)
  foo.args     (command-line arguments, optional)
A test whose program crashes (killed by a signal) fails even if its output matched.
mkt makes empty ones: mkt foo.

Usage: rut [FILE] [-v] [-d DIR] [-f FILE...] [-- EXTRA_COMPILER_FLAGS...]

Options:
  -h, --help, -H    Show this help message
  -v                Verbose: show details for passing tests too
  -d DIR            Look for test files in DIR instead of here
  -f FILE [FILE2..] Build these files together

Examples:
  rut               Build and run all tests
  rut sq.c -v       Test sq.c, details for every test
  rut main.py       Test a Python program
  rut -d tests      Use test files from ./tests/
HELP
            return 0
            ;;
    esac

    # shellcheck disable=SC2034  # filled by _dev_parse (dynamic scope); not every command reads all of them
    local file="" opt=0 warn=default out="" in_file="" verbose="" test_dir=.
    local -a srcs=() extra=() prog=() pargs=()
    local rust_exe=""
    _dev_parse "$@" || return 1

    if [[ ! -d "$test_dir" ]]; then
        echo "Error: test directory '$test_dir' not found" >&2
        return 1
    fi

    local lang
    if [[ -z $file && ${#srcs[@]} -gt 0 ]]; then lang=$(_dev_lang_of "${srcs[0]}"); fi
    [[ -n ${lang:-} ]] || lang=$(_dev_detect "$file") || return 1
    _dev_build "$lang" run || return 1
    _dev_prog "$lang" || return 1

    # Gather test stems from *.in files in the test directory
    local stems
    stems="$(compgen -G "$test_dir/*.in" 2>/dev/null | sed 's/\.in$//' | sort -u)"

    if [[ -z "$stems" ]]; then
        echo "Error: no *.in files found in $test_dir" >&2
        return 1
    fi

    # Build a temp suite file for _run_suite
    local suite
    suite="$(mktemp)"
    printf '%s\n' "$stems" > "$suite"

    # shellcheck disable=SC2086  # $verbose is empty or -v
    _run_suite $verbose "$suite" "${prog[@]}"
    local rc=$?

    command rm -f "$suite"
    return "$rc"
}

# mkt: create test stem files (.in and .expect; .args with -a)
mkt() {
    case "$1" in
        -h|--help|-H)
            cat <<'EOF'
Create test case file pairs for the test runner.

Usage: mkt [-a] <stem> [stem2...]

Creates <stem>.in and <stem>.expect for each stem provided.

Options:
  -h, --help, -H   Show this help message
  -a                Also create a <stem>.args file

Examples:
  mkt basic              Creates basic.in and basic.expect
  mkt test1 test2        Creates files for both stems
  mkt -a with-args       Creates .in, .expect, and .args
EOF
            return 0
            ;;
        "")
            echo "Error: provide at least one test stem name" >&2
            return 1
            ;;
    esac

    local with_args=0
    if [[ "$1" == "-a" ]]; then
        with_args=1
        shift
    fi

    if [[ $# -eq 0 ]]; then
        echo "Error: provide at least one test stem name" >&2
        return 1
    fi

    local stem count=0
    for stem in "$@"; do
        touch "${stem}.in" "${stem}.expect"
        if [[ "$with_args" -eq 1 ]]; then
            touch "${stem}.args"
            echo "Created: ${stem}.in  ${stem}.expect  ${stem}.args"
        else
            echo "Created: ${stem}.in  ${stem}.expect"
        fi
        (( count++ ))
    done

    if (( count > 1 )); then
        echo "--- $count test stems created ---"
    fi
}

# mkmake: write a Makefile for the C or C++ files here (same build as run)
# shellcheck disable=SC2016  # $(PROG), $$s and the like are Makefile text, written literally
mkmake() {
    case "${1:-}" in
        -h|--help|-H)
            cat <<'HELP'
Write a Makefile for the C or C++ files in this folder, with the same build as
run and VS Code. Refuses to overwrite an existing Makefile.

Targets: all (the default: build), run, debug (lldb only), test (every
.in/.expect case, like rut), clean. The program is named after the folder
(spaces become -). `make SANITIZE=` builds without the sanitizers, for valgrind.
Needs a folder of C or C++ files (not both).

Usage: mkmake
HELP
            return 0
            ;;
    esac
    if [[ -f Makefile || -f makefile || -f GNUmakefile ]]; then
        echo "Error: Makefile already exists" >&2
        return 1
    fi
    local lang; lang=$(_dev_detect) || return 1
    # make can't have spaces in a target name, so "my dir" makes ./my-dir.
    local prog; prog=$(_dev_name "$lang"); prog=${prog//[[:space:]]/-}
    local cc cvar flags fvar srcs
    case $lang in
        c)   cvar=CC;  fvar=CFLAGS;   flags=-std=c17;   srcs='$(wildcard *.c)'
             if command -v clang &>/dev/null; then cc=clang; else cc=gcc; fi ;;
        cpp) cvar=CXX; fvar=CXXFLAGS; flags=-std=c++20; srcs='$(wildcard *.cpp *.cc *.cxx)'
             if command -v clang++ &>/dev/null; then cc=clang++; else cc=g++; fi ;;
        *)   echo "Error: mkmake writes Makefiles for C and C++ (this folder is $lang)" >&2; return 1 ;;
    esac
    # Recipe lines must start with a real tab; printf '\t' keeps them.
    {
        echo "# Written by mkmake (bashrc-profile): the same build as run and VS Code's Run."
        echo "$cvar      = $cc"
        echo "# make SANITIZE= builds without the sanitizers (for valgrind / rund)."
        echo "SANITIZE = -fsanitize=address,undefined"
        echo "$fvar  = $flags -Wall -Wextra -g -O0 \$(SANITIZE)"
        echo "LDLIBS  = -lm"
        echo "PROG    = $prog"
        echo "SRCS    = $srcs"
        echo
        echo "all: \$(PROG)"
        echo
        echo "\$(PROG): \$(SRCS) \$(wildcard *.h *.hpp)"
        printf '\t$(%s) $(%s) $(SRCS) -o $@ $(LDLIBS)\n' "$cvar" "$fvar"
        echo
        echo "# make run ARGS=\"5 10\" passes arguments (run -a 5 10 does this for you)."
        echo "run: \$(PROG)"
        printf '\t./$(PROG) $(ARGS)\n'
        echo
        echo "# lldb, or gdb where lldb is missing."
        echo "DEBUGGER = \$(shell command -v lldb >/dev/null 2>&1 && echo 'lldb --' || echo 'gdb --args')"
        echo "debug: \$(PROG)"
        printf '\t$(DEBUGGER) ./$(PROG) $(ARGS)\n'
        echo
        echo "# Every <stem>.in through the program, compared with <stem>.expect (and <stem>.args)."
        echo "test: \$(PROG)"
        printf '\t@pass=0; fail=0; for t in *.in; do [ -e "$$t" ] || continue; s="$${t%%.in}"; \\\n'
        printf '\t  if ./$(PROG) $$(cat "$$s.args" 2>/dev/null) < "$$t" 2>&1 | diff -q - "$$s.expect" >/dev/null; \\\n'
        printf '\t  then echo "ok   $$s"; pass=$$((pass+1)); else echo "FAIL $$s"; fail=$$((fail+1)); fi; done; \\\n'
        printf '\techo "$$pass passed, $$fail failed"; [ $$fail -eq 0 ]\n'
        echo
        echo "clean:"
        printf '\trm -f $(PROG)\n'
        echo
        echo ".PHONY: all run debug test clean"
    } > Makefile
    echo "Wrote Makefile ($lang, program ./$prog). Try: make, make run, make test"
}

# Tab completions for the dev commands (source files of every language)
_ru_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -f) COMPREPLY=($(compgen -f -X '!*.@(c|cc|cpp|cxx|o|rs|py)' -- "$cur")); return ;;
        -O) COMPREPLY=($(compgen -W "0 1 2 3 s g" -- "$cur")); return ;;
        -W) COMPREPLY=($(compgen -W "all extra error pedantic all,extra all,extra,error" -- "$cur")); return ;;
        -o) COMPREPLY=($(compgen -f -- "$cur")); return ;;
    esac
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-h --help -H -f -O -W -o --" -- "$cur"))
        return
    fi
    # Default to .c/.o file completion
    COMPREPLY=($(compgen -f -X '!*.@(c|cc|cpp|cxx|o|rs|py)' -- "$cur"))
}
complete -F _ru_completions ru run

_rut_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -f) COMPREPLY=($(compgen -f -X '!*.@(c|cc|cpp|cxx|o|rs|py)' -- "$cur")); return ;;
        -d) COMPREPLY=($(compgen -d -- "$cur")); return ;;
    esac
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-h --help -H -v -d -f --" -- "$cur"))
        return
    fi
}
complete -F _rut_completions rut

_rud_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -f) COMPREPLY=($(compgen -f -X '!*.@(c|cc|cpp|cxx|o|rs|py)' -- "$cur")); return ;;
        -W) COMPREPLY=($(compgen -W "all extra error pedantic all,extra all,extra,error" -- "$cur")); return ;;
        -o) COMPREPLY=($(compgen -f -- "$cur")); return ;;
    esac
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-h --help -H -f -W -o --" -- "$cur"))
        return
    fi
    COMPREPLY=($(compgen -f -X '!*.@(c|cc|cpp|cxx|o|rs|py)' -- "$cur"))
}
complete -F _rud_completions rud

_rund_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -f) COMPREPLY=($(compgen -f -X '!*.@(c|cc|cpp|cxx|o|rs|py)' -- "$cur")); return ;;
        -i) COMPREPLY=($(compgen -f -- "$cur")); return ;;
        -W) COMPREPLY=($(compgen -W "all extra error pedantic all,extra all,extra,error" -- "$cur")); return ;;
        -o) COMPREPLY=($(compgen -f -- "$cur")); return ;;
    esac
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-h --help -H -f -i -o -W --" -- "$cur"))
        return
    fi
    COMPREPLY=($(compgen -f -X '!*.@(c|cc|cpp|cxx|o|rs|py)' -- "$cur"))
}
complete -F _rund_completions rund

_mkt_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-h --help -H -a" -- "$cur"))
    fi
}
complete -F _mkt_completions mkt

_mkmake_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    [[ "$cur" == -* ]] && COMPREPLY=($(compgen -W "-h --help -H" -- "$cur"))
}
complete -F _mkmake_completions mkmake

