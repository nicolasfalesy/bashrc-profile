# Command reference

Everything the profile defines, by module. Every function accepts `-h`.
Tools in *(parentheses)* are required and installed by `install.sh` for the profiles
that use them.

## Keys (lib/core.sh, lib/prompt.sh)

| Key | Action |
|-----|--------|
| Tab | complete; one Tab lists candidates; case-insensitive |
| Ctrl-R / Ctrl-S | fuzzy history search backward / forward *(fzf)* |
| Ctrl-T | fuzzy file picker, inserts the path *(fzf)* |
| Alt-C | fuzzy `cd` into a subdirectory *(fzf)* |
| Ctrl-Z | undo on the command line |
| → / End / Ctrl-F | accept the grey autosuggestion *(ble.sh)* |
| Alt-F | accept one word of it *(ble.sh)* |
| Tab / Shift-Tab, arrows, Enter, Esc | open, cycle, pick, close the completion menu; keep typing to filter *(ble.sh)* |

## Aliases (lib/aliases.sh)

**Editor**

| Alias | Does |
|-------|------|
| `vim`, `vi` | `nvim` (only when nvim exists) |
| `svim` | `sudo $EDITOR` |
| `nt` | edit `~/.config/nvim/init.lua` |

**Packages** (nala if present, else apt; absent on the NAS)

| Alias | Does |
|-------|------|
| `apt` | `sudo nala` |
| `ni <pkg>` | install |
| `np <pkg>` | purge |
| `ns <term>` | search |
| `nu` | update lists + full-upgrade, no questions |
| `nclean` | autoremove + clean cache |

**Core commands**

| Alias | Does |
|-------|------|
| `cp`, `mv` | with `-i` (ask before overwriting) |
| `mkdir` | `mkdir -p` |
| `rm` | `trash -v` (recover with `trash-restore`); `rm -I` where trash-cli is absent |
| `rmd` | the real `rm -rfv` — no trash, no prompts |
| `ping` | 10 packets then stop |
| `mx` | `chmod a+x` |
| `..`, `...`, `cd..` | up one / two levels |
| `e`, `c` | exit, clear |
| `h <text>` | search history |
| `ports`, `openports` | everything listening (`ss -tulnp`) |

**Listing**

| Alias | Does |
|-------|------|
| `l` | `ll` |
| `lt` | `ll` sorted by time, newest last |
| `tree` | coloured, dirs first, human sizes |
| `folders` | size of each subdirectory, sorted |
| `mnts` | `df -hT` without tmpfs/overlay noise |

**git**: `gs` status · `ga` add · `gaa` add -A · `gc` commit · `gcm` commit -m · `gp` push ·
`gl` pull · `gd` diff · `gds` diff --staged · `gb` branch · `gco` checkout · `gsw` switch ·
`glog` graph log · `gst` stash · `gstp` stash pop · `gcl` clone

**systemd**: `sc` systemctl · `scs` status · `scf` --failed · `scstart` · `scstop` ·
`screstart` · `scenable` (enable --now) · `scdisable` (disable --now) · `sclog <unit>`
(journal, jump to end) · `sclogf <unit>` (follow)

**Docker Compose** (run in the directory with the compose file; uses `sudo` unless you
are in the docker group)

| Alias | Does |
|-------|------|
| `dcu` | `compose up -d` |
| `dcd` | `compose down` |
| `dcr`, `dr` | down then up |
| `dcl` | `compose logs -f --tail=100` |
| `dcp` | `compose pull` |
| `dps` | `docker ps` as a names/status/ports table |
| `dprune` | `docker system prune -f` |

**Claude Code** *(when `claude` is on PATH)*

| Command | Does |
|---------|------|
| `claude` | `claude --dangerously-skip-permissions` — every machine here is Nico's own; use `\claude` or `command claude` for one run with the prompts back |

**This profile**

