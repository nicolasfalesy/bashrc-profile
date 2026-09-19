# Architecture

How the profile is put together, in the order things happen when a shell starts.

## 1. The big picture

```
 ~/.bashrc  (symlink)
     │
     ▼
 bashrc ─── interactive? no → return (scp, rsync, `ssh host cmd` stop here)
     │
     ├── ~/.config/bashrc-profile/config     profile + toggles  (written by install.sh, edit: bt config)
     ├── autodetect profile if config didn't set one
     ├── ble.sh --noattach                    only if BASHRC_BLESH=1
     │
     ├── lib/core.sh          options · history · readline · PATH · env · completion · lazy loader
     ├── lib/aliases.sh       aliases · bt · bup · prereqs
     ├── lib/navigation.sh    ll · cd · up · mkcd · take · tre
     ├── lib/files.sh         extract · ftext · size · bak · diff2 · path
     ├── lib/clipboard.sh     cpy · pst        (OSC 52 — works over SSH)
     ├── lib/system.sh        sys · psg · port · killport · topp · myip · weather · t · rcon
     ├── (lib/dev.sh)         ru run rud rund rut mkt   ← stubs only; loaded on first use
     │
     ├── profiles/pi.sh | nas.sh | desktop.sh | uw.sh | server.sh
     ├── ~/.bashrc.local      secrets, ssh hosts, per-machine overrides (never committed)
     │
     └── lib/prompt.sh        fastfetch · fzf · starship · (zoxide) · ble-attach   (always last)
```

Three kinds of configuration, three places:

| What | Where | In git? |
|------|-------|---------|
| Behaviour shared by all machines | `lib/*.sh` | yes |
| Behaviour for one *kind* of machine | `profiles/*.sh` | yes |
| Which kind this machine is + feature toggles | `~/.config/bashrc-profile/config` | no (installer writes it) |
| Secrets, hostnames, passwords, per-box aliases | `~/.bashrc.local` | no (template `bashrc.local.example` is) |

## 2. `bashrc` — the entry point, line by line

```bash
case $- in *i*) ;; *) return ;; esac
```
`$-` holds the shell's option letters; `i` means interactive. `scp`, `rsync`, `sftp`
and `ssh host 'command'` start a *non-interactive* bash that still reads `~/.bashrc`.
Anything printed there corrupts the protocol — the old profile ran `fastfetch`
unconditionally, which is exactly the classic "scp hangs / rsync protocol error"
bug. Everything below this line is interactive-only.

```bash
_bashrc_toggles=(BASHRC_PROFILE BASHRC_BLESH BASHRC_FASTFETCH …)
for _m in "${_bashrc_toggles[@]}"; do [[ -n ${!_m-} ]] && _bashrc_env+=("$_m=${!_m}"); done
[[ -r "$BASHRC_CONFIG_DIR/config" ]] && . "$BASHRC_CONFIG_DIR/config"
for _m in "${_bashrc_env[@]}"; do declare -g "$_m"; done
BASHRC_PROFILE="${BASHRC_PROFILE:-}" BASHRC_BLESH="${BASHRC_BLESH:-1}" …
```
Precedence is **environment > config file > defaults**. Every toggle that is
already in the environment is saved, the config file (plain bash written by the
installer — no parsing) is sourced, and the saved values are put back. So
`BASHRC_PROFILE=nas BASHRC_BLESH=0 bash -i` tries a combination without editing
anything. `declare -g` matters because `bup` and `bt` re-source `bashrc` from
inside a function, where a plain `declare` would be local.

Adding a toggle = three places: the defaults block here, `_bashrc_toggles`, and
`config_lines` in `install.sh` (so `bup` appends it to existing configs).

```bash
if [[ -z ${BASHRC_PROFILE_DIR-} || ! -f $BASHRC_PROFILE_DIR/lib/core.sh ]]; then
    BASHRC_PROFILE_DIR=$(readlink -f "${BASH_SOURCE[0]}"); BASHRC_PROFILE_DIR=${BASHRC_PROFILE_DIR%/*}
fi
```
The installer records the repo location in the config file. If it is missing (you
ran `bash --rcfile ./bashrc` from a checkout, say), resolve the symlink. `${var%/*}`
strips the filename — a bash parameter expansion instead of a `dirname` fork.

