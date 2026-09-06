# Audit — September 2026

What was found in the previous `bashrc` / `shell_functions` / `install.sh`, what was
changed, and why. The live config on the Pi had drifted from the GitHub copy (ble.sh
and fastfetch commented out, zoxide removed from `install_prereqs`, ~1100 extra lines
of functions); this rewrite reconciles both into one repo with machine profiles.

## Security

| Finding | Action |
|---------|--------|
| **Minecraft RCON password committed** in `bashrc` (`RCON_PASS="${RCON_PASS:-ADF3…}"`) and pushed to a public repo | Removed. Secrets now live only in `~/.bashrc.local`. **Rotate the RCON password** — it stays in the git history of every clone. |
| Home IPs, the UW username/hostname in tracked files | Moved to `~/.bashrc.local` (template ships with them since they are already public; edit as you like). |
| `curl … \| sh` used at shell *runtime* (`linutil`) | Removed. The installer still uses upstream install scripts, but only for starship/zoxide/fzf/ble.sh and only when apt cannot provide them. |
| The NAS's ssh host key differs from `~/.ssh/known_hosts` (key changed — reinstall? new key?) | Not bypassed. If you reinstalled TrueNAS, run `ssh-keygen -R 192.168.2.182` and reconnect; otherwise investigate before trusting the box. |

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
`rm → trash`, the `claude --dangerously-skip-permissions` alias (Pi only).
