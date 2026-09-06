#!/usr/bin/env bash
# lib/dev.sh — C programming toolchain helpers (lazy-loaded on first use).
#   ru    compile with gcc (C99, -Wall -Wextra -Wpedantic, -g)
#   run   compile and execute ./myprogram
#   rud   debug build (-O0)
#   rund  debug build, then run under valgrind with a colourised report
#   rut   compile and run the .in/.expect/.args test suite
#   mkt   create test stems
# Dependencies: gcc, make, valgrind  (install.sh --with-dev)

# Requires: gcc, valgrind (for rund)
# Compiles and runs C programs using gcc.
# Test runner expects .in (stdin), .expect (expected output), and
# optionally .args (command-line arguments) files per test stem.
#
# Quirks:
#   • This file is never sourced at startup: bashrc installs stubs for the six
#     public functions and the first call (or Tab) sources it — see
#     _bashrc_lazy in lib/core.sh. Adding a new public function here means adding
#     it to that `_bashrc_lazy dev …` line too, or it will not exist until
#     something else triggers the load.
#   • `run` is also the name of a helper inside install.sh; they never meet
#     (install.sh is executed, not sourced), but don't source install.sh.
#   • Colour codes are locals per function, not globals — keeps `set | grep`
#     and the environment clean.

# ru: compile C source files with gcc
ru() {
    case "$1" in
        -h|--help|-H)
            cat <<'EOF'
Compile C source files with gcc (C99, all warnings by default).

Auto-detects all .c files in the current directory, or specify one or
more source/object files with -f. Compiles to ./myprogram.

Usage: ru [OPTIONS] [-- EXTRA_GCC_FLAGS...]

Options:
  -h, --help, -H   Show this help message
  -f FILE [FILE2..] Compile specific .c and/or .o files (at least one required)
  -O LEVEL          Optimization level (default: 0)
  -W [FLAGS]        Override warnings: empty = no warnings,
                    comma-separated list = only those (e.g. all,extra)
  -o NAME           Output binary name (default: myprogram)

Anything after -- is passed directly to gcc.

Default warnings: -Wall -Wextra -Wpedantic

Examples:
  ru                          Auto-detect .c files, compile with all warnings
  ru -f main.c                Compile only main.c
  ru -f main.c utils.c io.c   Compile specific files
  ru -f main.c lib.o          Compile main.c and link with lib.o
  ru -O2                      Compile with -O2 instead of -O0
  ru -W                       Compile with no warning flags
  ru -W all,error             Compile with only -Wall -Werror
  ru -- -DDEBUG               Pass extra flags to gcc