**Profile autodetection** (only when the config did not set one):
`/proc/device-tree/model` contains "Raspberry Pi" → `pi`; `/usr/share/truenas` or
`/usr/bin/midclt` (TrueNAS middleware client) → `nas`; `$DISPLAY`/`$WAYLAND_DISPLAY`
set → `desktop`; `$HOSTNAME` or a `search`/`domain` line in `/etc/resolv.conf` under
`uwaterloo.ca` → `uw` (read with a `while read` loop — no fork); else `server`.

**ble.sh** has to be sourced with `--noattach` *before* anything calls `bind`, and
`ble-attach`ed at the very end — that is why it appears in both `bashrc` and
`lib/prompt.sh`.

**Modules** are sourced in a fixed list; `lib/dev.sh` is not sourced — instead
`_bashrc_lazy dev ru run rud rund rut mkt` installs stubs (see §4).

`BASHRC_TIMING=1 bash -i` prints the milliseconds the whole file took, including
`ble-attach`. Run it in a real terminal: ble.sh refuses to load in `bash -c …`
shells, so `bash -ic exit` timings never include it.

## 3. `lib/core.sh` — every setting explained

**shopt**
- `histappend` — append to `~/.bash_history` on exit rather than overwrite; several
  terminals no longer clobber each other.
- `checkwinsize` — re-read the terminal size after each command so wrapping stays
  right after a resize (default in bash ≥ 5, kept for older systems).
- `cmdhist` — a multi-line command is stored as one history line.
- `cdspell` — `cd /ect` silently becomes `cd /etc`.
- `no_empty_cmd_completion` — Tab on an empty line does not scan all of `$PATH`.

**History**
- `HISTSIZE=50000` / `HISTFILESIZE=100000` — the old 500/10000 meant a day's work
  fell out of memory. Bash handles 100k lines without noticeable cost.
- `HISTCONTROL=ignoreboth:erasedups` — `ignoreboth` = skip duplicates of the previous
  line and lines starting with a space (handy for passwords); `erasedups` removes
  older copies when a line is re-entered, so `history | grep` stays clean.
- `HISTTIMEFORMAT='%F %T '` — `history` shows when each command ran (the old value
  lacked the trailing space, so the time ran into the command).
- `HISTIGNORE` — `ls`, `ll`, `c`, `e`, … are not worth remembering.
- `PROMPT_COMMAND='history -a'` — append each command to the file immediately, so a
  crash or a second terminal never loses it. Starship wraps `PROMPT_COMMAND` and
  keeps running this.

**Readline (`bind`)**
- `bell-style visible` — flash, never beep.
- `completion-ignore-case on` — `cd doc<Tab>` matches `Documents`.
- `show-all-if-ambiguous on` — one Tab lists candidates instead of two.
- `colored-stats on` / `colored-completion-prefix on` — completion lists are coloured
  like `ls`, and the part you already typed is highlighted.
- `mark-symlinked-directories on` — a completed symlink-to-directory gets a `/`.
- `"\C-z": undo` — Ctrl-Z undoes edits on the command line (the job-control meaning of
  Ctrl-Z still applies while a program is running).
- `stty -ixon` — turn off XON/XOFF flow control so Ctrl-S becomes *forward* history
  search (the partner of Ctrl-R) instead of freezing the terminal.

**XDG directories** — set with `${VAR:-default}` so an existing value (e.g. from a
desktop session) is respected. Several tools (nvim, starship, zoxide) read them.

**PATH** — `_path_prepend`/`_path_append` add a directory only if it exists and is not
already present, so re-sourcing never grows `$PATH`. User dirs (`~/.local/bin`,
`~/.cargo/bin`, `~/.fzf/bin`) go first so user-installed tools win; flatpak and Go go
last. (The old profile had `/.local/share/flatpak/…` — a typo for `$HOME/…`.)

