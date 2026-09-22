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
| `--profile pi\|nas\|desktop\|uw\|server` | skip autodetection |
| `--dry-run` | print every step, change nothing |
| `--yes` | no questions (piped installs on a box without a tty assume yes) |
| `--no-deps` | just link files |
| `--with-dev` | gcc, make, gdb, valgrind, clang (C course work) |
| `--with-blesh` / `--no-blesh` | syntax highlighting + autosuggestions |
| `--with-mcrcon` | build the Minecraft RCON client |
| `--with-zoxide` | install zoxide and turn on `z` / `zi` (off by default) |
| `--upgrade` | refresh the user-local tools (ble.sh nightly, starship, fzf, zoxide) — `prereqs --upgrade` |
| `--update` | pull + relink + add new toggles to the config + clear caches (what `bup` runs) |
| `--uninstall` | remove links, restore backups |

Backups: `~/.bashrc.bak.<timestamp>`, `~/.config/starship.toml.bak.<timestamp>`,
`~/.blerc.bak.<timestamp>`.

## Raspberry Pi (profile `pi`)

Raspberry Pi OS / Debian, headless, reached over ssh. Detected from
`/proc/device-tree/model`.

```bash
bash install.sh --profile pi          # or let it autodetect
```

What is installed: the core list (starship, fzf, ripgrep, neovim, trash-cli,
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
  touch system packages. Everything goes into your home: starship into `~/.local/bin`
  (upstream install script), fzf into `~/.fzf`, ble.sh into `~/.local/share/blesh`
  from the release tarball, so no `make`/`gawk` are needed.
- No `trash-cli`: `rm` becomes `rm -I`. `nvim` is not packaged either — unpack a release
  into `~/nvim-linux-x86_64` and the profile puts it on `PATH` and sets `VIMRUNTIME`.
- Package aliases (`ni`, `nu`, …) are removed by the profile. `wn` (`watch nvidia-smi`)
  appears when the box has an NVIDIA GPU.

```bash
# on the NAS, as your admin user
curl -fsSL https://raw.githubusercontent.com/nicolasfalesy/bashrc-profile/main/install.sh | bash -s -- --profile nas
bt local            # set ZPOOL=porsche (and anything else)
```

Verified on the real box (TrueNAS SCALE, login shell switched from zsh to bash with
`sudo midclt call user.update <uid> '{"shell": "/usr/bin/bash"}'`). Notes:

- Keep the admin user's **home directory on a dataset of your data pool** (Credentials →
  Users → Home Directory). A home on the boot pool can be lost on a TrueNAS upgrade,
  taking `~/.local` and the profile with it.
- If `git` is absent the installer falls back to downloading a tarball; `bup` then
  cannot pull — re-run the curl line instead.
- Nothing here changes middleware-managed files; TrueNAS may still regenerate
  `/etc/*` on upgrade, but `~/.bashrc` and `~/.profile` are yours.
- `dsv` and the `z*` aliases use `sudo zpool`, and `dsv` deletes with `sudo rm` because
  the damaged files usually belong to other users or services.
- Keep the repo on the data pool too (e.g. `/mnt/<pool>/configs/home/bashrc-profile`)
  and point `BASHRC_PROFILE_DIR` at it in `bt config` for the same reason as the home.
- The old zsh setup is kept in `legacy/zshrc` for reference; nothing loads it.
- If the repo sits on a dataset with NFSv4 ACLs and `aclmode=restricted` (the default for
  SMB-shared datasets), `chmod` is refused: git then shows every file as modified and
  `bup`/`git pull` abort, and even `git config` fails writing its lock. Fix once by
  rewriting the config in place (no chmod involved):
  `sed 's/filemode = true/filemode = false/' .git/config > .git/config.new && cat .git/config.new > .git/config && rm .git/config.new`

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

## Omarchy laptop (profile `omarchy`)

Detected from `/usr/share/omarchy`. Arch + Hyprland with Omarchy's own bash setup.