EOF
            return 0
            ;;
    esac

    local opt_level="0"
    local warnings="default"
    local output="myprogram"
    local -a sources=()
    local -a extra_flags=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f)
                shift
                # Collect all following args that end in .c (until next flag or --)
                while [[ $# -gt 0 && "$1" != -* ]]; do
                    sources+=("$1"); shift
                done
                if [[ ${#sources[@]} -eq 0 ]]; then
                    echo "Error: -f requires at least one .c or .o file" >&2
                    return 1
                fi
                ;;
            -O)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "Error: -O requires a level (0, 1, 2, 3, s, g)" >&2
                    return 1
                fi
                opt_level="$2"; shift 2
                ;;
            -W)
                # -W with no argument or next arg is a flag = no warnings
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    warnings="none"
                    shift
                else
                    warnings="$2"; shift 2
                fi
                ;;
            -o)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "Error: -o requires an output name" >&2
                    return 1
                fi
                output="$2"; shift 2
                ;;
            --)
                shift
                extra_flags+=("$@")
                break
                ;;
            *)
                echo "Error: unknown option '$1'. Use -h for help." >&2
                return 1
                ;;
        esac
    done

    if ! command -v gcc &>/dev/null; then
        echo "Error: gcc not found. Install it with: sudo nala install gcc" >&2
        return 1
    fi

    # Build the source file list (auto-detect if -f was not used)
    if [[ ${#sources[@]} -eq 0 ]]; then
        local f
        for f in *.c; do
            [[ -f "$f" ]] && sources+=("$f")
        done
        if [[ ${#sources[@]} -eq 0 ]]; then
            echo "Error: no .c files found in $(pwd)" >&2
            return 1
        fi
    else
        # Validate all specified files exist
        local f
        for f in "${sources[@]}"; do
            if [[ ! -f "$f" ]]; then
                echo "Error: '$f' not found" >&2
                return 1
            fi
        done
    fi

    # Build gcc command
    local -a cmd=(gcc -std=c99 "-O${opt_level}" -g)

    # Warning flags
    case "$warnings" in
        default) cmd+=(-Wall -Wextra -Wpedantic) ;;
        none)    ;;  # no warning flags
        *)
            local w
            IFS=',' read -ra _warn_arr <<< "$warnings"
            for w in "${_warn_arr[@]}"; do
                cmd+=("-W${w}")
            done
            unset _warn_arr
            ;;
    esac

    cmd+=("${extra_flags[@]}")
    cmd+=("${sources[@]}")
    cmd+=(-o "$output")

    echo -e "\033[0;34m[compile]\033[0m ${cmd[*]}"
    "${cmd[@]}"
}

# run: compile and execute
run() {
    case "$1" in
        -h|--help|-H)
            cat <<'EOF'
Compile C source files and run the resulting program.

Usage: run [OPTIONS] [-- EXTRA_GCC_FLAGS...]

Options:
  -h, --help, -H   Show this help message
  -f FILE [FILE2..] Compile specific .c/.o files
  (all other options are passed to ru)

Examples:
  run                        Compile and run
  run -f main.c utils.c      Compile specific files and run
EOF
            return 0
            ;;
    esac
    # honour -o NAME so we run what we just built
    local a prev='' out=myprogram
    for a in "$@"; do [[ $prev == -o ]] && out=$a; [[ $a == -- ]] && break; prev=$a; done
    ru "$@" && "./$out"
}

# rud: compile C source files for debugging
rud() {
    case "$1" in
        -h|--help|-H)
            cat <<'EOF'
Compile C source files for debugging (no optimization, debug symbols).

Uses gcc -std=c99 -O0 -g with all warnings by default.

Usage: rud [OPTIONS] [-- EXTRA_GCC_FLAGS...]

Options:
  -h, --help, -H   Show this help message
  -f FILE [FILE2..] Compile specific .c/.o files
  -W [FLAGS]        Override warnings (see ru -h for details)
  -o NAME           Output binary name (default: myprogram)

Anything after -- is passed directly to gcc.

Examples:
  rud                                 Debug build of all .c files
  rud -f main.c utils.c               Debug build of specific files
  rud -- -fsanitize=address           Build with AddressSanitizer
EOF
            return 0
            ;;
    esac

    # Force -O0 for debug builds by stripping any -O from args and prepending -O 0
    local -a args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -O) shift 2 ;;  # discard any optimization override
            *)  args+=("$1"); shift ;;
        esac
    done

    ru -O 0 "${args[@]}"
}

# rund: compile for debug and run under valgrind
rund() {
    case "$1" in
        -h|--help|-H)
            cat <<'EOF'
Compile for debug and run under valgrind with leak checking.

Compiles using rud (debug build), then runs the program under valgrind
with --leak-check=full and --track-origins=yes. Output is colorized for
readability. Raw valgrind output is saved to valgrind_YYYYMMDD-HHMMSS.log.

Usage: rund [OPTIONS] [-- PROGRAM_ARGS...]

Options:
  -h, --help, -H   Show this help message
  -f FILE [FILE2..] Compile specific .c/.o files
  -i INPUT          Redirect INPUT file to program's stdin
  -o NAME           Output binary name (default: myprogram)
  -W [FLAGS]        Override warnings (see ru -h for details)

Program arguments go after --:

Examples:
  rund                           Build and valgrind
  rund -f main.c utils.c         Build specific files and valgrind
  rund -- arg1 arg2              Pass args to program
  rund -i input.txt              Redirect stdin from file
  rund -i input.txt -- 5 10      Stdin + program args
