# Setup by machine

## Any machine — the short version

```bash
curl -fsSL https://raw.githubusercontent.com/nicolasfalesy/bashrc-profile/main/install.sh | bash
bt local        # fill in secrets / ssh hosts
exec bash
```

The installer asks one question. Useful flags:

| Flag | Effect |
|------|--------|
| `--profile pi\|nas\|desktop\|server` | skip autodetection |
| `--dry-run` | print every step, change nothing |
| `--yes` | no questions (piped installs on a box without a tty assume yes) |
| `--no-deps` | just link files |
| `--with-dev` | gcc, make, gdb, valgrind, clang (C course work) |
| `--with-blesh` / `--no-blesh` | syntax highlighting + autosuggestions |
| `--with-mcrcon` | build the Minecraft RCON client |
| `--update` | pull + relink + clear caches (same as `bup`) |
| `--uninstall` | remove links, restore backups |

Backups: `~/.bashrc.bak.<timestamp>`, `~/.config/starship.toml.bak.<timestamp>`,
`~/.blerc.bak.<timestamp>`.

## Raspberry Pi (profile `pi`)

Raspberry Pi OS / Debian, headless, reached over ssh. Detected from
`/proc/device-tree/model`.

```bash
bash install.sh --profile pi          # or let it autodetect
```

What is installed: the core list (starship, zoxide, fzf, ripgrep, neovim, trash-cli,
tmux, htop, tree, archive tools) via **nala** (installed first if missing), plus
`raspi-utils` for `vcgencmd` and `wireguard-tools`. Docker and cloudflared are *not*
installed for you — the installer only warns if they are missing.

Defaults: ble.sh on (highlighting, autosuggestions, menu completion; ~30 ms at
start), fastfetch off. Flip either in `bt config`. `blerc` delays suggestions by
100 ms after a keystroke so a Pi over ssh does not recompute on every key; raise
`complete_auto_delay` there if it ever feels laggy.

`cloud <sub>` needs `CF_TUNNEL` and `CF_DOMAIN` in `~/.bashrc.local`.

Ssh logins are *login shells*: `/etc/profile` already loads bash-completion, and the
profile notices and skips it. Your terminal on the client side needs a Nerd Font for
the starship icons (the font lives where the terminal runs, not on the Pi).

## TrueNAS SCALE (profile `nas`)

Detected from `/usr/share/truenas` or `/usr/bin/midclt`. TrueNAS SCALE is Debian with:

- `/` mounted **read-only** and `apt` deliberately disabled → the installer does not
  touch system packages. Everything goes into your home: starship and zoxide into
  `~/.local/bin` (upstream install scripts), fzf into `~/.fzf`, ble.sh (if asked) into
  `~/.local/share/blesh` from the release tarball, so no `make`/`gawk` are needed.
- No `nvim`, no `trash-cli`: `EDITOR` falls back to `vim`/`nano`, `rm` becomes `rm -I`.
- Package aliases (`ni`, `nu`, …) are removed by the profile.

```bash
# on the NAS, as your admin user
curl -fsSL https://raw.githubusercontent.com/nicolasfalesy/bashrc-profile/main/install.sh | bash -s -- --profile nas
bt local            # set ZPOOL=porsche (and anything else)
```

Notes / caveats (not verified on the box while this was written — the NAS's ssh host
key had changed; see AUDIT.md):

- Keep the admin user's **home directory on a dataset of your data pool** (Credentials →
  Users → Home Directory). A home on the boot pool can be lost on a TrueNAS upgrade,
  taking `~/.local` and the profile with it.
- If `git` is absent the installer falls back to downloading a tarball; `bup` then
  cannot pull — re-run the curl line instead.
- Nothing here changes middleware-managed files; TrueNAS may still regenerate
  `/etc/*` on upgrade, but `~/.bashrc` and `~/.profile` are yours.
- `dsv` and the `z*` aliases use `sudo zpool`; the admin user has sudo on SCALE.

## Laptop / desktop (profile `desktop`)

Detected from `$DISPLAY` / `$WAYLAND_DISPLAY`. Ubuntu or Debian.

```bash
bash install.sh --profile desktop --with-dev
```

Adds Alacritty, clipboard tools (`wl-clipboard` + `xclip`), WireGuard, emoji font and
downloads **MesloLGS Nerd Font** into `~/.local/share/fonts` — select it in your
terminal so the prompt glyphs render. ble.sh and fastfetch are on by default.

`vpn` expects a WireGuard config at `/etc/wireguard/wg0.conf`. `note`/`notes` default to
`~/Nextcloud/…`; change `NOTES_FILE` in `~/.bashrc.local`.

## Generic server (profile `server`)

Anything else (VPS, the school Ubuntu box). Core packages via apt if you have sudo,
user-local fallbacks otherwise. `profiles/server.sh` is empty — add what you need.

## Secrets and hosts: `~/.bashrc.local`

Seeded from `bashrc.local.example` on first install, mode 600, ignored by git. Holds:
ssh aliases (`uw`, `nas`, `pi`), `RCON_*`, `CF_TUNNEL`/`CF_DOMAIN`, `ZPOOL`,
`WEATHER_LOCATION`, `NOTES_FILE`. Edit with `bt local`.

Consider moving the ssh aliases to `~/.ssh/config`:

```
Host nas
    HostName 192.168.2.182
    User truenas_admin
Host pi
    HostName 192.168.2.181
    User raspby
```
That also gives you `scp file nas:` and host tab-completion.

## Troubleshooting

**Prompt shows boxes / question marks** — the terminal font is not a Nerd Font.
Install MesloLGS NF where the terminal runs.

**"command not found: ll" inside a script** — the profile only loads in interactive
shells; scripts should call `ls` directly.

**Tab completion seems dead for the first press** — that first Tab loads
bash-completion (lazy loading). Set `BASHRC_LAZY_COMPLETION=0` in `bt config` to load
it at startup instead.

**Startup got slow** — `BASHRC_TIMING=1 bash -i` for the total;
`PS4='+ $EPOCHREALTIME ${BASH_SOURCE##*/}:$LINENO ' bash -xic exit 2>&1 | less` for a
line-by-line trace. Stale caches: `rm ~/.cache/bashrc-profile/*.bash`.

**Docker aliases missing** — `docker` is not in PATH, or you are not in the docker
group (then they use `sudo`).

**Restore the previous config** — `install.sh --uninstall`, or copy the newest
`~/.bashrc.bak.*` back by hand.
