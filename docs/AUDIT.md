# Audit — September 2026

What was found in the previous `bashrc` / `shell_functions` / `install.sh`, what was
changed, and why. The live config on the Pi had drifted from the GitHub copy (ble.sh
and fastfetch commented out, zoxide removed from `install_prereqs`, ~1100 extra lines
of functions); this rewrite reconciles both into one repo with machine profiles.

## Security

| Finding | Action |
|---------|--------|
| **Minecraft RCON password committed** in `bashrc` and pushed to a public repo | Removed from `bashrc`, but the same default stayed in `legacy/zshrc` until 2026-09-22, when it became `change-me` there too. Secrets now live only in `~/.bashrc.local`. **Rotate the RCON password**: it stays in the git history of every clone. |
| Home IPs, the UW username/hostname in tracked files | Moved to `~/.bashrc.local`. The template first shipped them as examples; since 2026-09-22 it ships placeholders (192.0.2.x, example.com), and the laptop's backup refuses to push new lines with home addresses. |
| `curl … \| sh` used at shell *runtime* (`linutil`) | Removed. The installer still uses upstream install scripts, but only for starship/zoxide/fzf/ble.sh and only when apt cannot provide them. |
| The NAS's ssh host key differs from `~/.ssh/known_hosts` (key changed — reinstall? new key?) | Not bypassed. If you reinstalled TrueNAS, run `ssh-keygen -R <nas-address>` and reconnect; otherwise investigate before trusting the box. |

## Bugs fixed

1. **No interactive guard.** `~/.bashrc` ran everything (including `fastfetch` on the
   GitHub version) for `scp`/`rsync`/`sftp`, which corrupts those protocols. Now the
   first line returns for non-interactive shells.
2. **`mkcd` / `take` → "command not found: ll".** `shell_functions` was sourced before
   `alias ll=…` existed, and aliases are expanded when a function is *parsed*.
   `ll` is a function now.
3. **`folders` ran Docker.** `alias du='sudo docker compose up -d'` plus
   `alias folders='du -h --max-depth=1'` → bash expands aliases recursively on the
   first word, so `folders` became `sudo docker compose up -d -h --max-depth=1`.
   Docker aliases are `dcu`/`dcd`/`dcr` (`dr` kept); `folders` calls `command du`.
4. **`alias grep=rg` broke `ftext`** (`grep -iIHrn` became `rg -iIHrn`, where `-I` means
   *no filename* and `-r` means *replace*) and any script or function that called
   `grep`. `grep` is `grep` again; `ftext` uses ripgrep explicitly when present.
5. **`alias ps='ps auxf'`** shadowed `ps`, so `ps -p PID -o comm=` inside functions
   (and `ps -ef` at the prompt) mixed syntaxes. Removed.
6. **`alias umount='~/Scripts/umount.sh'`** pointed at a file that does not exist on
   the Pi, so `umount` itself failed. Removed with `mnt`, `bk`, `backup`.
7. **`whatsmyip` hard-coded `wlan0`**; the Pi is on `eth0`. Now `myip` uses the
   default-route interface.
8. **`sys` CPU % was wrong** — it divided cumulative `/proc/stat` counters, i.e.
   the average since boot. Now a real 0.5 s delta; no `bc` needed.
9. **bash-completion loaded twice** in ssh login shells (`/etc/profile.d` + `.bashrc`):
   ~40 ms per login. Guarded on `BASH_COMPLETION_VERSINFO`.
10. **`PATH` typo** `/.local/share/flatpak/exports/bin` (missing `$HOME`). Fixed;
    PATH entries are now de-duplicated and only added when the directory exists.
11. **`up()` leaked globals** (`limit`, `i`). Local now, validates its argument.
12. **`HISTTIMEFORMAT="%F %T"`** without trailing space glued the time to the command.
13. **`HISTSIZE=500`** — a day's work fell out of memory. 50k/100k now.
14. **install.sh** sourced the new bashrc *inside* a `set -euo pipefail` script and
    called it a "reload"; on a piped install `read -p` read from the pipe (the script
    itself). Rewritten: reads from `/dev/tty`, verifies with a real `bash -i`.