EOF
            return 0
            ;;
    esac

    local input_file=""
    local output="myprogram"
    local -a compile_args=()
    local -a prog_args=()
    local parsing_prog=0

    while [[ $# -gt 0 ]]; do
        if [[ "$parsing_prog" -eq 1 ]]; then
            prog_args+=("$1"); shift
            continue
        fi
        case "$1" in
            -i)
                if [[ -z "$2" ]]; then
                    echo "Error: -i requires an input file" >&2
                    return 1
                fi
                input_file="$2"; shift 2
                ;;
            -o)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "Error: -o requires an output name" >&2
                    return 1
                fi
                output="$2"
                compile_args+=(-o "$2"); shift 2
                ;;
            -f)
                compile_args+=(-f)
                shift
                # Pass all non-flag args as files
                while [[ $# -gt 0 && "$1" != -* ]]; do
                    compile_args+=("$1"); shift
                done
                ;;
            -W)
                # -W with no argument or next arg is a flag = no warnings
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    compile_args+=(-W)
                    shift
                else
                    compile_args+=(-W "$2"); shift 2
                fi
                ;;
            --)
                shift; parsing_prog=1
                ;;
            *)
                echo "Error: unknown option '$1'. Use -h for help." >&2
                return 1
                ;;
        esac
    done

    if [[ -n "$input_file" && ! -f "$input_file" ]]; then
        echo "Error: input file '$input_file' not found" >&2
        return 1
    fi

    if ! command -v valgrind &>/dev/null; then
        echo "Error: valgrind not found. Install it with: sudo nala install valgrind" >&2
        return 1
    fi

    # Compile
    rud "${compile_args[@]}" || return 1

    # Prepare valgrind output
    local logfile
    logfile="valgrind_$(date +"%Y%m%d-%H%M%S").log"
    local tmpfile
    tmpfile="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$tmpfile'" RETURN

    # Build valgrind command
    local -a vcmd=(valgrind -s --leak-check=full --track-origins=yes "./$output")
    vcmd+=("${prog_args[@]}")

    echo -e "\033[0;34m[valgrind]\033[0m ${vcmd[*]}"
    echo ""

    # Run valgrind — stderr has the report, stdout has program output
    if [[ -n "$input_file" ]]; then
        "${vcmd[@]}" < "$input_file" 2>"$tmpfile"
    else
        "${vcmd[@]}" 2>"$tmpfile"
    fi

    # Save raw output
    cp "$tmpfile" "$logfile"

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
    local line content errors=0 leaks=0
    while IFS= read -r line; do
        content=${line#==*== }                       # strip the ==PID== prefix

        case $content in
            'HEAP SUMMARY'*|'LEAK SUMMARY'*|'ERROR SUMMARY'*)
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
    if [[ "$errors" -eq 0 && "$leaks" -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}RESULT: PASS${RESET} ${GREEN}— no errors, no leaks${RESET}"
    elif [[ "$errors" -eq 0 ]]; then
        echo -e "  ${YELLOW}${BOLD}RESULT: LEAKS${RESET} ${YELLOW}— no errors, but $leaks leak category(s) detected${RESET}"
    else
        echo -e "  ${RED}${BOLD}RESULT: FAIL${RESET} ${RED}— $errors error(s), $leaks leak category(s)${RESET}"
    fi
    echo -e "  ${DIM}Log saved: ${logfile}${RESET}"
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════${RESET}"
}

# _run_suite: inlined test-suite runner (replaces ~/testing/runSuite.sh)
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

    if [[ "$#" -ne 2 ]]; then
        echo "Error: _run_suite expects 2 arguments: _run_suite [-v] <suite-file> <program>" >&2
        return 1
    fi

    local SUITE_FILE="$1"
    local PROGRAM="$2"

    if [[ ! -r "$SUITE_FILE" ]]; then
        echo "Error: suite file '$SUITE_FILE' not found or unreadable" >&2
        return 1
    fi

    if [[ ! -x "$PROGRAM" ]]; then
        echo "Error: program '$PROGRAM' not found or not executable" >&2
        return 1
    fi

    local TEMPFILE
    TEMPFILE="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$TEMPFILE'" RETURN

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
        if [[ -r "$in_file" ]]; then
            "$PROGRAM" "${argv[@]}" < "$in_file" > "$TEMPFILE" 2>&1
        else
            "$PROGRAM" "${argv[@]}" > "$TEMPFILE" 2>&1
        fi

        if diff "$TEMPFILE" "$expect_file" > /dev/null 2>&1; then
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

# rut: compile and run the test suite
rut() {
    case "$1" in
        -h|--help|-H)
            cat <<'EOF'
Compile C source files and run all test cases in the current directory.

