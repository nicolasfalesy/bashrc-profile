# bashrc-profile

[![smoke](https://github.com/nicolasfalesy/bashrc-profile/actions/workflows/smoke.yml/badge.svg)](https://github.com/nicolasfalesy/bashrc-profile/actions/workflows/smoke.yml)

A modular bash configuration for every machine I touch — a Raspberry Pi 4 (Docker host),
a TrueNAS SCALE box, a laptop, and the odd Debian server — with one installer that
knows which machine it is on and what that machine needs.

```bash
curl -fsSL https://raw.githubusercontent.com/nicolasfalesy/bashrc-profile/main/install.sh | bash
```

Or from a clone: `bash install.sh` (add `--dry-run` to preview, `--help` for options).

## What you get

| Area | Highlights |
|------|-----------|
| Prompt | [starship](https://starship.rs) "Aurora" theme ("Waterloo Gold" on the UW servers, "Omarchy Auto" — which retints itself to match the desktop theme — on the laptop), [fzf](https://github.com/junegunn/fzf) Ctrl-R / Ctrl-T / Alt-C, [ble.sh](https://github.com/akinomyoga/ble.sh) highlighting + autosuggestions, optional [zoxide](https://github.com/ajeetdsouza/zoxide) `z`/`zi` (`--with-zoxide`) |
| Speed | 6–8 ms inside `bashrc` on the NAS, ~22 ms on a Pi 4 (ble.sh attach on top): cached `starship`/`zoxide` init, bash-completion loaded on first Tab, big modules lazy-loaded |
| Navigation | `cd` auto-lists, `ll`, `up 3`, `mkcd`, `take <url>`, `tre` |
| Files | `extract`, `ftext`, `size`, `bak`/`bak -r`, `diff2`, `path` |
| Clipboard | `cpy` / `pst` on every machine — `cat notes.txt \| cpy` puts it on your laptop's clipboard straight out of an SSH session (OSC 52), and `cpy -p` catches a paste coming the other way |
| System | `sys`, `psg`, `port`, `killport`, `topp`, `myip`, `weather`, `t` (tmux) |
| Services | git (`gs`, `gcm`, `glog`…), systemd (`scs`, `screstart`, `sclog`…), Docker Compose (`dcu`, `dcd`, `dcr`, `dcl`, `dps`) |
| C dev | `ru` / `run` / `rud` / `rund` (valgrind) / `rut` (test suite) / `mkt` — lazy-loaded |
| Per machine | **pi**: `temp`, `wt`, `cloud` (Cloudflare tunnel) · **nas**: ZFS shortcuts, `dsv`, `wn` · **desktop**: `vpn`, `note`, Alacritty/GRUB helpers · **uw**: no-root student servers, Waterloo Gold prompt |
| Housekeeping | `bt` (edit a module — syntax-checked and reloaded on save), `bgit` (git in the repo from anywhere), `bup` (pull + relink + reload), `prereqs` (install dependencies), `reload`, `tests/smoke.sh` |

Full reference: [docs/FEATURES.md](docs/FEATURES.md).

## Layout

```
bashrc                 entry point (~/.bashrc → this)
lib/core.sh            options, history, PATH, env, readline, completion
lib/aliases.sh         aliases + bt / bup / prereqs
lib/navigation.sh      ll, cd, up, mkcd, take, tre
lib/files.sh           extract, ftext, size, bak, diff2, path
lib/clipboard.sh       cpy, pst (OSC 52 — works over SSH)
lib/system.sh          sys, psg, port, killport, topp, myip, weather, t, rcon
lib/dev.sh             C toolchain (lazy-loaded)
lib/prompt.sh          fzf, starship, ble.sh, optional zoxide (always last)
profiles/{pi,nas,desktop,uw,server}.sh
themes/aurora.toml     starship theme, linked as ~/.config/starship.toml
themes/waterloo-gold.toml   linked instead on the uw profile (bt theme edits whichever is linked)
themes/omarchy-auto.toml    starship theme for the omarchy profile — colours by name only,
                       rendered against the desktop theme (bt theme edits this one)
bin/starship-omarchy-palette   renders it from the current Omarchy theme's colors.toml
hooks/50-starship-palette      theme-set hook that re-runs the renderer
blerc                  ble.sh settings, linked as ~/.blerc
legacy/                the old single-file uw_bashrc and TrueNAS zshrc (reference only)
bashrc.local.example   template for ~/.bashrc.local (secrets, ssh hosts — never committed)
install.sh             install / --update / --deps-only / --uninstall
tests/smoke.sh         parse + shellcheck + start every profile in a sandbox and call the functions
.github/workflows/     CI: runs tests/smoke.sh and an installer dry run on every push
.shellcheckrc          repo-wide shellcheck settings (the code is shellcheck-clean)
docs/                  ARCHITECTURE, FEATURES, SETUP, AUDIT
```

How it fits together: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Per-machine install notes (Pi, TrueNAS, laptop): [docs/SETUP.md](docs/SETUP.md).

## Machine profiles

The installer detects the profile (`/proc/device-tree/model` → **pi**, TrueNAS
middleware → **nas**, a display → **desktop**, a `uwaterloo.ca` hostname or DNS
search domain → **uw**, else **server**) and writes it to
`~/.config/bashrc-profile/config`. Override with `install.sh --profile nas` or
edit later with `bt config`.

| | pi | nas | desktop | uw | server |
|---|---|---|---|---|---|
| System packages via apt/nala | ✓ | ✗ (read-only root) | ✓ | ✗ (no root) | ✓ |
| starship / fzf | apt, fallback `~/.local/bin` | `~/.local/bin` only | apt, fallback `~/.local/bin` | `~/.local/bin` only | apt, fallback |
| ble.sh (syntax highlighting) | on | on (`~/.local/share/blesh`) | on | on | on |
| fastfetch on new terminal | off | off | on | off | off |
| starship theme | Aurora | Aurora | Aurora | Waterloo Gold | Aurora |
| Extras | raspi-utils, nala, wireguard | GPU `wn`, hand-unpacked nvim | alacritty, clipboard, Nerd Font, wireguard | `rm -iv`, `~/bin` | — |

zoxide (`z`, `zi`) is off everywhere unless you install with `--with-zoxide` or set
`BASHRC_ZOXIDE=1` in `bt config`.

## Daily use

```bash
bt            # edit lib/aliases.sh        bt pi / bt system / bt local / bt config / bt readme
              # on save: bash -n, then the profile is reloaded in this shell
bgit status   # git inside the repo from anywhere: bgit add -A && bgit commit -m … && bgit push
reload        # re-source ~/.bashrc
bup           # install.sh --update: git pull, relink, add new toggles to the config, reload
prereqs       # (re)install this profile's dependencies    prereqs --with-dev
prereqs --upgrade   # refresh ble.sh nightly / starship / fzf / zoxide to their latest
bash "$BASHRC_PROFILE_DIR/tests/smoke.sh"   # before committing: every profile still loads and works
BASHRC_TIMING=1 bash -i                     # how long does startup take?
BASHRC_PROFILE=pi BASHRC_BLESH=0 bash -i    # try another profile / toggle without editing anything
```

Secrets and host-specific aliases (ssh shortcuts, RCON password, Cloudflare tunnel
name, pool name) live in `~/.bashrc.local`, seeded from `bashrc.local.example`.

## Uninstall

```bash
bash ~/.local/share/bashrc-profile/install.sh --uninstall
```
Removes the symlinks and restores the newest `~/.bashrc.bak.*`. Packages stay.

MIT — see [LICENSE](LICENSE).