**EDITOR/VISUAL** — first available of `nvim`, `vim`, `nano`, but only when the
environment did not already provide one (`EDITOR=nano bt local` works; a permanent
choice goes in `~/.bashrc.local`, which is sourced later). Checked with `hash`, a
builtin that also caches the lookup; no subprocess.

**LESS** — `-R` lets ANSI colour through (git, `diff2`, `ftext`). The `LESS_TERMCAP_*`
variables recolour `man` pages: headings red, options green, search hits yellow-on-blue.

**bash-completion** (the ~35 ms elephant) — three cases:
1. `BASH_COMPLETION_VERSINFO` already set → a login shell (ssh) got it from
   `/etc/profile.d/bash_completion.sh`; do nothing. The old profile loaded it a
   second time here, doubling ssh login time.
2. `BASHRC_LAZY_COMPLETION=1` (default) → install `_bashrc_load_completion` as the
   *default* completer (`complete -D`). The first Tab on any command loads
   bash-completion, hands over to its own loader, and returns **124**, which tells
   readline "the completion spec changed, try again". After that first Tab everything
   behaves exactly as if it had been loaded eagerly.
3. Otherwise source it now.

**Lazy module loader** — `_bashrc_lazy <module> <fn>…` writes, for each name, a stub
function *and* a stub completion function. Calling the stub (or pressing Tab on it)
unsets all stubs, sources `lib/<module>.sh`, then re-invokes the real function or the
completer that the module registered. `lib/dev.sh` (800 lines, ~6 ms to parse) is only
ever loaded when you actually compile something.

**`command_not_found_handle`** — prints a red one-liner. Only defined when Debian's
`command-not-found` package has not already defined one in `/etc/bash.bashrc`.

## 4. The function modules

Shared conventions:
- Every function answers `-h`/`--help`; most have a `_name_completions` function and
  a `complete -F` line right below.
- External commands that an alias might shadow are called as `command ls`,
  `command grep`, `command du`, `command rm` — alias expansion happens when a function
  is *parsed*, so a function defined after `alias grep=rg` would silently contain
  `rg`. (That is how the old `ftext` ended up running `rg -iIHrn`, where `-r` means
  *replace*.)
- `ll` is a function precisely so that `cd`, `mkcd` and `take` can call it regardless
  of when they were parsed. The old `mkcd` failed with "command not found: ll".
- Profile hooks: `sys` calls `_sys_extra` if a profile defined it (`pi`: throttle
  flags, `nas`: pool health).

`lib/navigation.sh` — `cd` wraps `builtin cd`, then counts entries with a glob (no
`ls | wc` forks) and lists only if there are at most `BASHRC_CD_LS_MAX`. zoxide's
`__zoxide_cd` is pointed at this `cd` so `z` lists too. `tre` falls back to an
indented `find` listing where `tree` cannot be installed (TrueNAS, UW).

`lib/files.sh` — `size` runs `du -sb` in the background and spins while waiting; the
byte→unit formatting is one helper (`_size_fmt`) instead of two copies of the same
40 lines. `extract` lets GNU tar autodetect compression, so one case covers
`.tar.{gz,bz2,xz,zst}`.

`lib/clipboard.sh` — `cpy`/`pst` used to live in `profiles/desktop.sh`, where they were
useless: the machines actually typed into are headless and reached over SSH. The backend
is resolved *per call* rather than at startup, because one shell can be local now and
inside tmux over SSH a minute later — and because a `hash` lookup per call costs nothing
while a startup probe would show up in the 6–8 ms budget. Everything is staged through
the spool file instead of a shell variable: command substitution eats trailing newlines,
so `cat f | cpy; pst > f2` would not have been byte-exact. `_clip_osc52_read` runs in a
subshell with an `EXIT` trap that drains the terminal and restores `stty` — raw mode left
on wedges the shell, and a reply that arrives after the timeout would otherwise be typed
into the next prompt. `_clip_slurp` (`cpy -p`) exists because Windows Terminal and WezTerm
refuse that read permanently, so the clipboard has to be *typed* at us instead; it reads
with `dd`/`cat` rather than the `read` builtin, because `read` rewrites CR as LF on a
terminal and a Windows clipboard arrives as CRLF, and it lets `stty min 0 time N` decide
when the paste has stopped instead of timing the loop in bash.