| Command | Does |
|---------|------|
| `bt` | edit `lib/aliases.sh` |
| `bt <module>` | edit `lib/<module>.sh` or `profiles/<module>.sh` — `bt system`, `bt pi` |
| `bt local` / `bt config` | edit `~/.bashrc.local` / `~/.config/bashrc-profile/config` |
| `bt readme`, `bt features`, `bt setup`, `bt architecture`, `bt audit` | edit the docs |
| `bt theme` | edit the starship theme this machine links; `bt aurora` / `bt waterloo-gold` open a specific one |
| `bt blerc`, `bt install.sh`, `bt tests/smoke.sh` | the rest |
| `bt -l` | list everything `bt` can open |
| (after `bt`) | a changed bash file is `bash -n`-checked and, if it parses, `~/.bashrc` is re-sourced in the current shell; a file with a syntax error is *not* reloaded |
| `bgit …` | `git -C $BASHRC_PROFILE_DIR …` — `bgit status`, `bgit add -A`, `bgit commit -m …`, `bgit push` |
| `reload` | `source ~/.bashrc` |
| `bup` | `install.sh --update`: `git pull --ff-only`, relink, append toggles new since this config was written, clear caches, verify — then reload |
| `prereqs [opts]` | `install.sh --deps-only` — e.g. `prereqs --with-dev` |
| `prereqs --upgrade` | refresh the user-local tools to their latest: ble.sh nightly, starship, fzf (`~/.fzf`), zoxide; apt-managed copies are left to `nu` |
| `fetch` | fastfetch |

## Navigation (lib/navigation.sh)

| Command | Does |
|---------|------|
| `ll [args]` | `ls -AFlsh --color --group-directories-first` |
| `cd [dir]` | change directory, then `ll` (skipped above `BASHRC_CD_LS_MAX` entries, default 200) |
| `z <hint>` / `zi` | zoxide jump / interactive pick — lists like `cd` *(zoxide)* |
| `up [n]` | go up n levels |
| `mkcd <dir>` | mkdir -p + cd |
| `take <url\|dir>` | download an archive, extract it in a temp dir and cd in; or `mkcd` |
| `tre [depth] [dir]` | tree, depth 3, ignoring .git/node_modules/__pycache__/.venv/.cache *(tree; a `find`-based fallback where tree cannot be installed)* |

## Files (lib/files.sh)

| Command | Does |
|---------|------|
| `extract <archive>...` | tar.*/tgz/zip/7z/rar/gz/bz2/xz/zst/Z/deb *(unzip, p7zip-full, xz-utils, zstd)* |
| `ftext <pattern>` | recursive case-insensitive text search, paged *(ripgrep, falls back to grep)* |
| `size [--size K\|M\|G\|T] [dir...]` | directory sizes with a spinner and a total |
| `bak <file>...` | copy to `file.bak.YYYYMMDD-HHMMSS` |
| `bak -r <file.bak.TS>` | restore |
| `diff2 <a> <b>` | side-by-side coloured diff in less |
| `path [pattern]` / `path -c` | PATH one per line / count |

## Clipboard (lib/clipboard.sh)

Works on **every** profile, including over SSH — on a headless box `cpy` hands the
text to the terminal emulator at the other end of the connection with an OSC 52
escape sequence, so it lands on the laptop's real clipboard.

| Command | Does |
|---------|------|
| `cpy [TEXT...]` | copy the arguments, or stdin when there are none: `cat notes.txt \| cpy` |
| `cpy -n` | same, minus trailing newlines |
| `cpy -c` | clear the clipboard and the local spool |
| `cpy -p` | **wait for a paste** (Ctrl+Shift+V) and store it — see below |
| `pst` | paste to stdout — `pst > file`, `pst \| jq .` |

Backend, picked per call: `wl-copy` (Wayland) → `xclip`/`xsel` (X11, including
`ssh -X`) → `pbcopy` (macOS) → **OSC 52** (the terminal itself). `tmux` and
`screen` are wrapped in a DCS passthrough automatically.