15. `at -l` / `install_app -l` used unanchored `grep .desktop`. Anchored.
16. `size` had the unit-formatting block duplicated (40 lines). One helper.
17. `iatest=$(expr index "$-" i)` (a fork, deprecated `expr index`) → `[[ $- == *i* ]]`.

## Removed (did nothing, duplicated something, or referenced things that do not exist)

Aliases: `apt-get`, `nf`/`nfi` (= `nu`), `svi`/`snvim` (= `svim`), `home` (= `cd`),
`bd` (= `cd -`), `k9` (= `pkill`), `da`, `treed`, `folderssort` (`folders` sorts now),
`countfiles`, `f`, `000`/`600`/`666`/`700`/`777` (recursive chmod as root, never used),
`rebootsafe`/`rebootforce`, `linutil`, `mnt`/`umount`/`unmount`/`bk`/`backup`
(`~/Scripts` does not exist), `whatismyip` (kept as alias of `myip`), Ctrl-F → `zi`
(already removed on the Pi).

Functions: `cpg`, `mvg` (never used), `mkdirg` (= `mkcd`), the 200-line
`install_prereqs` (now `prereqs` → `install.sh --deps-only`, one source of truth).

Environment: `CLICOLOR` (BSD `ls` only — no effect on Linux), the 2004-era
`LS_COLORS` string (missing `ow`/`tw`/`st` sticky & world-writable dirs, modern media
types — GNU `ls` defaults are better), `GREP_OPTIONS` block, `LINUXTOOLBOXDIR`,
`/etc/bashrc` check (Fedora path). `TERMINAL`, `QT_QPA_PLATFORMTHEME` and the
Alacritty/GRUB/`.desktop`/clipboard/Nextcloud helpers moved to `profiles/desktop.sh`.

Usage data from `~/.bash_history` on the Pi guided this: `ll` 164×, `c` 104×, `e` 57×,
`dr` 38×, `bt` 19×, `nu` 15×, `wt` 10×, `du` 10×; almost everything removed had 0 uses.

## Renamed

| Old | New | Why |
|-----|-----|-----|
| `du`, `dd`, `dr` | `dcu`, `dcd`, `dcr` (+ `dr`) | stop shadowing coreutils |
| `whatsmyip` | `myip` (old name aliased) | |
| `ports` (netstat) | `ports` (`ss -tulnp`) | net-tools is deprecated |
| `bt` (vim +102 ~/.bashrc) | `bt [module]` | the file is modular now |
| `install_prereqs` | `prereqs` (old name aliased) | |

## Performance (Pi 4, warm cache)

| | before | after |
|---|---|---|
| `bash -ic exit` (new terminal / tmux pane) | 78 ms | 31 ms |
| inside `bashrc` (`BASHRC_TIMING=1`) | — | 22 ms |
| ssh login shell | ~145 ms | bash-completion no longer loaded twice (see below) |

Where it went: bash-completion 35 ms → deferred to first Tab; `zoxide init` 35 ms and
`starship init` 20 ms → cached scripts; fzf `completion.bash` 27 ms → off by default;
`readlink`/`dirname`/`mkdir` forks → parameter expansion and existence checks;
`lib/dev.sh` 6 ms → lazy. Per prompt, two `starship time` subprocesses are replaced by
`$EPOCHREALTIME`.

## Kept as-is (on purpose)

The starship "Aurora" theme and `blerc` tuning, the C toolchain (`ru`…`mkt`) verbatim,
the git/systemd alias sets, `cd` auto-listing (now capped at 200 entries),
`rm → trash`, the `claude --dangerously-skip-permissions` alias (moved out of
`profiles/pi.sh` into `lib/aliases.sh` — it applies to every machine).

## Merged from GitHub afterwards (September 2026)

The rewrite was done on a clone that turned out to be ~60 commits behind
`origin/main`. Everything the remote had was folded in with a merge commit:

| Upstream work | Where it went |
|---------------|---------------|
| `uw_bashrc` + `starship_uw.toml` ("Waterloo Gold"), `install.sh --uw` | `profiles/uw.sh`, `starship_uw.toml`, `install.sh --profile uw` (auto-detected from a `uwaterloo.ca` hostname/search domain) |
| `zshrc` for TrueNAS + zsh plugin installer | superseded — the NAS runs bash now; file kept as `legacy/zshrc` |
| `shell_functions` (C toolchain with multi-file `-f`, `.o` support, `rut -d`) | already identical to the Pi copy that `lib/dev.sh` was taken from; only the `dsv` change below was newer |
| `dsv`: delete with `sudo rm` | `profiles/nas.sh` |
| zshrc extras: `wn` (`watch nvidia-smi`), `VIMRUNTIME` for a hand-unpacked nvim | `profiles/nas.sh`, guarded by `nvidia-smi` / `~/nvim-linux-x86_64` |
| "Remove zoxide from bashrc and zshrc" | honoured: zoxide is opt-in (`BASHRC_ZOXIDE=1`, `install.sh --with-zoxide`); the cached-init code stays for when it is on |
| `starship.toml`: git metrics (neon green / dark red), sudo indicator, memory usage, seconds in the clock, `command_timeout = 5000` | taken as-is, plus `scan_timeout = 100` |
| git / systemctl alias sets, `gcc valgrind clang tmux` in prereqs | already present in `lib/aliases.sh` / `install.sh` |
| `.gitignore` additions (`CLAUDE.md`, build files, backups) | merged; `CLAUDE.md` is untracked again |
| root `FEATURES.md` / `SETUP.md` | replaced by `docs/` |

## Second pass — 6 September 2026

A full read of every file plus real measurements on the NAS (TrueNAS SCALE, bash 5.2)
and a check of the Pi's clone. Everything below was verified by running it, not by
reading alone.

### Measured

| | NAS |
|---|---|
| inside `bashrc` (`BASHRC_TIMING=1`), ble.sh off | 5–8 ms |
| `bash -ic exit` wall | 7–9 ms (`bash --norc`: 2 ms) |
| slowest single steps (trace) | `lib/core.sh` 2.1 ms, `lib/prompt.sh` 1.4 ms, `lib/aliases.sh` 1.1 ms, `ble.sh --noattach` 1.1 ms |

There is nothing left to shave at startup; the profile is within ~5 ms of a bare
shell. ble.sh's `ble-attach` cost could not be measured here (it needs a terminal
that answers its queries — in a pty with no terminal behind it it waits ~200 ms for
replies that never come). Measure it on a real terminal with `BASHRC_TIMING=1 bash -i`
versus `BASHRC_BLESH=0 BASHRC_TIMING=1 bash -i`.

### Bugs fixed