`lib/system.sh` — `sys` reads `/proc/stat` twice, 0.5 s apart, and computes the
*delta* (the old version divided cumulative counters, i.e. average since boot). Memory
comes from `/proc/meminfo`; the primary interface from `ip route get 1.1.1.1` (the old
`whatsmyip` hard-coded `wlan0`; the Pi is on `eth0`). Temperature comes from the first
hwmon sensor named `coretemp`/`k10temp`/`zenpower`/`cpu_thermal`, falling back to
`thermal_zone0` — on the NAS the ACPI zone reads 16 °C while the CPU is at 68 °C.

`lib/dev.sh` — the valgrind report in `rund` is coloured with bash pattern matching
only (`case`, `[[ =~ ]]`); the previous version forked `echo | sed` plus up to nine
`grep`s *per line*.

## 5. `lib/prompt.sh` — why it is fast

`starship init bash` and `zoxide init bash` (zoxide only when `BASHRC_ZOXIDE=1`; it is
off by default) are Rust binaries that print a shell script. Spawning them cost
~20 ms + ~35 ms on the Pi *every shell start*.
`_bashrc_cached_init` runs each once, saves the script to
`~/.cache/bashrc-profile/<name>.bash`, and afterwards just sources the file. The
binary's path comes from `${BASH_CMDS[name]}` (bash's own hash table — no fork) and
`[[ $binary -nt $cache ]]` triggers a rebuild after an upgrade. `bup` and `prereqs`
clear the cache too.

The starship script is patched once, when cached:
- `PS2="$(starship prompt --continuation)"` → the literal string (one fork saved per start);
- `$(starship time)` → `$(( ${EPOCHREALTIME/./} / 1000 ))` — bash ≥ 5 can tell the time
  itself, saving the two forks starship would otherwise do *around every command*.

fzf: only `key-bindings.bash` is loaded (Ctrl-R fuzzy history, Ctrl-T file picker,
Alt-C cd). `completion.bash` (the `vim **<Tab>` feature) costs ~25 ms because it
inspects every registered completion; enable with `BASHRC_FZF_COMPLETION=1` if you
want it. With ble.sh on, the ble contrib integrations are used instead.

If starship is missing you get a plain green/blue `user@host:path$` prompt.

**PROMPT_COMMAND and history.** `lib/core.sh` sets `PROMPT_COMMAND='history -a'`.
starship's init replaces `PROMPT_COMMAND` with `starship_precmd` and stores the old
value in `STARSHIP_PROMPT_COMMAND`, which `starship_precmd` evals every prompt — so
each command still lands in the history file immediately (verified). With ble.sh
attached, ble.sh takes over history entirely (`bleopt history_share=1` in `blerc`:
other terminals' commands appear, and writes are ble.sh's), and it *unsets*
`PROMPT_COMMAND` while a command runs. A function that reads `$PROMPT_COMMAND` at
runtime under ble.sh sees it empty; that is normal.

Measured on the Pi 4 (`BASHRC_TIMING=1`, warm cache): **~22 ms inside `bashrc`, ~30 ms
wall for `bash -ic exit`**, down from ~80 ms.

## 6. `install.sh`

Phases, each a function: `detect_profile` → `detect_system` (package manager, sudo,
arch) → `locate_repo` (use the checkout you ran it from, else clone/pull
`~/.local/share/bashrc-profile`, else tarball) → `install_dependencies` →
`link_files` → `write_config` → `verify` → `summary`.

Dependencies are declared as arrays of `package[:command]`:

| List | Contents |
|------|----------|
| `CORE_PKGS` | bash-completion curl git wget tree ripgrep neovim trash-cli tmux htop unzip p7zip-full xz-utils zstd gawk iproute2 fzf starship (zoxide only with `--with-zoxide`) |
| `PI_PKGS` | nala raspi-utils (vcgencmd) wireguard-tools |
| `DESKTOP_PKGS` | alacritty xclip wl-clipboard wireguard-tools fonts-noto-color-emoji desktop-file-utils |
| `DEV_PKGS` (`--with-dev`) | gcc make gdb valgrind clang |

`install_pkgs` skips anything whose command or package is present, checks the repo
actually has a candidate (`apt-cache policy`), and installs the rest in one
transaction. Whatever the repos cannot provide falls through to user-local
installers: starship → `~/.local/bin`, zoxide → `~/.local/bin`, fzf → `~/.fzf`,
ble.sh → `~/.local/share/blesh` (release tarball, no `make` needed), mcrcon (built
from source, `--with-mcrcon`), MesloLGS Nerd Font → `~/.local/share/fonts` (desktop).

On **nas** the package manager is forced to `none`: TrueNAS SCALE mounts `/` read-only
and disables apt, so only the user-local path runs.

`link_files` backs up whatever is at `~/.bashrc`, `~/.config/starship.toml`, `~/.blerc`
(following a symlink and copying its content) to `*.bak.<timestamp>` and symlinks the
repo files. The starship link points at `themes/aurora.toml` (`themes/waterloo-gold.toml`
on **uw**); a link that already points at some file in `themes/` is kept, so a theme
chosen by hand survives `bup`.

`--upgrade` (`prereqs --upgrade`) re-runs the user-local installers in refresh mode:
ble.sh re-downloads the nightly tarball, starship and zoxide re-run their upstream
installers with force, fzf does `git pull` in `~/.fzf` and rebuilds the binary. A copy
that came from apt (`is_user_local` says no) is left to `nu`. Versions before/after are
listed in the summary. `write_config` records profile, repo dir and toggles, and seeds
`~/.bashrc.local` (mode 600) from the template if absent. `verify` parses every file
with `bash -n`, then starts a real `bash --rcfile … -i` and checks the core functions
exist.

`--update` (what `bup` runs) = `git pull --ff-only` in the checkout (`update_repo`),
relink, `refresh_config` (append any toggle from `config_lines` that the existing
config lacks, and re-point `BASHRC_PROFILE_DIR` if the repo moved — nothing else
in the file is touched), clear caches, verify. `--deps-only` is what `prereqs` calls;
`--uninstall` removes the links and restores the newest backups.

## 7. Editing safely

- `bt <module>` opens a file; on save it runs `bash -n` and reloads the profile in
  the current shell only if the file parses. `bt local`, `bt config`, `bt readme`,
  `bt features` … work the same way (docs are just saved).
- `bash tests/smoke.sh` parses every file, runs shellcheck if present, checks that
  sourcing `bashrc` from a non-interactive shell prints nothing, then starts a real
  interactive shell per profile inside a throw-away `HOME` (own `HISTFILE`, no config,
  no `~/.bashrc.local`, ble.sh off) and calls the functions. Run it before `bgit push`;
  GitHub Actions (`.github/workflows/smoke.yml`) runs the same script plus an
  installer dry run on every push, so a red badge on the README means a broken push.
- The code is shellcheck-clean with the repo's `.shellcheckrc`; the few deliberate
  exceptions carry an inline `# shellcheck disable=…` with the reason.
- Things that bite:
  - anything that prints before the interactive guard in `bashrc` breaks scp/rsync;
  - a new function in `lib/dev.sh` must be added to the `_bashrc_lazy dev …` line;
  - a new toggle goes in three places (see §2);
  - inside functions, call tools an alias might shadow as `command x`;
  - `ll` is a function, not an alias, so `cd`/`mkcd`/`take` can call it;
  - keep `lib/prompt.sh` last and never `bind` after ble.sh is attached;
  - a test shell must get its own `HISTFILE` or its commands end up in yours
    (`tests/smoke.sh` does this; a hand-rolled `bash -i < script` does not).