`cpy` always also writes a spool file (`$BASHRC_CACHE_DIR/clipboard`, mode 0600),
because the OSC 52 *read* that `pst` needs is disabled by default in nearly every
terminal — letting a remote host read your clipboard is a security hole. `pst`
tries the read anyway and otherwise returns the spool, so `cpy` → `pst` on the
same host always round-trips. To get a true remote paste, allow the read:

| Terminal | Setting |
|----------|---------|
| Alacritty | `[terminal] osc52 = "CopyPaste"` in `alacritty.toml` |
| kitty | `clipboard_control write-clipboard write-primary read-clipboard` |
| iTerm2 | Settings → General → Selection → "Applications may access clipboard" |
| xterm | `XTerm*disallowedWindowOps: 20,21,SetXprop` |
| WezTerm, Windows Terminal | write only — **no read, ever** (deliberate; use `cpy -p`) |

### `cpy -p` — paste into the clipboard

For the terminals that will never allow the read. Run `cpy -p`, press Ctrl+Shift+V,
and it captures what the terminal types at it:

```bash
cpy -p          # "paste now (Ctrl+Shift+V)…"  → "caught ✅"
pst > token.txt # and now pst returns it, here and in every later shell
```

`compatibility.allowOSC52` in Windows Terminal's `settings.json` controls the *copy*
half and already defaults to `true`, so `cpy` works there with no configuration.

Two implementation notes, both found the hard way and both load-bearing:

- **bash's `read` builtin cannot be used to capture a paste.** Reading the same raw
  terminal, `dd` sees `A \r \n B` where `read -rs -N` sees `A \n \n` — it rewrites CR
  as LF. A Windows clipboard arrives as CRLF, so every line came out doubled.
- **The terminal must be in raw mode *before* the paste arrives.** Otherwise the
  driver's own CR→LF translation fires first and CRLF becomes two newlines. This is
  why there is no reliable one-keystroke binding: anything that types `cpy -p` and
  pastes in the same action loses the race and double-spaces multi-line pastes.
  Binding a key to *type the command only* is safe:

```json
{ "keys": "ctrl+alt+v",
  "command": { "action": "sendInput", "input": "cpy -p\r" } }
```

  then press Ctrl+Shift+V as normal.

## System (lib/system.sh)

| Command | Does |
|---------|------|
| `sys` | CPU % (real 0.5 s delta) + load, memory, root disk, IP + interface, CPU temperature (hwmon `coretemp`/`k10temp`/`cpu_thermal`, else `thermal_zone0`), battery, uptime, then profile extras |
| `psg <pattern>...` | processes matching, highlighted, with counts |
| `port` / `port 80 443` | what listens where *(iproute2 `ss`)* |
| `killport <port>...` | kill the TCP or UDP listener |
| `topp [-c\|-m] [n]` | top n by CPU or memory |
| `myip` (`whatsmyip`) | LAN IP on the default-route interface + public IP |
| `pubip` | public IP only |
| `weather [-s] [place]` | wttr.in report; default `$WEATHER_LOCATION` |
| `t <name>` | tmux: create or attach · `t -l` list · `t -a` attach · `t -p` kill one · `t -k` kill all *(tmux)* |
| `rcon <cmd>` (`rc`) | Minecraft RCON via `mcrcon`; needs `RCON_IP/PORT/PASS` in `~/.bashrc.local` *(`install.sh --with-mcrcon`)* |

## C toolchain (lib/dev.sh — lazy-loaded; `prereqs --with-dev`)

| Command | Does |
|---------|------|
| `ru [-f files] [-O n] [-W flags] [-o name] [-- gcc-flags]` | compile with `gcc -std=c99 -g -Wall -Wextra -Wpedantic` → `./myprogram` |
| `run …` | `ru` then execute the binary (honours `-o NAME`) |
| `rud …` | debug build (`-O0`) |
| `rund [-i input] [-- args]` | debug build, run under valgrind, colourised leak/error report, log saved |
| `rut [-v] [-d dir] [-f files]` | compile, then run every `<stem>.in` against `<stem>.expect` (+ optional `<stem>.args`) |
| `mkt [-a] <stem>...` | create empty `.in`/`.expect` (and `.args`) test files |

