#!/usr/bin/env bash
# lib/dev.sh — build, run, debug and test programs in C, C++, Rust, Python or a
# Makefile folder (lazy-loaded on first use). VS Code's Run button calls `run`.
#   ru      build (clang gnu17 / gnu++20 with sanitizers; cargo; make)
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

# _dev_lang_of FILE: the language of a source file by its extension (or of a
# folder that is a Python package), or nothing. .C, .cc, .cxx, .c++ and .cpp in
# any case are C++, as gcc and clang treat them.
_dev_lang_of() {
    # Always called as $(...), so this doesn't touch the user's shell: with
    # nocasematch on, x.C would match *.c.
    shopt -u nocasematch 2>/dev/null
    if [[ -d $1 ]]; then [[ -f $1/__main__.py ]] && echo python; return 0; fi
    case "$1" in
        *.c)                                                    echo c ;;
        *.C|*.[cC][pP][pP]|*.[cC][cC]|*.[cC][xX][xX]|*.[cC]++)  echo cpp ;;
        *.rs)                                                   echo rust ;;
        *.py)                                                   echo python ;;
    esac
}

# _dev_list: this folder's regular files as ./name, NUL-separated and sorted.
# find, not a * glob: safe with failglob or nullglob set, and with names that
# start with a dash (./-x.c is never read as an option).
_dev_list() { command find . -maxdepth 1 -type f -print0 2>/dev/null | command sort -z; }