| Finding | Fix |
|---------|-----|
| `BASHRC_BLESH=0 bash -i` (or any toggle in the environment) was overridden by the config file; only `BASHRC_PROFILE` won | environment now beats the config for every toggle (`bashrc` §2) |
| `bashrc` defaulted `BASHRC_BLESH=0` while the installer, README and FEATURES all said ble.sh is on by default | default is 1 (guarded by the ble.sh file existing) |
| `install.sh --update` from a checkout never pulled — `locate_repo` only pulls the clone it made itself — so `--update` was "relink + clear cache" | `update_repo` pulls the checkout in `--update`; `bup` now runs `install.sh --update` instead of its own pull |
| the machine config was never refreshed: NAS and Pi configs still lacked `BASHRC_ZOXIDE` and listed `pi \| nas \| desktop \| server` (no `uw`) | `refresh_config` appends missing toggles on `--update`, leaves existing lines alone; `config_lines` is the single template for both |
| `run -o NAME` compiled to `NAME` and then executed `./myprogram` | `run` honours `-o` |
| `sys` showed 16.8 °C on the NAS: `thermal_zone0` is the ACPI board sensor; the CPU (`k10temp`) was at 68 °C | hwmon CPU sensors first (`coretemp`, `k10temp`, `zenpower`, `cpu_thermal`), `thermal_zone0` as fallback, sensor name shown |
| `killport` only looked at TCP listeners (`ss -tlnp`) while `port` shows UDP too | `ss -tulnp` |
| `tre` was unusable on the NAS and UW servers (no `tree`, no apt) | `find`-based fallback with the same ignores |
| `_bashrc_is_uw` stayed defined whenever the config already named a profile | unset unconditionally |
| `rund` coloured the valgrind report with `echo \| sed` and up to nine `grep`s per line — thousands of forks on a long report | pure bash `case` / `[[ =~ ]]`, same colours |
| `_run_suite` redefined a nested helper as a global function on every call | hoisted to `_run_suite_details` |
| `rut` word-split its stem list (`printf '%s\n' $stems`) | quoted |
| `install.sh --profile` / `--dir` with no value died with an "unbound variable" trace | explicit `die` with a message |
| `install.sh` read the profile back from the config *with its trailing comment* (`nas      # pi \| nas …`), so `[[ $PROFILE == nas ]]` was false and `prereqs` on the NAS chose `apt` as the package manager | comment stripped, value validated |
| `lib/core.sh` overwrote an `EDITOR` that was already in the environment | respected when set; `VISUAL` follows `EDITOR` |
| `install.sh` verify warned about ble.sh's "cannot find a controlling TTY" line on every run | filtered with the other harmless messages |
| ShellCheck: 33× SC2207, 7× SC2139, 6× SC2164 and a dozen others | repo is shellcheck-clean; `.shellcheckrc` documents the three codes that are disabled globally and why, the rest are fixed or carry an inline reason |

### Docs that had drifted

- README "Speed" row described the Pi numbers in a confusing way ("~60 ms with ble.sh
  (was ~80 ms without it)") → rewritten with both machines' numbers.
- ARCHITECTURE listed `zoxide` in `CORE_PKGS` (it has been opt-in since the merge).
- FEATURES said `BASHRC_BLESH` defaults to 1; the code said 0 (now 1 everywhere).
- Nothing explained what happens to `PROMPT_COMMAND`/`history -a` under starship and
  ble.sh (now ARCHITECTURE §5; verified: starship keeps `history -a` via
  `STARSHIP_PROMPT_COMMAND`, ble.sh owns history when attached).

### Added

- `tests/smoke.sh` — parse, shellcheck, non-interactive silence check, then a real
  interactive shell per profile in a throw-away HOME calling every function family.
- `.shellcheckrc`.
- `bt` syntax-checks and reloads on save; `bt readme` / `bt features` … open the docs.
- `bgit` — `git -C $BASHRC_PROFILE_DIR`.
- Quirk comments at the top of `bashrc`, `lib/prompt.sh`, `lib/dev.sh`, `install.sh`
  and an "Editing safely" section in ARCHITECTURE.

### Done the same day

- zsh is gone from the NAS: `~/.zshrc` and `~/.shell_functions` (symlinks into
  `configs/home/`), `~/.zsh/` (three plugin clones), both zsh histories, three
  `.zcompdump*`, `~/.zprofile`, `~/.zshenv`, the June `.bak` files and two stale
  `starship.toml.bak.*`. Everything was tarred to
  `/mnt/<pool>/configs/home/zsh-archive-20260906/` first; the live `.zshrc` (12 lines
  newer) replaced `legacy/zshrc`. The Pi's dead `~/.shell_functions` went the same way.
  Login shells were already bash on both machines; the `zsh` binary is part of the
  TrueNAS image and stays.
- `install.sh --upgrade` / `prereqs --upgrade` refreshes ble.sh, starship, fzf, zoxide.
- Themes moved to `themes/aurora.toml` and `themes/waterloo-gold.toml`; `bt theme`.

### Still open

- The GitHub repo description is still "BASHRC PROFILE!!" with no topics (needs
  `gh auth login` on the NAS, then `gh repo edit`).
- `CLAUDE.md` is gitignored; the quirks now live in tracked comments and docs instead.
- ~~No CI~~ — `.github/workflows/smoke.yml` runs `tests/smoke.sh` and an installer dry
  run on every push (added the same day).
