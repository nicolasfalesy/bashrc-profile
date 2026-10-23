# Multi-language dev commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ru run rud rund rut mkt` (and new `mkmake`) work for C, C++, Rust, Python and Makefile folders, matching VS Code's Run button.

**Architecture:** `lib/dev.sh` gains a small private layer (`_dev_*`) that parses the shared options, detects the language, builds, and produces the command that runs the program. Each public command becomes a thin wrapper over that layer; the valgrind report and `_run_suite` keep their code and only take a command array instead of `./myprogram`.

**Tech Stack:** bash 5, clang/gcc, clang++/g++, cargo/rustc, python3, make, lldb/gdb, valgrind.

**Spec:** `docs/superpowers/specs/2026-10-22-multi-language-run-design.md`

## Global Constraints

- C flags: `-std=c17 -Wall -Wextra -g -O0 -fsanitize=address,undefined` and `-lm` last; C++ `-std=c++20`, same flags. gcc/g++ fallback when clang/clang++ is missing.
- `rund` builds without `-fsanitize`.
- Detection order: named file, Makefile/makefile/GNUmakefile, Cargo.toml here or above, then `.c`, C++ (`.cpp .cc .cxx`), `.py`. Mixed kinds stop with `This folder has <A> and <B> files; name one: run <example>`.
- Program name: named file's stem; else folder basename; `-o NAME` wins.
- Stamps in `${XDG_CACHE_HOME:-$HOME/.cache}/bashrc-profile/run/`.
- Exit line: dim `exit N, S.SS s`, red when N≠0; `run` returns N.
- Old options keep working: `-f`, `-O`, `-W`, `-o`, `-i` (rund), `-v` `-d` (rut), `-a` (mkt); `--` = compiler flags except `rund` (program args).
- Missing tool: one line `Error: <tool> not found. Install it with your package manager (package: <pkg>)`.
- The repo is public: no personal paths, hosts or names in code, tests or docs.

## Review Focus

- A folder or file name with spaces ("My Course/sq 1.c") builds, runs and tests. → Task 2 test `spaces`.
- Typed input reaches the program under `run` (stdin passes through the timing wrapper). → Task 3 test `stdin`.
- Every old invocation still works: `ru -f a.c b.c`, `run -o x`, `rut -- -DX`, `rund -i in -- 1 2`. → Tasks 2-5 tests `compat_*`.
- Running from `src/` inside a Cargo project finds the project. → Task 3 test `rust_subdir`.
- A named file beats a Makefile in the same folder (`run sq.c` with a Makefile present). → Task 1 test `file_beats_make`.

---

### Task 1: Test harness, detection and naming

**Files:**
- Create: `tests/dev.sh`
- Modify: `tests/smoke.sh` (add `tests/dev.sh` to the syntax list line 23, the shellcheck list line 33, and run it like `claude-account.sh` near line 191)
- Modify: `lib/dev.sh` (new private section after the header comment)

**Interfaces:**
- Produces: `_dev_detect [FILE]` → prints one of `c cpp rust python make`; returns 1 with the spec's message on mixed/none.
- Produces: `_dev_name LANG [FILE]` → prints the program name (stem or folder basename).
- Produces: test helpers in `tests/dev.sh`: `ok NAME`, `bad NAME`, `check NAME CMD…`, a temp root `$T` under `${TMPDIR:-/tmp}`, sources `lib/dev.sh` directly; exits non-zero on any failure; prints `N passed, M failed`.

- [ ] **Step 1: Write failing tests** `detect_c` (folder with `a.c` → `c`), `detect_cpp` (`a.cpp`), `detect_py` (`a.py`), `detect_make` (Makefile + `a.c` → `make`), `detect_rust` (Cargo.toml → `rust`), `file_beats_make` (`_dev_detect sq.c` with Makefile → `c`), `mixed` (`a.c` + `b.py` → status 1, stderr contains `This folder has C and Python files`), `name_file` (`_dev_name c sq.c` → `sq`), `name_folder` (folder `proj` with `a.c b.c` → `proj`).
- [ ] **Step 2: Run** `bash tests/dev.sh` → FAIL (`_dev_detect: command not found`).
- [ ] **Step 3: Implement** `_dev_detect` and `_dev_name` (Cargo.toml search walks up with `while [[ $d != / ]]`).
- [ ] **Step 4: Run** `bash tests/dev.sh` → all pass; `bash tests/smoke.sh omarchy` → passes.
- [ ] **Step 5: Commit** `git commit -m "dev: language detection and program naming, with tests"`

