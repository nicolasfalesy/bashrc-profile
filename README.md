# bashrc-profile

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
| Prompt | [starship](https://starship.rs) "Aurora" theme, [zoxide](https://github.com/ajeetdsouza/zoxide) `z`/`zi`, [fzf](https://github.com/junegunn/fzf) Ctrl-R / Ctrl-T / Alt-C, optional [ble.sh](https://github.com/akinomyoga/ble.sh) |
| Speed | ~30 ms to a prompt on a Pi 4, ~60 ms with ble.sh (was ~80 ms without it): cached `starship`/`zoxide` init, bash-completion loaded on first Tab, big modules lazy-loaded |
| Navigation | `cd` auto-lists, `ll`, `up 3`, `mkcd`, `take <url>`, `tre` |
| Files | `extract`, `ftext`, `size`, `bak`/`bak -r`, `diff2`, `path` |
| System | `sys`, `psg`, `port`, `killport`, `topp`, `myip`, `weather`, `t` (tmux) |
| Services | git (`gs`, `gcm`, `glog`…), systemd (`scs`, `screstart`, `sclog`…), Docker Compose (`dcu`, `dcd`, `dcr`, `dcl`, `dps`) |
| C dev | `ru` / `run` / `rud` / `rund` (valgrind) / `rut` (test suite) / `mkt` — lazy-loaded |
| Per machine | **pi**: `temp`, `wt`, `cloud` (Cloudflare tunnel) · **nas**: ZFS shortcuts, `dsv` · **desktop**: clipboard, `vpn`, `note`, Alacritty/GRUB helpers |
| Housekeeping | `bt` (edit the profile), `bup` (git pull + reload), `prereqs` (install dependencies), `reload` |

Full reference: [docs/FEATURES.md](docs/FEATURES.md).

## Layout

```
bashrc                 entry point (~/.bashrc → this)
lib/core.sh            options, history, PATH, env, readline, completion
lib/aliases.sh         aliases + bt / bup / prereqs
lib/navigation.sh      ll, cd, up, mkcd, take, tre
lib/files.sh           extract, ftext, size, bak, diff2, path
lib/system.sh          sys, psg, port, killport, topp, myip, weather, t, rcon
lib/dev.sh             C toolchain (lazy-loaded)
lib/prompt.sh          fzf, starship, zoxide, ble.sh (always last)
profiles/{pi,nas,desktop,server}.sh
starship.toml, blerc   linked into ~/.config/starship.toml and ~/.blerc
bashrc.local.example   template for ~/.bashrc.local (secrets, ssh hosts — never committed)
install.sh             install / --update / --deps-only / --uninstall
docs/                  ARCHITECTURE, FEATURES, SETUP, AUDIT
```

How it fits together: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Per-machine install notes (Pi, TrueNAS, laptop): [docs/SETUP.md](docs/SETUP.md).

## Machine profiles

The installer detects the profile (`/proc/device-tree/model` → **pi**, TrueNAS
middleware → **nas**, a display → **desktop**, else **server**) and writes it to
`~/.config/bashrc-profile/config`. Override with `install.sh --profile nas` or
edit later with `bt config`.

| | pi | nas | desktop | server |
|---|---|---|---|---|
| System packages via apt/nala | ✓ | ✗ (read-only root) | ✓ | ✓ |
| starship / zoxide / fzf | apt, fallback `~/.local/bin` | `~/.local/bin` only | apt, fallback `~/.local/bin` | apt, fallback |
| ble.sh (syntax highlighting) | on | on (`~/.local/share/blesh`) | on | on |
| fastfetch on new terminal | off | off | on | off |
| Extras | raspi-utils, nala, wireguard | — | alacritty, clipboard, Nerd Font, wireguard | — |

## Daily use

```bash
bt            # edit lib/aliases.sh        bt pi / bt system / bt local / bt config
reload        # re-source ~/.bashrc
bup           # git pull + reload
prereqs       # (re)install this profile's dependencies    prereqs --with-dev
BASHRC_TIMING=1 bash -i     # how long does startup take?
```

Secrets and host-specific aliases (ssh shortcuts, RCON password, Cloudflare tunnel
name, pool name) live in `~/.bashrc.local`, seeded from `bashrc.local.example`.

## Uninstall

```bash
bash ~/.local/share/bashrc-profile/install.sh --uninstall
```
Removes the symlinks and restores the newest `~/.bashrc.bak.*`. Packages stay.

MIT — see [LICENSE](LICENSE).