# _dev_cargo_root: the nearest folder at or above the current one with a
# Cargo.toml (symlinks resolved, like realpath elsewhere); status 1 when none.
_dev_cargo_root() {
    local d; d=$(builtin pwd -P)
    while :; do
        [[ -f $d/Cargo.toml ]] && { echo "$d"; return 0; }
        [[ $d == / || -z $d ]] && return 1
        d=${d%/*}; [[ -z $d ]] && d=/
    done
}

# _dev_detect [FILE]: which language to build. First match wins: a named file,
# a Makefile here, a Cargo.toml here, a Python package here (__main__.py), the
# C/C++/Python sources here, then a Cargo.toml above (so src/ finds its project,
# but a C exercise folder inside a Rust repo still builds as C).
_dev_detect() {
    if [[ -n ${1:-} ]]; then
        local lang; lang=$(_dev_lang_of "$1")
        [[ -n $lang ]] && { echo "$lang"; return 0; }
        echo "Error: don't know how to build '$1' (C, C++, Rust or Python files, or a Python package folder)" >&2
        return 1
    fi
    if [[ -f Makefile || -f makefile || -f GNUmakefile ]]; then echo make; return 0; fi
    if [[ -f Cargo.toml ]]; then echo rust; return 0; fi
    if [[ -f __main__.py ]]; then echo python; return 0; fi
    local -a kinds=() first=()
    local -A names=([c]=C [cpp]=C++ [python]=Python) seen=()
    local f k
    while IFS= read -r -d '' f; do
        k=$(_dev_lang_of "$f")
        [[ $k == @(c|cpp|python) && -z ${seen[$k]:-} ]] || continue
        seen[$k]=1; kinds+=("$k"); first+=("${f#./}")
    done < <(_dev_list)
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

# _dev_pick_lang: the language for the caller's file and srcs (dynamic scope):
# the named file, else the first -f file with a known language (.o files alone
# mean C), else the folder.
_dev_pick_lang() {
    if [[ -n $file ]]; then _dev_detect "$file"; return; fi
    local s l
    for s in "${srcs[@]}"; do l=$(_dev_lang_of "$s"); [[ -n $l ]] && { echo "$l"; return 0; }; done
    [[ ${#srcs[@]} -gt 0 ]] && { echo c; return 0; }
    _dev_detect
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
#   local -a srcs=() extra=() pargs=() penv=()   (+ local rust_exe="" and prog=())
# `--` puts what follows (up to an -a) in extra: compiler flags for ru/run/rud/rut,
# program arguments for rund. -a puts everything after it in pargs.
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
            # The compiler's own spellings work too: -O2, -Wall, -Wall,error.
            -O?*) opt=${1#-O}; shift ;;
            -W?*) warn=${1#-W}; shift ;;
            --)
                shift
                while [[ $# -gt 0 && $1 != -a ]]; do extra+=("$1"); shift; done
                ;;
            # -a: everything after it goes to the program (so it comes last).
            -a)
                shift; pargs+=("$@")
                local a
                for a in "$@"; do
                    case $a in
                        -O|-W|-o|-f|-i|-d|-v)
                            echo "Note: everything after -a goes to the program, including '$a'; put options before -a" >&2
                            break ;;
                    esac
                done
                break ;;
            -*) echo "Error: unknown option '$1'. Use -h for help." >&2; return 1 ;;
            *)
                if [[ -n $file ]]; then echo "Error: name one file at a time ('$file' and '$1')" >&2; return 1; fi
                file=$1; shift
                ;;
        esac
    done
}

# _dev_refuse CMD LETTER...: status 1 when the caller got an option CMD doesn't
# use (a: -a, i: -i, v: -v, d: -d), instead of silently ignoring it.
_dev_refuse() {
    local cmd=$1 l why; shift
    for l in "$@"; do
        case $cmd in
            ru)  why="ru only builds" ;;
            rut) why="rut takes arguments from <stem>.args and input from <stem>.in" ;;
            rud) why="in rud, type the input in the debugger" ;;
            *)   why="" ;;
        esac
        case $l in
            a) [[ ${#pargs[@]} -eq 0 ]] || { echo "Error: -a is for run, rud and rund${why:+ ($why)}" >&2; return 1; } ;;
            i) [[ -z $in_file ]] || { echo "Error: -i is for run and rund${why:+ ($why)}" >&2; return 1; } ;;
            v) [[ -z $verbose ]] || { echo "Error: -v is for rut" >&2; return 1; } ;;
            d) [[ $test_dir == . ]] || { echo "Error: -d is for rut" >&2; return 1; } ;;
        esac
    done
}

# _dev_show WORD...: a command as you'd type it, for the [compile] and [valgrind]
# lines: words with spaces, quotes or shell characters are quoted, plain words
# (commas included; bash's %q would print address\,undefined) as they are.
_dev_show() {
    local w s=""
    for w in "$@"; do
        if [[ $w =~ ^[A-Za-z0-9_./=:,+@%-]+$ ]]; then s+="$w "; else s+="$(printf '%q' "$w") "; fi
    done
    printf '%s' "${s% }"
}

# _dev_tmp: a new temp file in ${XDG_CACHE_HOME:-~/.cache}/bashrc-profile/tmp, not
# $TMPDIR. A Ctrl-C that aborts a command (ble.sh can) leaves its temp file
# behind; here every later call clears the ones older than a day. Not sooner: a
# live run can leave its file untouched for hours (rund's valgrind log while the
# program waits for input).
_dev_tmp() {
    local d="${XDG_CACHE_HOME:-$HOME/.cache}/bashrc-profile/tmp"
    command mkdir -p -- "$d" || return 1
    command find "$d" -maxdepth 1 -type f -mmin +1440 -delete 2>/dev/null
    command mktemp "$d/XXXXXXXX"
}

# _dev_need TOOL PACKAGE: status 1 with one line naming the package when TOOL is missing.
_dev_need() {
    command -v "$1" &>/dev/null && return 0
    echo "Error: $1 not found. Install it with your package manager (package: $2)" >&2
    return 1
}

# Build stamps: the exact compiler command of the last good build of each
# program, a fingerprint of every file it was built from, and the program file's
# own, so an unchanged re-run skips the compiler. Kept out of the project folders,
# in ${XDG_CACHE_HOME:-~/.cache}/bashrc-profile/run/, one file per program. Every
# write uses >| so a user's `set -C` (noclobber) can't leave a stale stamp.
_dev_stamp_path() {
    local abs; abs=$(command realpath -m -- "$1")
    echo "${XDG_CACHE_HOME:-$HOME/.cache}/bashrc-profile/run/$(printf '%s' "$abs" | command sha1sum | command cut -c1-40)"
}
_dev_stamp_ok()    { local s; s=$(_dev_stamp_path "$1"); [[ -f $s && $(<"$s") == "$2" ]]; }
_dev_stamp_write() { local s; s=$(_dev_stamp_path "$1"); command mkdir -p -- "${s%/*}" && printf '%s' "$2" >| "$s"; }
# _dev_stat FILE...: path, modification time to the nanosecond, size and inode, symlinks followed.
_dev_stat() { command stat -L -c '%n %y %s %i' -- "$@" 2>/dev/null; }

# _dev_fingerprint CC STD SOURCES...: _dev_stat of every file the program is built
# from: all the headers the compiler itself lists (cc -M: -I and -isystem folders,
# subfolders, system headers), the sources and the .o files. A same-second edit,
# an older date (cp -p, unzip) or a swapped file all change it. Status 1 when the
# compiler can't list them (a syntax error): then just build.
_dev_fingerprint() {
    local cc=$1 std=$2; shift 2
    local -a csrc=() objs=() deps=() toks=() cflags=() ldirs=()
    local f tok raw x n d ext found
    for f in "$@"; do
        case $f in *.o|*.a|*.so|*.so.*) objs+=("$f") ;; *) csrc+=("$f") ;; esac
    done
    # Libraries named with -lNAME count too: found in the -L folders, else where
    # the compiler itself would find them. Link-only flags stay out of cc -M.
    for x in "${extra[@]}"; do
        case $x in
            -L?*) ldirs+=("${x#-L}"); cflags+=("$x") ;;
            -l?*|-Wl,*) ;;
            *) cflags+=("$x") ;;
        esac
    done
    for x in "${extra[@]}"; do
        [[ $x == -l?* ]] || continue
        n=${x#-l} found=""
        for d in "${ldirs[@]}"; do
            for ext in so a; do [[ -f $d/lib$n.$ext ]] && { objs+=("$d/lib$n.$ext"); found=1; break 2; }; done
        done
        if [[ -z $found ]]; then
            f=$("$cc" -print-file-name="lib$n.so" 2>/dev/null) || f=""
            [[ $f == /* && -f $f ]] && objs+=("$f")
        fi
    done
    if [[ ${#csrc[@]} -gt 0 ]]; then
        raw=$("$cc" -M "$std" "${cflags[@]}" "${csrc[@]}" 2>/dev/null) || return 1
        raw=${raw//\\$'\n'/ }          # join continued lines
        raw=${raw//\\ /$'\x01'}        # protect escaped spaces in paths
        raw=${raw//\\#/#}              # undo make's escapes for # and $
        raw=${raw//\$\$/\$}
        IFS=$' \n\t' read -r -d '' -a toks <<<"$raw" || true   # split without globbing
        for tok in "${toks[@]}"; do
            [[ $tok == *: ]] && continue   # the "x.o:" rule names
            deps+=("${tok//$'\x01'/ }")
        done
    fi
    _dev_stat "${deps[@]}" "${objs[@]}"
}

# _dev_build_cc LANG MODE: build C or C++ into ./$out (sets out when empty).
# MODE run = the VS Code build (sanitizers on); MODE plain = no sanitizers (rund,
# since they clash with valgrind). Skips the compiler when the command, the
# fingerprint of every file it depends on and the program file are unchanged.
_dev_build_cc() {
    local lang=$1 mode=$2 cc std
    # gnu17, not strict c17: C17 plus the POSIX/GNU functions courses use
    # (strdup, getline, M_PI...), the same as clang's and gcc's own default.
    if [[ $lang == c ]]; then
        std=-std=gnu17
        if command -v clang &>/dev/null; then cc=clang; else _dev_need gcc gcc || return 1; cc=gcc; fi
    else
        std=-std=gnu++20
        if command -v clang++ &>/dev/null; then cc=clang++; else _dev_need g++ g++ || return 1; cc=g++; fi
    fi

    # The named file and any -f files are built together; with neither, every
    # source of this language in the folder.
    local -a sources=()
    [[ -n $file ]] && sources+=("$file")
    sources+=("${srcs[@]}")
    local s f
    if [[ ${#sources[@]} -eq 0 ]]; then
        while IFS= read -r -d '' f; do [[ $(_dev_lang_of "$f") == "$lang" ]] && sources+=("$f"); done < <(_dev_list)
    fi
    for s in "${sources[@]}"; do
        [[ -f $s ]] || { echo "Error: '$s' not found" >&2; return 1; }
    done
    # One source counts as named, so `run` in a one-file folder and VS Code's
    # `run sq.c` make the same ./sq.
    if [[ -z $out ]]; then
        if [[ -n $file ]]; then out=$(_dev_name "$lang" "$file")
        elif [[ ${#sources[@]} -eq 1 ]]; then out=$(_dev_name "$lang" "${sources[0]}")
        else out=$(_dev_name "$lang"); fi
    fi
    # Never write the program over a source, or over a file that isn't a program.
    local oabs; oabs=$(command realpath -m -- "$out")
    for s in "${sources[@]}"; do
        [[ $(command realpath -m -- "$s") == "$oabs" ]] && { echo "Error: -o $out would overwrite the source file $s" >&2; return 1; }
    done
    [[ -d $out ]] && { echo "Error: '$out' is a folder; name the program with -o NAME" >&2; return 1; }
    # A program here is an ELF file; a script or text with that name is yours.
    if [[ -e $out ]]; then
        local magic=""; IFS= read -r -n 4 magic < "$out" 2>/dev/null
        [[ $magic == $'\x7f'ELF ]] || { echo "Error: '$out' exists and isn't a program; not overwriting it (name the program with -o NAME)" >&2; return 1; }
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
    # Libraries (-lNAME) go after the sources, where every linker looks for them.
    local -a libs=() flags=()
    for f in "${extra[@]}"; do if [[ $f == -l?* ]]; then libs+=("$f"); else flags+=("$f"); fi; done
    cmd+=("${flags[@]}" "${sources[@]}" -o "$out" "${libs[@]}" -lm)

    # The fingerprint is taken BEFORE compiling: a file saved during the compile
    # then differs at the next run, which rebuilds instead of trusting old code.
    # The check and the build run in a subshell holding a lock on this program
    # (flock), so two runs at once in one folder take turns instead of linking
    # over each other ("Text file busy"); the lock goes with the subshell, even
    # on Ctrl-C.
    local key lock=/dev/null; key=$(printf '%q ' "${cmd[@]}")
    if command -v flock &>/dev/null; then
        lock=$(_dev_stamp_path "$out").lock
        command mkdir -p -- "${lock%/*}" || lock=/dev/null
    fi
    (
        [[ $lock == /dev/null ]] || command flock -w 300 9 || { echo "Error: another build of $out is still running" >&2; exit 1; }
        fp=$(_dev_fingerprint "$cc" "$std" "${sources[@]}") || fp=""
        if [[ -n $fp && -x $out ]] && _dev_stamp_ok "$out" "$key"$'\n'"$fp"$'\n'"$(_dev_stat "$out")"; then
            exit 0
        fi
        # On stderr, so `run > out.txt` keeps only the program's output.
        printf '\033[0;34m[compile]\033[0m %s\n' "$(_dev_show "${cmd[@]}")" >&2
        # The compiler's messages are kept (colour kept for a terminal) to add a
        # hint after a failed link. With nowhere to keep them (an unwritable
        # cache) they go straight to the terminal, without the hints.
        local -a ccolor=(); [[ -t 2 ]] && ccolor=(-fdiagnostics-color=always)
        if ! cerr=$(_dev_tmp 2>/dev/null); then
            "${cmd[@]}" && exit 0
            command rm -f -- "$(_dev_stamp_path "$out")"; exit 1
        fi
        if "${cmd[@]}" "${ccolor[@]}" 2>|"$cerr"; then
            command cat -- "$cerr" >&2; command rm -f -- "$cerr"
            [[ -n $fp ]] && _dev_stamp_write "$out" "$key"$'\n'"$fp"$'\n'"$(_dev_stat "$out")"
            exit 0   # a stamp that can't be written only costs the next skip
        fi
        # Several files each with their own main() are separate programs (a folder
        # of lab exercises), not one: once the linker has said so, one line names
        # them instead of its wall. Checked only after the link failed, so a main()
        # behind #ifdef or in a comment can never block a build that works.
        local -a mains=(); local s
        if [[ ${#sources[@]} -gt 1 ]] && command grep -qE "multiple definition of .main'|duplicate symbol.*[ _]main\b" "$cerr" 2>/dev/null; then
            for s in "${sources[@]}"; do
                [[ $s == *.@(o|a|so) || " ${mains[*]} " == *" ${s#./} "* ]] && continue
                command grep -qE '^[[:space:]]*(static[[:space:]]+)?(int|void)[[:space:]]+main[[:space:]]*\(' -- "$s" 2>/dev/null && mains+=("${s#./}")
            done
        fi
        if [[ ${#mains[@]} -gt 1 ]]; then
            echo "Error: ${mains[0]} and ${mains[1]}$([[ ${#mains[@]} -gt 2 ]] && echo " (and others)") each have a main(); name one: run ${mains[0]}" >&2
        else
            command cat -- "$cerr" >&2
        fi
        if [[ ${#sources[@]} -eq 1 ]] && command grep -qE 'undefined reference to|Undefined symbols' "$cerr" 2>/dev/null; then
            local -a others=(); local o
            while IFS= read -r -d '' o; do
                [[ $(_dev_lang_of "$o") == "$lang" && $(command realpath -- "$o") != "$(command realpath -- "${sources[0]}")" ]] && others+=("${o#./}")
            done < <(_dev_list)
            [[ ${#others[@]} -gt 0 ]] && echo "Note: the missing function may be in another file here (${others[*]}); build them together: run -f ${sources[0]#./} ${others[0]} (or plain run)" >&2
        fi
        command rm -f -- "$cerr" "$(_dev_stamp_path "$out")"; exit 1
    ) 9>>"$lock"
}

# ru: build the program (C, C++, Rust; Python has nothing to build; a Makefile folder runs make)
ru() {
    case "${1:-}" in
        -h|--help|-H)
            command cat <<'HELP'
Build a program in whatever language it is, the same way VS Code's Run does.

Usage: ru [FILE] [OPTIONS] [-- EXTRA_COMPILER_FLAGS...]

Picks the language from FILE, else from this folder (first match): a Makefile,
a Cargo.toml here, a Python package (__main__.py), .c, .cpp/.cc/.cxx/.C or .py
files, then a Cargo.toml in a folder above.

  C     clang -std=gnu17 -Wall -Wextra -g -O0 -fsanitize=address,undefined ... -lm
        (gnu17 = C17 plus POSIX functions like strdup; gcc where clang is missing)
  C++   clang++ -std=gnu++20, same flags
  Rust  cargo build (a .rs that isn't a project's src/main.rs or src/bin/*.rs:
        rustc --edition 2021 -g)
  Make  make (the default target; never a run, clean or test target)
  Python  nothing to build

The program is named after FILE (ru sq.c makes ./sq), or after the folder when
several files are built; it never overwrites a source or a file that isn't a
program. A re-run of C or C++ skips the compiler when nothing it depends on
changed (every header, followed symlinks, to the nanosecond).

Options:
  -h, --help, -H    Show this help message
  -f FILE [FILE2..] Build these .c/.cpp/.o files too (with FILE, if named)
  -O LEVEL          Optimisation level, also -O2 (default 0; Cargo: anything but 0
                    = --release; lone .rs: rustc -C opt-level; ignored for Python and make)
  -W [FLAGS]        Warnings: alone = none, comma list = only those (e.g. all,error);
                    also -Wall, -Wall,error
  -o NAME           Program name (a Makefile folder: the program make builds)

Anything after -- goes to the compiler (C and C++ only).

Examples:
  ru                Build whatever is in this folder
  ru sq.c           Build sq.c into ./sq
  ru -f main.c io.c Build two files into ./<folder name>
  ru -O2            Optimised build
  ru -- -DDEBUG     Pass a flag to the compiler
HELP
            return 0
            ;;
    esac
    # shellcheck disable=SC2034  # filled by _dev_parse (dynamic scope); not every command reads all of them
    local file="" opt=0 warn=default out="" in_file="" verbose="" test_dir=.
    local -a srcs=() extra=() pargs=() penv=() mk_pre=()
    local rust_exe="" mk_done="" mk_goal="" mk_run="" mk_prog="" mk_args="" mk_shell=""
    _dev_parse "$@" || return 1
    _dev_refuse ru a i v d || return 1
    local lang; lang=$(_dev_pick_lang) || return 1
    if [[ $lang == python ]]; then echo "Nothing to build for Python; run it with: run ${file:-FILE.py}"; return 0; fi
    # In a Makefile folder ru always builds (mode build), even when run would
    # leave the building to `make run`.
    if [[ $lang == make ]]; then _dev_build make build; else _dev_build "$lang" run; fi
}

# _dev_cargo_pkg ROOT: the [package] name in ROOT/Cargo.toml (empty for a workspace).
_dev_cargo_pkg() {
    command sed -n "/^\[package\]/,/^\[/{s/^name[[:space:]]*=[[:space:]]*[\"']\([^\"']*\)[\"'].*/\1/p;}" "$1/Cargo.toml" 2>/dev/null | command head -1
}
# _dev_cargo_edition ROOT: the project's edition (2021 when it doesn't say).
_dev_cargo_edition() {
    local e; e=$(command sed -n "s/^edition[[:space:]]*=[[:space:]]*[\"']\([0-9]*\)[\"'].*/\1/p" "$1/Cargo.toml" 2>/dev/null | command head -1)
    echo "${e:-2021}"
}