```bash
bash install.sh --profile omarchy --no-blesh
```

Unlike every other profile this one does **not** replace `~/.bashrc`. It appends
a block marked `bashrc-profile: BEGIN` / `END` that sources this repo after
Omarchy's rc chain, so both sets of aliases are live and nothing under
`/usr/share/omarchy` is touched. `install.sh --uninstall` strips the block again.

Packages come from pacman, and only the few Omarchy does not already ship
(`tree`, `trash-cli`, `7zip`, `unrar`, `wireguard-tools`, `desktop-file-utils`).
ble.sh is best left off here: it adds about 205 ms to every new shell.

What it adds on top of Omarchy:

- **Prompt that follows the desktop theme.** `themes/omarchy-auto.toml` names its
  colours, `bin/starship-omarchy-palette` fills them in from the current theme's
  `colors.toml`, and `hooks/50-starship-palette` re-runs it on every
  `omarchy theme set`.
- **Next class in the prompt.** Starship's `[custom.nextclass]` module shows the
  next calendar event when it starts within 90 minutes. It needs an
  `omarchy-next-class` command on `PATH` and a calendar cache at
  `~/.cache/omarchy/gcal.json`; without them the module simply stays hidden.
- **Themed lazygit.** If the current theme has a `lazygit.yml`, `LG_CONFIG_FILE`
  loads it after your own `config.yml`, so it only adds colours.
- **fastfetch card on a new terminal window.** Only in the first shell of a real
  terminal: not in subshells, tmux, SSH or Claude Code sessions. It uses
  `~/.config/fastfetch/config.jsonc`, and is skipped if that file is missing.

## UW student servers (profile `uw`)

`ubuntu2404-0xx.student.cs.uwaterloo.ca` and friends. Detected from a hostname or a
`/etc/resolv.conf` search domain under `uwaterloo.ca`. You have no root there, so the
installer never touches apt: starship, fzf and ble.sh go under your home exactly as
on the NAS. Drop an nvim release into `~/.local` if you want it.

```bash
git clone https://github.com/nicolasfalesy/bashrc-profile ~/bashrc-profile
bash ~/bashrc-profile/install.sh --profile uw
```

What is different: the **Waterloo Gold** starship theme (`themes/waterloo-gold.toml`) is linked
instead of Aurora, `~/bin` is on `PATH`, `rm` is `rm -iv` (no trash-cli), the package
and `sudo` aliases are removed. The C helpers (`ru`, `run`, `rut`, `mkt`) work as
everywhere else; `gcc`/`valgrind` are already on the school machines. Put the
`home-pc` ssh alias in `~/.bashrc.local` (it is in the template).

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

**Startup got slow** — `BASHRC_TIMING=1 bash -i` in a real terminal for the total
(6–8 ms on the NAS, ~22 ms on the Pi, plus whatever ble.sh's attach costs on that
terminal). `BASHRC_BLESH=0 bash -i` shows the number without ble.sh.
`PS4='+ $EPOCHREALTIME ${BASH_SOURCE##*/}:$LINENO ' bash -xic exit 2>&1 | less` gives a
line-by-line trace (ble.sh excluded — it refuses `bash -c`). Stale caches:
`rm ~/.cache/bashrc-profile/*.bash`.

**Something broke after an edit** — `bt` refuses to reload a file that does not
parse and says so; fix it and save again. `bash "$BASHRC_PROFILE_DIR/tests/smoke.sh"`
exercises every profile in a sandbox. An older `~/.bashrc.bak.*` is always there.

**A toggle in `bt config` seems ignored** — the environment wins over the file:
`env | grep BASHRC_` shows what is exported in this session.

**Docker aliases missing** — `docker` is not in PATH, or you are not in the docker
group (then they use `sudo`).

**Restore the previous config** — `install.sh --uninstall`, or copy the newest
`~/.bashrc.bak.*` back by hand.