Test cases are defined by file stems: for a stem "foo", the runner looks for:
  foo.in       (stdin input, optional)
  foo.expect   (expected output, required)
  foo.args     (command-line arguments, optional)

Usage: rut [-h|--help] [-v] [-d DIR] [-f FILE...] [-- EXTRA_GCC_FLAGS...]

Options:
  -h, --help, -H   Show this help message
  -v                Verbose: show details for passing tests too
  -d DIR            Look for test files (.in/.expect) in DIR instead of cwd
  -f FILE [FILE2..] Compile specific .c/.o files

Anything after -- is passed directly to gcc via ru.

Examples:
  rut               Compile and run all tests
  rut -v            Verbose output for all tests
  rut -d tests      Use test files from ./tests/
  rut -v -f main.c utils.c   Compile specific files, verbose test run
  rut -- -DDEBUG    Compile with -DDEBUG and run tests
EOF
            return 0
            ;;
    esac

    local verbose_arg=""
    local compile_args=()
    local test_dir="."

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v)
                verbose_arg="-v"
                shift
                ;;
            -d)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "Error: -d requires a directory" >&2
                    return 1
                fi
                test_dir="$2"; shift 2
                ;;
            -f)
                compile_args+=(-f)
                shift
                while [[ $# -gt 0 && "$1" != -* ]]; do
                    compile_args+=("$1"); shift
                done
                ;;
            --)
                shift
                compile_args+=(-- "$@")
                break
                ;;
            *)
                echo "Error: unknown option '$1'. Use -h for help." >&2
                return 1
                ;;
        esac
    done

    if [[ ! -d "$test_dir" ]]; then
        echo "Error: test directory '$test_dir' not found" >&2
        return 1
    fi

    # Compile
    ru "${compile_args[@]}" || return 1

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

    _run_suite $verbose_arg "$suite" ./myprogram
    local rc=$?

    rm -f "$suite"
    return "$rc"
}

# mkt: create test stem files (.in and .expect)
mkt() {
    case "$1" in
        -h|--help|-H)
            cat <<'EOF'
Create test case file pairs for the test runner.

Usage: mkt <stem> [stem2...]

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

# Tab completions for C programming functions
_ru_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -f) COMPREPLY=($(compgen -f -X '!*.@(c|o)' -- "$cur")); return ;;
        -O) COMPREPLY=($(compgen -W "0 1 2 3 s g" -- "$cur")); return ;;
        -W) COMPREPLY=($(compgen -W "all extra error pedantic all,extra all,extra,error" -- "$cur")); return ;;
        -o) COMPREPLY=($(compgen -f -- "$cur")); return ;;
    esac
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-h --help -H -f -O -W -o --" -- "$cur"))
        return
    fi
    # Default to .c/.o file completion
    COMPREPLY=($(compgen -f -X '!*.@(c|o)' -- "$cur"))
}
complete -F _ru_completions ru run

_rut_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -f) COMPREPLY=($(compgen -f -X '!*.@(c|o)' -- "$cur")); return ;;
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
        -f) COMPREPLY=($(compgen -f -X '!*.@(c|o)' -- "$cur")); return ;;
        -W) COMPREPLY=($(compgen -W "all extra error pedantic all,extra all,extra,error" -- "$cur")); return ;;
        -o) COMPREPLY=($(compgen -f -- "$cur")); return ;;
    esac
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-h --help -H -f -W -o --" -- "$cur"))
        return
    fi
    COMPREPLY=($(compgen -f -X '!*.@(c|o)' -- "$cur"))
}
complete -F _rud_completions rud

_rund_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -f) COMPREPLY=($(compgen -f -X '!*.@(c|o)' -- "$cur")); return ;;
        -i) COMPREPLY=($(compgen -f -- "$cur")); return ;;
        -W) COMPREPLY=($(compgen -W "all extra error pedantic all,extra all,extra,error" -- "$cur")); return ;;
        -o) COMPREPLY=($(compgen -f -- "$cur")); return ;;
    esac
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-h --help -H -f -i -o -W --" -- "$cur"))
        return
    fi
    COMPREPLY=($(compgen -f -X '!*.@(c|o)' -- "$cur"))
}
complete -F _rund_completions rund

_mkt_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-h --help -H -a" -- "$cur"))
    fi
}
complete -F _mkt_completions mkt