# _dev_rust_plan: how to build Rust, into the caller's rs_root (the Cargo project:
# the one around the named file, or here or above; empty = no project), rs_file
# (the named file's real path) and rs_example (its name when it is in examples/).
_dev_rust_plan() {
    rs_root="" rs_file="" rs_example=""
    if [[ -z $file ]]; then rs_root=$(_dev_cargo_root) || rs_root=""; return 0; fi
    [[ -f $file ]] || { echo "Error: '$file' not found" >&2; return 1; }
    rs_file=$(command realpath -- "$file")
    local root=${rs_file%/*}
    while [[ ! -f $root/Cargo.toml ]]; do
        [[ $root == / || -z $root ]] && return 0
        root=${root%/*}; [[ -z $root ]] && root=/
    done
    rs_root=$root
    if [[ $rs_file == "$root"/examples/*.rs ]]; then
        rs_example=${rs_file#"$root"/examples/}; rs_example=${rs_example%/main.rs}; rs_example=${rs_example%.rs}
    fi
}

# _dev_rust_pick JSON: set the caller's rust_exe from cargo's build messages, which
# give each program's source file (src_path) and path (executable). A named file:
# the program built from it (renamed [[bin]]s included), or status 2 when none is
# (then the file is built on its own). Nothing named: the only program; else the
# project's default-run; else the one named like the package; else stop and list
# them. A library crate leaves rust_exe empty.
_dev_rust_pick() {
    local -a exes=() srcp=()
    local line ex sp want="" i built=""
    while IFS= read -r line; do
        [[ $line == *'"executable":"'* ]] || continue
        ex=${line#*\"executable\":\"}; ex=${ex%%\"*}
        sp=${line#*\"src_path\":\"}; sp=${sp%%\"*}
        exes+=("$ex"); srcp+=("$sp")
    done <<<"$1"
    rust_exe=""
    if [[ -n $rs_file ]]; then
        for i in "${!srcp[@]}"; do [[ ${srcp[i]} == "$rs_file" ]] && { rust_exe=${exes[i]}; return 0; }; done
        return 2
    fi
    [[ ${#exes[@]} -eq 0 ]] && return 0
    if [[ ${#exes[@]} -eq 1 ]]; then rust_exe=${exes[0]}; return 0; fi
    want=$(command sed -n "s/^default-run[[:space:]]*=[[:space:]]*[\"']\([^\"']*\)[\"'].*/\1/p" "$rs_root/Cargo.toml" 2>/dev/null | command head -1)
    [[ -n $want ]] || want=$(_dev_cargo_pkg "$rs_root")
    for i in "${!exes[@]}"; do [[ ${exes[i]##*/} == "$want" ]] && { rust_exe=${exes[i]}; return 0; }; done
    for i in "${!srcp[@]}"; do built+="${built:+, }run $(command realpath -m --relative-to=. -- "${srcp[i]}")"; done
    echo "Error: this project has several programs; name one: $built (or set default-run in Cargo.toml)" >&2
    return 1
}

# _dev_make_info: read the Makefile the way make does (includes, variables,
# multi-target lines) from `make -pq`, which prints make's database and runs no
# recipe (only $(MAKE) lines of the default target, as make always does). Read
# once per command (mk_done) and kept in the caller's locals: mk_goal (the default
# target), mk_run (1 when a run target has a recipe of its own), mk_prog (PROG as
# make expands it, only when the Makefile sets it: an exported PROG in your shell
# doesn't count), mk_pre (the default target's prerequisites) and mk_args (1 when
# the Makefile uses $(ARGS)).
# shellcheck disable=SC2016  # $(info ...), $(ARGS) are make syntax, written literally
_dev_make_info() {
    [[ -n $mk_done ]] && return 0
    mk_done=1 mk_goal="" mk_run="" mk_prog="" mk_args="" mk_shell="" mk_pre=()
    local mf pf db line target="" prev=""
    for mf in GNUmakefile makefile Makefile; do [[ -f $mf ]] && break; done
    pf=$(_dev_tmp) || return 1
    printf '%s\n' '$(info _DEV_PROG=$(strip $(if $(filter file override,$(origin PROG)),$(PROG))))' \
        '$(info _DEV_SHELL=$(SHELL))' >| "$pf"
    # -r leaves out make's ~1,000 lines of built-in rules (a Makefile's own
    # targets, variables and includes are all still there).
    db=$(LC_ALL=C command make -pqr -f "$mf" -f "$pf" 2>/dev/null) || true
    command rm -f -- "$pf"
    mk_prog=$(command sed -n 's/^_DEV_PROG=//p' <<<"$db" | command head -1)
    mk_goal=$(command sed -n 's/^\.DEFAULT_GOAL := //p' <<<"$db" | command tail -1)
    mk_shell=$(command sed -n 's/^_DEV_SHELL=//p' <<<"$db" | command head -1)
    [[ $db == *'$(ARGS)'* ]] && mk_args=1
    # Only the lines that matter go through the (slow) read loop: blank lines,
    # target lines, "# Not a target:" and recipe markers.
    db=$(command grep -E '^$|^# Not a target:|^#  recipe to execute|^[^#[:space:]][^=]*:' <<<"$db") || db=""
    while IFS= read -r line; do
        if [[ -z $line ]]; then target=""
        elif [[ $prev != "# Not a target:" && $line != [#[:space:]]* && $line == *:* && $line != *:=* ]]; then
            target=${line%%:*}
            [[ -n $mk_goal && $target == "$mk_goal" ]] && read -r -a mk_pre <<<"${line#*:}"
        elif [[ $target == run && $line == "#  recipe to execute"* ]]; then
            mk_run=1
        fi
        prev=$line
    done <<<"$db"
}

# _dev_make_run: `make run`, returning the program's own exit code and showing
# its output live. make turns any failing recipe into exit 2, so make runs its
# recipes through a tiny stand-in shell (SHELL=...make-shell, which runs the
# Makefile's own SHELL, flags and all) that notes every failing command's code
# and its make level. make stops at the first failure it doesn't ignore (a `-`
# line it does), so the top level's last code is the real one; a 2 there with a
# deeper level noted is a $(MAKE) line, so that level's last code is the
# program's, through nested makes and crashes (139 for a segfault).
# shortcut: a program that itself exits 2 after an ignored failure in a sub-make
# reads as that sub-make's code; upgrade if a real Makefile does that.
_dev_make_run() {
    local rc=0 rcf wrap saved
    local -a margs=() shellarg=()
    if [[ ${#pargs[@]} -gt 0 ]]; then
        # shellcheck disable=SC2016  # $(ARGS) is make syntax
        [[ -n $mk_args ]] || echo 'Note: the Makefile'"'"'s run target does not use $(ARGS); the -a arguments are ignored' >&2
        # Each argument single-quoted for the recipe's shell, then every $ doubled
        # for make, so spaces, quotes, ; and $ reach the program exactly as typed.
        local a q=""
        for a in "${pargs[@]}"; do q+="'${a//\'/\'\\\'\'}' "; done
        margs=("ARGS=${q//\$/\$\$}")
    fi
    rcf=$(_dev_tmp) || return 1
    wrap="${XDG_CACHE_HOME:-$HOME/.cache}/bashrc-profile/make-shell"
    # make splits SHELL at spaces, so a stand-in whose path has one can't be used:
    # then make's own status (2 for any failure) comes back.
    # shortcut: no program exit code when the cache path has a space; upgrade if someone hits it.
    # Written to a new file ($BASHPID: unique even in a subshell, unlike $$) and
    # renamed into place, so a run already using the
    # old one never sees a half-written script or "Text file busy".
    if [[ $wrap != *[[:space:]]* ]]; then
        # The stand-in keeps its own shell's messages apart (2> a file) so a crash
        # reads "./prog 5: Segmentation fault (core dumped)", naming the recipe,
        # not "make-shell: line 3: ... $DEV_MAKE_SHELL"; anything else it says is
        # passed on as it was. (A dash /bin/sh says nothing there: no line at all.)
        # The name is fixed here: an external command's redirection is expanded
        # after its fork, where $BASHPID is already the child's.
        local wtmp="$wrap.$BASHPID"
        if command cat >| "$wtmp" <<'SH' \
            && command chmod +x -- "$wtmp" && command mv -f -- "$wtmp" "$wrap"; then
#!/bin/sh
set -f
m="$DEV_MAKE_RC.$$"
if (: > "$m") 2>/dev/null; then
    { $DEV_MAKE_SHELL "$@" 2>&3 3>&-; } 3>&2 2>"$m"
    rc=$?
    if [ -s "$m" ]; then
        for cmd; do :; done
        cmd=$(printf '%s\n' "$cmd" | head -n 1)
        grep -vF '$DEV_MAKE_SHELL "$@"' "$m" >&2
        grep -F '$DEV_MAKE_SHELL "$@"' "$m" | sed -n 's/^.*: [0-9][0-9]* \(.*\) \$DEV_MAKE_SHELL "\$@".*$/\1/p' | tr -s ' ' |
            while IFS= read -r what; do printf '%s: %s\n' "$cmd" "$what" >&2; done
    fi
    rm -f "$m"
else
    $DEV_MAKE_SHELL "$@"
    rc=$?
fi
[ "$rc" -ne 0 ] && echo "${MAKELEVEL:-0} $rc" >> "$DEV_MAKE_RC"
exit "$rc"
SH
            shellarg=("SHELL=$wrap")
        else
            command rm -f -- "$wtmp"
        fi
    fi
    # Ctrl-C stops the program, not this function: the code below still runs.
    saved=$(trap -p INT); trap ':' INT
    DEV_MAKE_SHELL=${mk_shell:-/bin/sh} DEV_MAKE_RC=$rcf \
        command make --no-print-directory -s run "${shellarg[@]}" "${margs[@]}" || rc=$?
    if [[ -n $saved ]]; then eval "$saved"; else trap - INT; fi
    if [[ $rc != 0 && -s $rcf ]]; then
        local lv code top=""; local -A last=()
        while read -r lv code; do
            [[ $lv =~ ^[0-9]+$ && $code =~ ^[0-9]+$ ]] || continue
            last[$lv]=$code; [[ -z $top || $lv -lt $top ]] && top=$lv
        done < "$rcf"
        if [[ -n $top ]]; then
            rc=${last[$top]}
            while [[ $rc == 2 && -n ${last[$((top + 1))]:-} ]]; do top=$((top + 1)); rc=${last[$top]}; done
        fi
    fi
    command rm -f -- "$rcf"
    return "$rc"
}

# _dev_build LANG MODE: build for LANG. Sets out (the program's name) for C,
# C++ and a lone .rs, and rust_exe for a Cargo project. MODE run = VS Code's
# build; plain = no sanitizers (rund).
_dev_build() {
    case $1 in
        c|cpp) _dev_build_cc "$1" "$2" ;;
        rust)
            local rs_root rs_file rs_example edition=2021
            _dev_rust_plan || return 1
            if [[ -n $rs_root ]]; then
                edition=$(_dev_cargo_edition "$rs_root")
                if [[ $warn != default || ${#extra[@]} -gt 0 || -n $out || ${#srcs[@]} -gt 0 ]]; then
                    echo "Error: -W, -o, -f and compiler flags don't apply to Rust (Cargo projects)" >&2; return 1
                fi
                _dev_need cargo cargo || return 1
                # One cargo call: errors and warnings render on stderr as usual, and
                # stdout carries JSON with the programs' paths for _dev_rust_pick.
                local -a c=(cargo build -q --message-format=json-render-diagnostics --manifest-path "$rs_root/Cargo.toml")
                [[ -n $rs_example ]] && c+=(--example "$rs_example")
                [[ $opt != 0 ]] && c+=(--release)
                local json pick=0
                json=$("${c[@]}") || return 1
                _dev_rust_pick "$json" || pick=$?
                [[ $pick == 0 ]] && return 0
                [[ $pick == 2 ]] || return 1
                # A named file that no program is built from (a module, a scratch
                # file): build it on its own, with the project's edition.
            fi
            [[ -n $file ]] || { echo "Error: name the .rs file to build: run x.rs" >&2; return 1; }
            if [[ $warn != default || ${#extra[@]} -gt 0 ]]; then
                echo "Error: -W and compiler flags don't apply to Rust" >&2; return 1
            fi
            _dev_need rustc rustc || return 1
            [[ -n $out ]] || out=$(_dev_name rust "$file")
            local -a c=(rustc --edition "$edition" -g -o "$out" "$file")
            [[ $opt != 0 ]] && c+=("-Copt-level=$opt")
            printf '\033[0;34m[compile]\033[0m %s\n' "$(_dev_show "${c[@]}")" >&2
            "${c[@]}"
            ;;
        python) return 0 ;;
        make)
            _dev_need make make || return 1
            if [[ $warn != default || ${#extra[@]} -gt 0 || ${#srcs[@]} -gt 0 ]]; then
                echo "Error: -W, -f and compiler flags don't apply to a Makefile folder (they belong in the Makefile)" >&2; return 1
            fi
            _dev_make_info
            # Building means making the default target, unless that target runs,
            # tests or cleans (a Makefile whose first target is run or clean, or
            # whose all depends on run): then run builds through `make run`, and
            # the others build PROG if the Makefile names one.
            local pre dangerous=""
            [[ $mk_goal == @(run|clean|test|check|debug|install|distclean) ]] && dangerous=1
            for pre in "${mk_pre[@]}"; do [[ $pre == run ]] && dangerous=1; done
            if [[ -n $dangerous ]]; then
                if [[ $2 == runner && -n $mk_run && -z $out ]]; then return 0
                elif [[ -n $out || -n $mk_prog ]]; then command make --no-print-directory "${out:-$mk_prog}" >&2
                else
                    echo "Error: the Makefile's first target is '$mk_goal', so building would run it; put the build target first, or add PROG = name" >&2
                    return 1
                fi
            else
                # make's output on stderr, so `run > out.txt` keeps only the program's.
                command make --no-print-directory >&2
            fi
            ;;
    esac
}

# _dev_venv_python: the python of the nearest .venv or venv in this folder or a
# folder above, else python3 (with a note when one is there but broken).
_dev_venv_python() {
    local d v; d=$(builtin pwd -P)
    while :; do
        for v in "$d/.venv" "$d/venv"; do
            [[ -x $v/bin/python ]] && { echo "$v/bin/python"; return 0; }
            [[ -L $v/bin/python || -d $v/bin ]] && echo "Note: $v/bin/python is broken or missing; using python3" >&2
        done
        [[ $d == / || -z $d ]] && break
        d=${d%/*}; [[ -z $d ]] && d=/
    done
    _dev_need python3 python3 || return 1
    echo python3
}

# _dev_prog LANG: fill the caller's prog array with the command that runs the
# program just built (after _dev_build, which set out or rust_exe), and penv with
# any environment it needs (PYTHONPATH for a package).
_dev_prog() {
    case $1 in
        c|cpp) if [[ $out == */* ]]; then prog=("$out"); else prog=("./$out"); fi ;;
        rust)
            if [[ -n $rust_exe ]]; then prog=("$rust_exe")
            elif [[ -n $out ]]; then if [[ $out == */* ]]; then prog=("$out"); else prog=("./$out"); fi
            else echo "Error: cargo built no program here (a library crate?)" >&2; return 1; fi
            ;;
        python)
            local py f=$file abs=""
            py=$(_dev_venv_python) || return 1
            # A package (a folder with __main__.py, named or the current one) runs
            # as `python -m pkg` from above its outermost package, so relative
            # imports work (pkg/sub runs as pkg.sub).
            if [[ -n $f && -d $f ]]; then abs=$(command realpath -- "$f")
            elif [[ -z $f && -f __main__.py ]]; then abs=$(builtin pwd -P)
            fi
            if [[ -n $abs ]]; then
                local top=$abs mod=${abs##*/} where=""
                while [[ -f ${top%/*}/__init__.py && ${top%/*} != "$top" ]]; do top=${top%/*}; mod=${top##*/}.$mod; done
                if [[ $mod =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]]; then
                    # The name must lead to this folder, not to a standard module
                    # with the same name (a folder calendar/ without __init__.py
                    # loses to Python's own calendar).
                    where=$(PYTHONPATH="${top%/*}${PYTHONPATH:+:$PYTHONPATH}" "$py" -c 'import importlib.util as u, sys
s = u.find_spec(sys.argv[1])
print(((list(s.submodule_search_locations or []) or [s.origin or ""])[0]) if s else "")' "${top##*/}" 2>/dev/null) || where=""
                    if [[ $where == "$top" ]]; then
                        penv=("PYTHONPATH=${top%/*}${PYTHONPATH:+:$PYTHONPATH}"); prog=("$py" -m "$mod"); return 0
                    fi
                    echo "Note: '${top##*/}' is also the name of a standard Python module; running $abs/__main__.py by its path" >&2
                fi
                f=$abs/__main__.py   # not usable as a module name: run the file itself
            fi
            if [[ -z $f ]]; then
                if [[ -f main.py ]]; then f=main.py
                else
                    local -a pys=(); local p
                    while IFS= read -r -d '' p; do [[ $p == *.py ]] && pys+=("${p#./}"); done < <(_dev_list)
                    if [[ ${#pys[@]} -eq 1 ]]; then f=${pys[0]}
                    else echo "Error: several Python files here; name one: run ${pys[0]:-FILE.py}" >&2; return 1; fi
                fi
            fi
            [[ -f $f ]] || { echo "Error: '$f' not found" >&2; return 1; }
            prog=("$py" "$f")
            ;;
        make)
            local cand p; local -a found=()
            _dev_make_info
            # -o NAME, else the Makefile's PROG, else the default target when it is
            # a program file (main: main.c), else the one program among its
            # prerequisites (all: main). Never a guess from the folder's name.
            p=${out:-$mk_prog}
            if [[ -z $p ]]; then
                if [[ -n $mk_goal && -f $mk_goal && -x $mk_goal ]]; then p=$mk_goal
                else
                    for cand in "${mk_pre[@]}"; do [[ -f $cand && -x $cand ]] && found+=("$cand"); done
                    [[ ${#found[@]} -eq 1 ]] && p=${found[0]}
                fi
            fi
            [[ -n $p ]] || { echo "Error: can't tell which program the Makefile builds; add PROG = name to it, or a run: target, or use -o NAME" >&2; return 1; }
            [[ -f $p && -x $p ]] || { echo "Error: make didn't build ./$p" >&2; return 1; }
            if [[ $p == */* ]]; then prog=("$p"); else prog=("./$p"); fi
            ;;
    esac
}

# _dev_exec CMD...: run CMD with the caller's penv (environment assignments) when
# there are any. env can't run shell functions (_dev_make_run), so only then.
_dev_exec() { if [[ ${#penv[@]} -gt 0 ]]; then command env "${penv[@]}" "$@"; else "$@"; fi; }

# _dev_exit_line RC START: one dim line after a run (red when RC isn't 0), on
# stderr so `run > out.txt` keeps only the program's own output. A locale with a
# decimal comma writes EPOCHREALTIME as 12,5; awk wants 12.5.
_dev_exit_line() {
    local secs colour='\033[2m' end=${EPOCHREALTIME/,/.}
    secs=$(command awk -v a="${2/,/.}" -v b="$end" 'BEGIN { printf "%.2f", b - a }')
    [[ $1 != 0 ]] && colour='\033[0;31m'
    # In a terminal, a program whose last line has no newline ("Enter n: " then
    # EOF) would get the exit line glued on. Width-1 spaces then \r: at column 0
    # they fit and \r comes back; mid-line they wrap to a new line first.
    if [[ -t 2 ]]; then
        # The terminal's own width (stty asks it; COLUMNS can be stale after a
        # resize, and tput guesses 80 without TERM), else COLUMNS, else 80.
        local cols=""; read -r _ cols < <(command stty size <&2 2>/dev/null) || true
        [[ $cols =~ ^[0-9]+$ && $cols -gt 1 ]] || cols=${COLUMNS:-0}
        [[ $cols =~ ^[0-9]+$ && $cols -gt 1 ]] || cols=80
        printf '%*s\r' "$((cols - 1))" '' >&2
    fi
    echo -e "${colour}exit $1, ${secs} s\033[0m" >&2
}

# run: build (when needed) and run the program, in whatever language it is
run() {
    case "${1:-}" in
        -h|--help|-H)
            command cat <<'HELP'
Build (when needed) and run the program, in whatever language it is. VS Code's
Run button calls this too.

Usage: run [FILE] [OPTIONS] [-- EXTRA_COMPILER_FLAGS...] [-a PROGRAM_ARGS...]

Same language rules and options as ru (see ru -h), plus -i FILE to feed FILE to
the program's stdin. Then:
  C, C++, lone .rs   ./<name>
  Rust (Cargo)       the project's program, from target/
  Python             .venv/bin/python FILE when the folder has a .venv, else python3 FILE
                     (no FILE: main.py, or the only .py)
  Makefile           -o NAME when given; else make run when the Makefile has a run
                     target with a recipe; else the program it builds: its PROG, its
                     first target when that is a program, or the one program among
                     that target's prerequisites (never a guess from the folder's name)

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
    local -a srcs=() extra=() prog=() pargs=() penv=() mk_pre=()
    local rust_exe="" mk_done="" mk_goal="" mk_run="" mk_prog="" mk_args="" mk_shell=""
    _dev_parse "$@" || return 1
    _dev_refuse run v d || return 1
    if [[ -n $in_file && ! -f $in_file ]]; then echo "Error: input file '$in_file' not found" >&2; return 1; fi
    local lang; lang=$(_dev_pick_lang) || return 1
    # Mode runner only for a Makefile folder: there make run may do the building.
    if [[ $lang == make ]]; then _dev_build make runner || return 1; else _dev_build "$lang" run || return 1; fi
    [[ $lang == make ]] && _dev_make_info
    # A Makefile's own run target, unless -o names the program to run.
    if [[ -n $mk_run && -z $out ]]; then
        prog=(_dev_make_run)
    else
        _dev_prog "$lang" || return 1
    fi
    # Ctrl-C stops the program but not this function, so the exit line (130)
    # still shows; the shell's own INT trap, if any, comes back afterwards.
    local start=$EPOCHREALTIME rc=0 saved
    saved=$(trap -p INT); trap ':' INT
    if [[ -n $in_file ]]; then _dev_exec "${prog[@]}" "${pargs[@]}" < "$in_file" || rc=$?
    else _dev_exec "${prog[@]}" "${pargs[@]}" || rc=$?; fi
    if [[ -n $saved ]]; then eval "$saved"; else trap - INT; fi
    _dev_exit_line "$rc" "$start"
    return "$rc"
}

# rud: debug build, then open it in the debugger (lldb; gdb if lldb is missing; pdb for Python)
rud() {
    case "${1:-}" in
        -h|--help|-H)
            command cat <<'HELP'
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
    local -a srcs=() extra=() prog=() pargs=() penv=() mk_pre=()
    local rust_exe="" mk_done="" mk_goal="" mk_run="" mk_prog="" mk_args="" mk_shell=""
    _dev_parse "$@" || return 1
    _dev_refuse rud i v d || return 1
    opt=0
    local lang; lang=$(_dev_pick_lang) || return 1
    _dev_build "$lang" run || return 1
    _dev_prog "$lang" || return 1
    if [[ $lang == python ]]; then
        _dev_exec "${prog[0]}" -m pdb "${prog[@]:1}" "${pargs[@]}"
    elif command -v lldb &>/dev/null; then
        command lldb -- "${prog[@]}" "${pargs[@]}"
    else
        _dev_need gdb "lldb or gdb" || return 1
        echo "Note: lldb not found, using gdb" >&2
        command gdb --args "${prog[@]}" "${pargs[@]}"
    fi
}

# rund: debug build without sanitizers, then run under valgrind with a colourised report
rund() {
    case "${1:-}" in
        -h|--help|-H)
            command cat <<'HELP'
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

Program arguments go after -- (or after -a, which comes last).

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
    local -a srcs=() extra=() prog=() prog_args=() pargs=() penv=() mk_pre=()
    local rust_exe="" mk_done="" mk_goal="" mk_run="" mk_prog="" mk_args="" mk_shell=""
    _dev_parse "$@" || return 1
    _dev_refuse rund v d || return 1
    # For rund, everything after -- is the program's arguments, not compiler flags.
    prog_args=("${extra[@]}"); extra=(); opt=0
    local input_file=$in_file

    if [[ -n "$input_file" && ! -f "$input_file" ]]; then
        echo "Error: input file '$input_file' not found" >&2
        return 1
    fi

    local lang; lang=$(_dev_pick_lang) || return 1
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
    if [[ -f ${prog[0]} ]] && command grep -qa __asan_init "${prog[0]}"; then
        echo "Error: ${prog[0]} was built with AddressSanitizer, which clashes with valgrind." >&2
        echo "Build it without -fsanitize first (a mkmake Makefile: make clean && make SANITIZE=), then rund." >&2
        return 1
    fi

    # Prepare valgrind output
    local logfile
    logfile="valgrind_$(command date +"%Y%m%d-%H%M%S").log"
    local tmpfile
    tmpfile=$(_dev_tmp) || return 1
    # Removes the file when rund returns, then removes itself: a RETURN trap set
    # in a function otherwise stays set in the user's shell.
    # shellcheck disable=SC2064
    trap "command rm -f '$tmpfile'; trap - RETURN" RETURN

    # Build valgrind command
    local -a vcmd=(valgrind -s --leak-check=full --track-origins=yes "${prog[@]}")
    vcmd+=("${prog_args[@]}" "${pargs[@]}")

    printf '\033[0;34m[valgrind]\033[0m %s\n' "$(_dev_show "${vcmd[@]}")"
    echo ""

    # Run valgrind — stderr has the report, stdout has program output. The status
    # is kept (|| vrc=) so a user's `set -e` can't end their shell here, and so a
    # Ctrl-C (130) is told apart from a finished run.
    local vrc=0
    if [[ -n "$input_file" ]]; then
        "${vcmd[@]}" < "$input_file" 2>|"$tmpfile" || vrc=$?
    else
        "${vcmd[@]}" 2>|"$tmpfile" || vrc=$?
    fi

    # Save raw output
    command cp -- "$tmpfile" "$logfile" || echo "Note: couldn't save the log to $logfile" >&2

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
            else echo -e "  ${RED}${BOLD}${content}${RESET}"; leaks=$((leaks + 1)); fi
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
    if [[ $vrc == 130 ]] || command grep -q 'default action of signal 2 (SIGINT)' "$tmpfile"; then
        echo -e "  ${RED}${BOLD}RESULT: FAIL${RESET} ${RED}— interrupted (Ctrl-C) before the program finished${RESET}"
    elif [[ -z $summary ]]; then
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
        command cat "$args_file"
        echo
    else
        echo -e "${ITALIC}(none)${RESET}"
    fi

    echo -e "${YELLOW}Input:${RESET}"
    if [[ -r "$in_file" ]]; then
        command cat "$in_file"
        echo
    else
        echo -e "${ITALIC}(none)${RESET}"
    fi

    echo -e "${BLUE}${BOLD}Expected:${RESET}"
    command cat "$expect_file"
    echo

    echo -e "${BLUE}${BOLD}Actual:${RESET}"
    command cat "$TEMPFILE"
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
    TEMPFILE=$(_dev_tmp) || return 1
    # shellcheck disable=SC2064
    trap "command rm -f '$TEMPFILE'; trap - RETURN" RETURN

    local stem expect_file args_file in_file
    local -a argv
    while IFS= read -r stem || [[ -n "$stem" ]]; do
        # Skip blank lines
        [[ -z "$stem" ]] && continue

        total=$((total + 1))   # not (( total++ )): that is status 1 at 0, which ends a set -e shell
        expect_file="${stem}.expect"
        args_file="${stem}.args"
        in_file="${stem}.in"

        if [[ ! -r "$expect_file" ]]; then
            echo "Error: missing or unreadable expected output file: $expect_file" >&2
            return 1
        fi

        # Arguments from .args, split on spaces and newlines but never globbed
        # (an argument * stays *).
        argv=()
        if [[ -r "$args_file" ]]; then
            IFS=$' \t\n' read -r -d '' -a argv < "$args_file" || true
        fi

        # Run program with optional stdin redirection
        local prc=0
        if [[ -r "$in_file" ]]; then
            "${PROGRAM[@]}" "${argv[@]}" < "$in_file" >| "$TEMPFILE" 2>&1 || prc=$?
        else
            "${PROGRAM[@]}" "${argv[@]}" >| "$TEMPFILE" 2>&1 || prc=$?
        fi

        # A program killed by a signal (a crash, abort) fails even when its
        # output matched up to that point; an ordinary non-zero exit doesn't.
        # 131 QUIT, 132 ILL, 134 ABRT, 135 BUS, 136 FPE, 137 KILL, 139 SEGV; an
        # exit(-1) (255) or any other code is the program's own and only output counts.
        if [[ $prc == @(131|132|134|135|136|137|139) ]]; then
            failed=$((failed + 1))
            echo -e "${RED}${BOLD}x Test failed:${RESET} ${UNDERLINE}$stem${RESET} (crashed, signal $(( prc - 128 )))"
            _run_suite_details "$stem"
        elif command diff "$TEMPFILE" "$expect_file" > /dev/null 2>&1; then
            echo -e "${GREEN}${BOLD}> Passed:${RESET} $stem"
            if [[ "$VERBOSE" -eq 1 ]]; then
                _run_suite_details "$stem"
            fi
        else
            failed=$((failed + 1))
            echo -e "${RED}${BOLD}x Test failed:${RESET} ${UNDERLINE}$stem${RESET}"
            _run_suite_details "$stem"
        fi
        if [[ -n ${dev_int:-} ]]; then echo -e "${RED}${BOLD}Interrupted (Ctrl-C)${RESET}" >&2; return 130; fi
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
            command cat <<'HELP'
Build the program (any language, see ru -h) and run every test case here.

Test cases are file stems: for a stem "foo", the runner looks for
  foo.in       (stdin input; cases are found by their .in)
  foo.expect   (expected stdout and stderr together, required)
  foo.args     (command-line arguments, optional)
A test whose program crashes (segfault, abort and other crash signals) fails even
if its output matched; an ordinary exit code, even exit(-1), doesn't count.
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
    local -a srcs=() extra=() prog=() pargs=() penv=() mk_pre=()
    local rust_exe="" mk_done="" mk_goal="" mk_run="" mk_prog="" mk_args="" mk_shell=""
    _dev_parse "$@" || return 1
    _dev_refuse rut a i || return 1

    if [[ ! -d "$test_dir" ]]; then
        echo "Error: test directory '$test_dir' not found" >&2
        return 1
    fi

    local lang; lang=$(_dev_pick_lang) || return 1
    _dev_build "$lang" run || return 1
    _dev_prog "$lang" || return 1
    [[ ${#penv[@]} -gt 0 ]] && prog=(env "${penv[@]}" "${prog[@]}")

    # Gather test stems from *.in files in the test directory
    local stems
    stems="$(compgen -G "$test_dir/*.in" 2>/dev/null | command sed 's/\.in$//' | command sort -u)"

    if [[ -z "$stems" ]]; then
        local hint=""
        [[ $test_dir == . && -n $(compgen -G "tests/*.in" 2>/dev/null) ]] && hint=" (the tests are in tests/: rut -d tests)"
        echo "Error: no *.in files found in $test_dir$hint" >&2
        return 1
    fi

    # Build a temp suite file for _run_suite
    local suite
    suite=$(_dev_tmp) || return 1
    printf '%s\n' "$stems" >| "$suite"

    # Ctrl-C stops the running test and then the whole suite (dev_int, read by
    # _run_suite), so the suite file is still removed and the trap restored.
    local dev_int="" saved; saved=$(trap -p INT); trap 'dev_int=1' INT
    # shellcheck disable=SC2086  # $verbose is empty or -v
    _run_suite $verbose "$suite" "${prog[@]}"
    local rc=$?
    if [[ -n $saved ]]; then eval "$saved"; else trap - INT; fi

    command rm -f -- "$suite"
    return "$rc"
}

# mkt: create test stem files (.in and .expect; .args with -a)
mkt() {
    case "${1:-}" in
        -h|--help|-H)
            command cat <<'EOF'
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
        if [[ "$with_args" -eq 1 ]]; then
            command touch -- "${stem}.in" "${stem}.expect" "${stem}.args" || { echo "Error: couldn't create the files for '$stem'" >&2; return 1; }
            echo "Created: ${stem}.in  ${stem}.expect  ${stem}.args"
        else
            command touch -- "${stem}.in" "${stem}.expect" || { echo "Error: couldn't create the files for '$stem'" >&2; return 1; }
            echo "Created: ${stem}.in  ${stem}.expect"
        fi
        count=$((count + 1))
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
            command cat <<'HELP'
Write a Makefile for the C or C++ files in this folder, with the same build as
run and VS Code. Refuses to overwrite an existing Makefile.

Targets: all (the default: build), run (make run ARGS="5 10"), debug (lldb, or
gdb), test (every .in/.expect case, like rut; a crash fails), clean. The program
is named after the folder (made safe for make: test becomes test-prog, other
characters become -). `make SANITIZE=` builds without the sanitizers, for
valgrind. Needs a folder of C or C++ files (not both) whose names have no
spaces or # $ : % \ (make can't handle those).

Usage: mkmake
HELP
            return 0
            ;;
    esac
    if [[ -f Makefile || -f makefile || -f GNUmakefile ]]; then
        echo "Error: Makefile already exists" >&2
        return 1
    fi
    # The C or C++ files here, never both (one Makefile, one compiler).
    local f k has_c="" has_cpp=""
    local -a bad=()
    while IFS= read -r -d '' f; do
        k=$(_dev_lang_of "$f")
        case $k in c) has_c=1 ;; cpp) has_cpp=1 ;; *) continue ;; esac
        # make splits names on spaces and treats # $ : % \ specially.
        [[ ${f#./} == *[[:space:]\#\$:%\\]* ]] && bad+=("${f#./}")
    done < <(_dev_list)
    if [[ -n $has_c && -n $has_cpp ]]; then echo "Error: mkmake needs a folder of C or C++ files, not both" >&2; return 1; fi
    if [[ -z $has_c && -z $has_cpp ]]; then echo "Error: mkmake writes Makefiles for C and C++, and there are no C or C++ files here" >&2; return 1; fi
    if [[ ${#bad[@]} -gt 0 ]]; then
        echo "Error: make can't handle a source file name with a space or # \$ : % \\ in it; rename: ${bad[*]}" >&2
        return 1
    fi
    local lang=c; [[ -n $has_cpp ]] && lang=cpp
    # The program is named after the folder, made safe for make: other characters
    # become -, no leading - or ., and never a target name the Makefile itself uses.
    local prog; prog=$(_dev_name "$lang"); prog=${prog//[^A-Za-z0-9._-]/-}
    while [[ $prog == [-.]* ]]; do prog=${prog#?}; done
    [[ -n $prog ]] || prog=program
    # Never a name the Makefile itself uses, or one that looks like a source file.
    [[ $prog == @(all|run|debug|test|clean|Makefile|makefile|GNUmakefile) || -n $(_dev_lang_of "$prog") || $prog == *.[hH]* ]] && prog=$prog-prog
    local cc cvar flags fvar srcs
    case $lang in
        c)   cvar=CC;  fvar=CFLAGS;   flags=-std=gnu17;   srcs='$(wildcard *.c)'
             if command -v clang &>/dev/null; then cc=clang; else _dev_need gcc "clang or gcc" || return 1; cc=gcc; fi ;;
        cpp) cvar=CXX; fvar=CXXFLAGS; flags=-std=gnu++20; srcs='$(wildcard *.cpp *.cc *.cxx *.C *.CPP *.Cpp *.CC *.CXX *.c++ *.C++)'
             if command -v clang++ &>/dev/null; then cc=clang++; else _dev_need g++ "clang or g++" || return 1; cc=g++; fi ;;
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
        echo "# Every <stem>.in through the program, compared with <stem>.expect (stdout and"
        echo "# stderr; arguments from <stem>.args), like rut. A crash fails even with matching output."
        echo "test: \$(PROG)"
        printf '\t@set -- *.in; [ -e "$$1" ] || { echo "no .in files here (mkt NAME makes one)"; exit 1; }; set -f; \\\n'
        printf '\tpass=0; fail=0; out=$$(mktemp); for t in "$$@"; do s="$${t%%.in}"; \\\n'
        printf '\t  ./$(PROG) $$(cat "$$s.args" 2>/dev/null) < "$$t" > "$$out" 2>&1; rc=$$?; \\\n'
        printf '\t  case $$rc in 131|132|134|135|136|137|139) echo "FAIL $$s (crashed, exit $$rc)"; fail=$$((fail+1)); continue;; esac; \\\n'
        printf '\t  if diff -q "$$out" "$$s.expect" >/dev/null; then echo "ok   $$s"; pass=$$((pass+1)); \\\n'
        printf '\t  else echo "FAIL $$s"; fail=$$((fail+1)); fi; done; rm -f "$$out"; \\\n'
        printf '\techo "$$pass passed, $$fail failed"; [ $$fail -eq 0 ]\n'
        echo
        echo "clean:"
        printf '\trm -f $(PROG)\n'
        echo
        echo ".PHONY: all run debug test clean"
    } >| Makefile
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

