# Multi-language dev commands (ru, run, rud, rund, rut, mkt, mkmake)

Date: 2026-10-22. Status: approved design, ready for a plan.

## Goal

The dev commands in `lib/dev.sh` were C-only (gcc, C99). They now work for
whatever language the program is in (C, C++, Rust, Python, and any folder with a
Makefile) and behave exactly like VS Code's Run button, which calls `run`.

Success: in a C folder, a C++ folder, a Cargo project, a Python folder or a
Makefile project, `run` builds (when needed) and runs the right thing; `rut`
tests it; `rud` and `rund` debug it; nothing that worked before stops working.

## Commands

| Command | C / C++ | Rust | Python | Makefile folder |
|---|---|---|---|---|
| `ru [file]` | build | `cargo build` | nothing to build (says so) | `make` |
| `run [file]` | build, run | `cargo run` | run with `.venv/bin/python` or `python3` | `make`, then `make run` if that target exists, else `./<folder name>` |
| `rud [file]` | debug build, open lldb (gdb if no lldb) | `cargo build`, lldb on the binary | `python -m pdb` | `make`, lldb on the binary |
| `rund [file]` | plain debug build (no sanitizers), valgrind report | valgrind on the binary | says valgrind is for compiled programs | `make`, valgrind |
| `rut` | `.in`/`.expect`/`.args` tests | same | same | same |
| `mkt` | unchanged | | | |
| `mkmake` | new: writes a Makefile for the C or C++ files here | | | |

Existing options keep their meaning: `-f FILES`, `-O LEVEL`, `-W [FLAGS]`,
`-o NAME`, `-i INPUT` (rund), `-v`/`-d DIR` (rut), `-a` (mkt). `--` keeps its
meaning per command: compiler flags for `ru`/`run`/`rud`/`rut`, program
arguments for `rund`. For Rust, any `-O` level other than 0 means
`--release`; `-W` and compiler flags do not apply and are refused with a
message. A positional file argument is new: `run square.c`.

## Detecting the language (first match wins)

1. A file named on the command line: its extension (`.c`, `.cpp`/`.cc`/`.cxx`,
   `.rs`, `.py`).
2. A `Makefile` (or `makefile`/`GNUmakefile`) in the current folder.
3. A `Cargo.toml` in the current folder or any parent.
4. Source files in the current folder: `.c`, then C++ extensions, then `.py`.

A folder with more than one of the kinds in step 4 stops with: "This folder has
C and Python files; name one: run square.c". A lone `.rs` outside a Cargo
project is built with `rustc -g`. Several `.py` files run `main.py` if present,
otherwise stop and list them.

## Builds

- C: `clang -std=c17 -Wall -Wextra -g -O0 -fsanitize=address,undefined ... -lm`.
  gcc with the same flags where clang is missing. `-O n` and `-W` behave as before.
- C++: `clang++ -std=c++20`, same flags (g++ fallback).
- Program name: the named file's stem (`run square.c` makes `./square`); the
  folder's name when several files are built; `-o NAME` still wins.
- rund builds the same program without sanitizers (they clash with valgrind).
- Skip unchanged builds (C and C++): a stamp in
  `${XDG_CACHE_HOME:-~/.cache}/bashrc-profile/run/` records the exact compiler
  command; the build is skipped when the binary exists, is newer than every
  source and header in the folder, and the command is identical. Cargo and
  make already do their own.

## After a run

One dim line: `exit 0, 0.02 s` (time from `$EPOCHREALTIME`), red when the exit
code is not 0. `run` returns the program's exit code.

## VS Code

Code Runner's executor map calls `run` for C, C++, Rust and Python
(`cd $dir && run "$fileName"`), so the terminal and the Run button share one set
of rules. Its integrated terminal is an interactive bash, so the lazy stubs are
there.

## Other machines

The same file serves every profile. Missing tools fall back (clang to gcc, lldb
to gdb) or stop with one line naming the package to install.

## mkmake

Writes `Makefile` for the C or C++ files here (refuses to overwrite one):
`CC`/`CFLAGS` matching the build above, targets `all` (default), `run`,
`debug` (lldb), `test` (calls the same `.in`/`.expect` runner via `rut`), and
`clean`. The program is named after the folder.

## Testing

New `tests/dev.sh`, run by `tests/smoke.sh` (so CI and the pre-push hook run
it), building tiny real programs in a temp folder: detection per language and
the mixed-folder message, program naming, skip-unchanged (second run prints no
compile line; touching a header rebuilds), Makefile with and without a `run`
target, Python with and without `.venv`, the exit line (red on a non-zero
exit, exit code passed through), `rut` on C and Python, `mkmake` output built
by `make`, and Rust through cargo when cargo exists (skipped otherwise). CI
installs clang, make and python3; the Ubuntu runner already has cargo.

## Docs

Help text of every command, `docs/FEATURES.md`'s C toolchain table (renamed
"Dev commands"), and the `_bashrc_lazy dev` line in `bashrc` gains `mkmake`.