## Profile: pi (profiles/pi.sh)

| Command | Does |
|---------|------|
| `temp` | CPU temperature + decoded `vcgencmd get_throttled` bits (under-voltage, capped, throttled — now and since boot) *(raspi-utils)* |
| `wt` | `watch` temperature + throttle flags every second |
| `cloud <sub>` | edit `/etc/cloudflared/config.yml`, add DNS route `sub.$CF_DOMAIN` to tunnel `$CF_TUNNEL`, restart cloudflared |
| `sys` extra | throttle status line |

## Profile: nas (profiles/nas.sh — TrueNAS SCALE)

`ZPOOL` (default `tank`) comes from `~/.bashrc.local`.

| Command | Does |
|---------|------|
| `zs` / `zh` | `zpool status -v` / `zpool status -x` (health one-liner) |
| `zl` | datasets with used/avail/mountpoint |
| `zsnap` | snapshots by creation time |
| `zio` | `zpool iostat -v 2` |
| `smart <dev>` | `smartctl -a` |
| `dsv [-n] [pattern]` | delete (with sudo) the files `zpool status -v` reports as damaged (default under `/mnt/$ZPOOL/`), confirm, then `zpool clear` |
| `wn` | `watch -n 0.1 nvidia-smi` — only defined when `nvidia-smi` exists |
| `sys` extra | one line per pool: health, used/size, capacity |

Environment: if `~/nvim-linux-x86_64` exists (a hand-unpacked nvim release) it is put on
`PATH` and `VIMRUNTIME` is set.

## Profile: desktop (profiles/desktop.sh)

| Command | Does |
|---------|------|
| `vpn` / `vpn -s` / `vpn -d` | WireGuard `wg0` up / status / down *(wireguard-tools)* |
| `note <text>` / `-l` / `-e` / `-c` | timestamped scratch notes in `$NOTES_FILE` |
| `notes` | edit the "constant notes" file |
| `kt` | edit Alacritty keybinds |
| `at` / `at -l [q]` / `at -t <name>` | Alacritty config / list themes / activate theme |
| `apps` / `apps -u` | cd to local .desktop files / refresh desktop database |
| `install_app <file.desktop>` / `-l [q]` | symlink a launcher / list |
| `grub` / `-e` / `-t <dir>` / `-d` | update-grub / edit config / install theme / cd themes |