### Task 2: Option parsing and C/C++ builds (ru)

**Files:** Modify `lib/dev.sh` (`ru`, new `_dev_parse`, `_dev_build_cc`, `_dev_stamp_*`), `tests/dev.sh`.

**Interfaces:**
- Produces: `_dev_parse "$@"` fills the caller's locals (dynamic scope): `file` (positional source or ""), `-a srcs` (from `-f`), `opt` (default 0), `warn` (`default|none|LIST`), `out`, `-a extra` (after `--`), `in_file`, `verbose`, `test_dir`; unknown option → `Error: unknown option '<x>'. Use -h for help.` status 1. Callers declare those locals first.
- Produces: `_dev_build_cc LANG MODE` (MODE `run|plain`) → builds into `./$out`, prints `[compile] <cmd>` only when it compiles, skips when the stamp matches; status of the compiler.
- Produces: `_dev_stamp_ok OUT CMD` / `_dev_stamp_write OUT CMD`; stamp file name is the sha1 of the absolute output path.
- `ru [FILE] [opts]` → `_dev_detect` then the language's build (Tasks 2-3).

- [ ] **Step 1: Write failing tests** `c_build` (`ru sq.c` makes `./sq`, compile line has `-std=c17` and `-fsanitize=address,undefined`), `c_skip` (second `ru sq.c` prints no `[compile]`), `c_header` (touch `x.h` → rebuilds), `c_flags_change` (`ru sq.c -O 2` after `ru sq.c` → rebuilds), `cpp_build` (`ru a.cpp` uses `-std=c++20`), `gcc_fallback` (PATH without clang → compile line starts with `gcc`), `spaces` (folder `My Course`, file `sq 1.c` → `./sq 1` exists), `compat_f` (`ru -f a.c b.c` builds `./<folder>`), `compat_W` (`ru -W` has no `-Wall`).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `_dev_parse`, `_dev_build_cc`, stamps; rewrite `ru` (help text lists the languages and the positional file).
- [ ] **Step 4: Run** `bash tests/dev.sh` → pass.
- [ ] **Step 5: Commit** `git commit -m "dev: ru builds C and C++ with clang, skips unchanged builds"`

### Task 3: Rust, Python, Make and run

**Files:** Modify `lib/dev.sh` (`run`, `_dev_build`, `_dev_prog`, `_dev_exit_line`), `tests/dev.sh`.

**Interfaces:**
- Produces: `_dev_build LANG MODE` → dispatches: c/cpp `_dev_build_cc`; rust `cargo build -q` (+`--release` when opt≠0; refuses `-W`/`extra` with `Error: -W and compiler flags don't apply to Rust`); lone `.rs` outside Cargo → `rustc -g -o "$out"`; python no-op; make `make`.
- Produces: `_dev_prog LANG MODE` → fills caller's `-a prog` with the program command: `./"$out"`; rust: the `"executable"` path from `cargo build --message-format=json` (grep, no jq); python: `.venv/bin/python FILE` else `python3 FILE`; make: `./<folder>`.
- Produces: `_dev_exit_line RC START` (START = `$EPOCHREALTIME` before the program).
- `run` → build, then for make with a `run` target (`make -n run` succeeds) `make run`, else `"${prog[@]}"`; prints the exit line; returns the program's code.