Environment: `TERMINAL=alacritty`, `QT_QPA_PLATFORMTHEME=qt5ct`, fastfetch and ble.sh on by default.
`cpy` / `pst` are shared now — see [Clipboard](#clipboard-libclipboardsh); here they pick up `wl-copy` or `xclip` by themselves.

## Profile: omarchy (profiles/omarchy.sh)

Layered on top of Omarchy's own bash setup (see [SETUP.md](SETUP.md#omarchy-laptop-profile-omarchy)).
Where both sides define a name, this file settles it:

| Name | Winner | The other one moved to |
|------|--------|------------------------|
| `cd` | Omarchy (zoxide `zd`) | — (`z` / `zi` jump) |
| `c` | ours (clear) | Omarchy's `opencode --auto` → `o` |
| `h` | Omarchy (herdr) | our `history \| grep` → `hg` |
| `lt` | Omarchy (eza tree) | our `ll -tr` → `ltr` |
| `ll` | ours, re-pointed at eza | — (matches Omarchy's `ls`) |
| `t` | merged | bare `t` attaches the "Work" tmux session |
| `ga` / `gd` | ours (git add / diff) | Omarchy's worktree add / remove → `wta` / `wtd` |

| Command | Does |
|---------|------|
| `ni` / `np` / `ns` / `nq` | pacman install / remove / search / query |
| `nu` | `omarchy-update` (not `pacman -Syu`: the mirror is pinned on purpose) |
| `nclean` | remove orphaned packages, keep 2 cached versions |
| `htop` | `btop`, when htop is not installed |
| `vpn` / `-s` / `-d` / `-t` | WireGuard `wg0` up / status / down / toggle, shared with the taskbar toggle |
| `note`, `notes`, `apps`, `install_app` | same as the desktop profile |

Also set up here: the Omarchy Auto prompt, which retints itself on every theme
change and shows the next class when one starts within 90 minutes; lazygit
loading the theme's colours after your own config; and a fastfetch card in the
first shell of a new terminal window. Environment: `TERMINAL=/usr/bin/foot`;
`claude` is left as the real binary.

## Profile: uw (profiles/uw.sh — UW CS student servers)

No root, so there is nothing to install system-wide. The installer links the
**Waterloo Gold** theme (`themes/waterloo-gold.toml`) as `~/.config/starship.toml`.

| Change | Does |
|--------|------|
| `PATH` | `~/bin` first |
| `rm` | `rm -iv` (no trash-cli on the servers) |
| removed | `apt`, `ni`, `np`, `ns`, `nu`, `nclean`, `svim` |

The C toolchain (`ru`… `mkt`) is the shared `lib/dev.sh`; put `alias home-pc=…` in
`~/.bashrc.local`.

## Environment variables you can set (bt config / bt local)

Precedence: **environment > `~/.config/bashrc-profile/config` > defaults in `bashrc`**.
So `BASHRC_BLESH=0 bash -i` or `BASHRC_PROFILE=pi bash -i` tries something once
without touching the config file.

| Variable | Default | Meaning |
|----------|---------|---------|
| `BASHRC_PROFILE` | autodetect | pi / nas / desktop / omarchy / uw / server |
| `BASHRC_BLESH` | 1 | load ble.sh when `~/.local/share/blesh/ble.sh` exists (highlighting, autosuggestions, menu completion — tuned in `blerc`) |
| `BASHRC_FASTFETCH` | 0 (desktop 1) | fastfetch on new terminals |
| `BASHRC_CD_LS_MAX` | 200 | `cd` lists directories up to this size |
| `BASHRC_LAZY_COMPLETION` | 1 | bash-completion on first Tab instead of at startup |
| `BASHRC_FZF_COMPLETION` | 0 | fzf `**<Tab>` completion (+25 ms) |
| `BASHRC_ZOXIDE` | 0 | `1` = zoxide `z` / `zi` (install with `prereqs --with-zoxide`) |
| `BASHRC_TIMING` | – | `=1` prints startup time |
| `BASHRC_CLIP_BACKEND` | auto | force `wayland` / `x11` / `macos` / `osc52` / `file` |
| `BASHRC_CLIP_FILE` | `$BASHRC_CACHE_DIR/clipboard` | the `cpy` spool (mode 0600) |
| `BASHRC_CLIP_MAX` | 74994 | largest base64 payload pushed through OSC 52; `0` = no limit |
| `BASHRC_CLIP_TIMEOUT` | 0.5 | seconds `pst` waits for the terminal's OSC 52 reply |
| `BASHRC_CLIP_PASTE_WAIT` | 15 | seconds `cpy -p` waits for a paste to start (capped at 25) |
| `BASHRC_CLIP_PASTE_IDLE` | 2 | tenths of a second of silence that end a `cpy -p` capture |
| `RCON_IP`, `RCON_PORT`, `RCON_PASS` | – | Minecraft RCON |
| `CF_TUNNEL`, `CF_DOMAIN` | – | Cloudflare tunnel name and zone (`cloud`) |
| `ZPOOL` | tank | pool for the nas profile |
| `WEATHER_LOCATION` | – | default for `weather` |
| `NOTES_FILE` | ~/Nextcloud/quick-notes.txt | `note` storage |
| `EDITOR` | nvim → vim → nano | kept if the environment already set it; set your own in `bt local` |