- [ ] **Step 1: Write failing tests** `run_c` (`echo 12 | run sq.c` output has `144` and `exit 0`), `stdin` (same, proves input), `run_exit_code` (program `return 3` → `run` status 3 and line contains `exit 3`), `run_py` (`run a.py`), `py_venv` (fake `.venv/bin/python` script that echoes `VENV` → used), `run_make_target` (Makefile with `run:` echo `MADE`), `run_make_plain` (Makefile builds `./<folder>`, no run target → runs it), `rust_run` and `rust_subdir` (skip with `skip` line when no cargo; `cargo new` in `$T`, run from `src/`), `compat_o` (`run -o x a.c` runs `./x`).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -m "dev: run handles Rust, Python and Makefiles, with an exit line"`

### Task 4: rud and rund

**Files:** Modify `lib/dev.sh` (`rud`, `rund` top half; the valgrind report loop is unchanged), `tests/dev.sh`.

**Interfaces:** Consumes `_dev_parse`, `_dev_build`, `_dev_prog`.
- `rud` → build (MODE run), then `lldb -- "${prog[@]}"` (gdb `--args` if no lldb); python `python -m pdb FILE`.
- `rund` → build MODE `plain` (cargo/make as is), then the existing valgrind block on `"${prog[@]}"`; python → `Error: valgrind is for compiled programs (C, C++, Rust)` status 1.

- [ ] **Step 1: Write failing tests** with stub `lldb`/`valgrind` scripts on PATH that print their argv: `rud_c` (stub sees `-- ./sq`), `rud_gdb_fallback`, `rud_py` (stub `python3` sees `-m pdb`), `rund_plain` (compile line lacks `-fsanitize`), `compat_rund` (`rund -i in.txt -- 1 2` → stub sees `./<name> 1 2`), `rund_py_refuses`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -m "dev: rud opens lldb, rund runs valgrind on any compiled language"`

### Task 5: rut, mkmake, completions, lazy line

**Files:** Modify `lib/dev.sh` (`rut`, new `mkmake`, completions), `bashrc:175` (`_bashrc_lazy dev ru run rud rund rut mkt mkmake`), `tests/dev.sh`.

**Interfaces:**
- `_run_suite [-v] SUITE PROG…` → PROGRAM becomes the remaining args (a command array); the `-x` check applies only when it is a single path.
- `rut` → build then `_run_suite $verbose "$suite" "${prog[@]}"`.
- `mkmake` → writes `Makefile` (refuses if one exists: `Error: Makefile already exists`) for C or C++: `CC`/`CXX`, `CFLAGS` per Global Constraints, `LDLIBS = -lm`, `PROG = <folder>`, targets `all run debug test clean`, `.PHONY`, recipes indented with real tabs.
- Completions: `-f` completes `*.@(c|cc|cpp|cxx|o|rs|py)`; positional too; `mkmake` gets `-h`.

- [ ] **Step 1: Write failing tests** `rut_c` (sq + `t1.in`=`3`, `t1.expect`=`Give me a number: 3 squared is 9`), `rut_py`, `compat_rut_flags` (`rut -- -DX`), `mkmake_builds` (`mkmake` then `make` makes `./<folder>`; `make run` with input works), `mkmake_refuses`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** `bash tests/dev.sh && bash tests/smoke.sh` → pass.
- [ ] **Step 5: Commit** `git commit -m "dev: rut for any language, new mkmake"`

### Task 6: Docs, CI, VS Code, go live

**Files:** `docs/FEATURES.md` (rename "C toolchain" to "Dev commands", one row per command incl. `mkmake`), `lib/dev.sh` header comment, `.github/workflows/*.yml` (apt line adds `clang make python3 python3-venv`), outside the repo: `~/.config/Code/User/settings.json` executor map (`c cpp rust python` → `cd $dir && run "$fileName"`), the Square One page (new "Run from the terminal" section).

- [ ] **Step 1:** Update docs and CI; run `bash tests/smoke.sh` → pass; `shellcheck` clean.
- [ ] **Step 2:** Commit `git commit -m "dev: docs and CI for the multi-language commands"`.
- [ ] **Step 3:** Merge `feat/multi-language-run` into `omarchy-profile` (fast-forward), let `omarchy-config-backup` push it and fast-forward `main`; watch the CI run to green.
- [ ] **Step 4:** In a fresh interactive shell on the laptop: `run` in `~/Projects/c-practice` and `~/Projects/rust-practice` with input `12` → `144` and the exit line; VS Code's Run button on `square.c` shows the same exit line.
