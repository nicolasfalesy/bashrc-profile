# bashrc-profile

A fully-featured, well-organized shell configuration with 60+ aliases and 35+ custom functions designed for power users. Supports both **bash** (Linux/Raspberry Pi) and **zsh** (TrueNAS).

## Quick Start

### One-Line Install
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nicolasfalesy/bashrc-profile/main/install.sh)
```

The installer will ask if you're on TrueNAS — answer `y` for a zsh-compatible install, or `n` for the standard bash install.

### Manual Install
```bash
git clone https://github.com/nicolasfalesy/bashrc-profile.git
cd bashrc-profile
bash install.sh
```

## Features

- **60+ carefully curated aliases** for common tasks (Docker, package management, SSH, Git, etc.)
- **35+ custom shell functions** for navigation, file operations, networking, system info, and more
- **Organized structure** with clear sections and comments
- **Color-coded output** for better readability
- **Compatible with modern tools** (ripgrep, nala, starship, zoxide, ble.sh)
- **Aurora prompt theme** — Tokyo Night palette with rounded pill-shaped powerline segments, git status, language detection, and right-aligned system info
- **TrueNAS / zsh support** — dedicated zshrc with zsh-native options and no apt/nala dependencies

## Installation Options

### Option 1: Curl Install (Recommended)
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nicolasfalesy/bashrc-profile/main/install.sh)
```

### Option 2: Clone & Install
```bash
git clone https://github.com/nicolasfalesy/bashrc-profile.git
cd bashrc-profile
bash install.sh
```

### Option 3: Manual Install
```bash
# Standard bash
cp bashrc ~/.bashrc
cp shell_functions ~/.shell_functions
cp starship.toml ~/.config/starship.toml
source ~/.bashrc

# TrueNAS / zsh
cp zshrc ~/.zshrc
cp shell_functions ~/.shell_functions
cp starship.toml ~/.config/starship.toml
source ~/.zshrc
```

## TrueNAS Install

When prompted `Are you installing on TrueNAS? [y/N]`, answer `y`. This will:

- Install `zshrc` → `~/.zshrc` instead of `~/.bashrc`
- Skip all `apt`/`nala` package manager steps (unsupported on TrueNAS)
- Use `starship init zsh` and `zoxide init zsh`
- Install zsh plugins: zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions

### Post-Install Steps for TrueNAS

**1. Fix shell auto-sourcing** — TrueNAS doesn't auto-source `~/.zshrc` on SSH login. Run this once:
```bash
echo '[[ -o interactive ]] && [[ -f "$HOME/.zshrc" ]] && source "$HOME/.zshrc"' > ~/.zshenv
```

**2. Enable exec on your home ZFS dataset** — TrueNAS sets `exec=off` on the home dataset by default, which prevents any binary in `~/.local/bin` from running (starship, zoxide, nvim, etc.):
```bash
# Check your dataset name
zfs get exec $(df -P ~/.local | tail -1 | awk '{print $1}')

# Enable exec (replace with your actual dataset name)
sudo zfs set exec=on boot-pool/ROOT/25.10.2.1/home
```
Or do it via **TrueNAS WebUI → Storage → Datasets → (your home dataset) → Edit → Advanced Options → Exec: On**.

> **Note:** This may need to be re-applied after a TrueNAS system update.

**3. Install starship** (prompt):
```bash
curl -sS https://starship.rs/install.sh | sh -s -- --bin-dir ~/.local/bin -y
```

**4. Install zoxide** (smart navigation):
```bash
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
chmod +x ~/.local/bin/zoxide
```

**5. Install neovim** (editor, no apt needed):
```bash
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
tar xzf nvim-linux-x86_64.tar.gz
cp nvim-linux-x86_64/bin/nvim ~/.local/bin/nvim
/bin/rm -rf nvim-linux-x86_64 nvim-linux-x86_64.tar.gz
```

**6. Reload:**
```bash
source ~/.zshrc
```

## Install Script Features

The `install.sh` script handles:
- ✅ **TrueNAS detection** — asks at startup and installs the right config for your system
- ✅ **Automatic backups** — creates timestamped backups of existing config files
- ✅ **Dry-run mode** — preview changes before applying with `bash install.sh --dry-run`
- ✅ **Fresh & update installs** — supports both new installations and updates
- ✅ **Automatic reload** — reloads your shell after installation (or notifies you to restart)
- ✅ **Starship prompt** — installs the custom Aurora theme to `~/.config/starship.toml` (Tokyo Night palette, rounded pill-shaped powerline segments)
- ✅ **ZSH plugins** — installs zsh-autosuggestions, zsh-syntax-highlighting, and zsh-completions for TrueNAS

## What's Included

### Aliases
- **Editor**: vim, vi, svim, svi, snvim
- **Docker**: du, dd, dr
- **Package Management**: apt, np, ni, nfi, nf, nu *(bash only — skipped on TrueNAS)*
- **Config Shortcuts**: kt, bt, nt, notes, reload, e, c
- **Scripts & Mounts**: mnt, umount, bk
- **SSH**: uw, nas, pi
- **Drive Management**: sv *(zsh/TrueNAS only)*
- **NVIDIA**: wn *(zsh/TrueNAS only)*
- **Core Commands**: cp, mv, rm, mkdir, ps, ping, etc.
- **Filesystem**: ll, l, tree, treed, folders, folderssort, mnts
- **Permissions**: mx, 000, 600, 666, 700, 777
- **Search**: grep, h, f, countfiles, ports

### Functions
- **Navigation**: cd (auto-ls), up, cpg, mvg, mkdirg
- **File Operations**: extract, ftext, size
- **Networking**: whatsmyip, pubip, vpn
- **Clipboard**: cpy, pst
- **System**: sys, apps, install_app
- **Theme Manager**: at (Alacritty themes)
- **GRUB Management**: grub
- **Minecraft RCON**: rcon, rc
- **Cloudflare Tunnel**: cloud
- **Prerequisites Installer**: install_prereqs, prereqs *(bash only)*
- **Shell Functions**: mkcd, psg, port, weather, take, path, bak, diff2, tre, note
- **CS136 C Programming**: ru, run, rut, mkt *(requires clang)*
- **ZFS Utilities**: dsv *(requires zpool)*

## Configuration

### Environment Variables
Edit `~/.bashrc` (or `~/.zshrc` on TrueNAS) to customize:
- `EDITOR` - Your preferred editor (default: nvim)
- `RCON_IP`, `RCON_PORT`, `RCON_PASS` - Minecraft server settings
- `TERMINAL` - Terminal application (default: alacritty)

### Aliases & Functions
All aliases and functions are in `~/.bashrc`/`~/.zshrc` and `~/.shell_functions`. Edit them directly to customize for your workflow.

## Dependencies

The profile works best with:
- **fastfetch** - System info display
- **neovim** - Editor
- **starship** - Shell prompt
- **zoxide** - Smart directory navigation
- **ripgrep** - Fast grep alternative
- **trash-cli** - Safe file deletion
- **alacritty** - GPU-accelerated terminal
- **ble.sh** - Enhanced readline *(bash only)*
- **clang** - C compiler for CS136 functions

Run `install_prereqs` (or `prereqs`) to install missing dependencies. *(Not available on TrueNAS.)*

## Uninstall

To restore your previous configuration:
```bash
# Find your backup
ls ~/.bashrc.bak.*
ls ~/.shell_functions.bak.*

# Restore
cp ~/.bashrc.bak.YYYYMMDD-HHMMSS ~/.bashrc
cp ~/.shell_functions.bak.YYYYMMDD-HHMMSS ~/.shell_functions

# Reload
source ~/.bashrc
```

## Customization

1. **Add new aliases**: Add them to the appropriate section in `~/.bashrc` or `~/.zshrc`
2. **Add new functions**: Add them to `~/.shell_functions` or `~/.bashrc`
3. **Modify existing settings**: Edit the `ENVIRONMENT VARIABLES` section
4. **Prompt**: Edit `~/.config/starship.toml` to customize the Starship prompt. The Aurora theme uses rounded powerline caps (`\uE0B6` / `\uE0B4`) and a Tokyo Night palette — segments can be recolored by updating the hex values in each `[section]`.

See [FEATURES.md](FEATURES.md) for detailed documentation of all aliases and functions.

## Troubleshooting

### Command not found errors
- Run `install_prereqs` to install missing dependencies (bash only)
- Verify the command is in your PATH: `which command_name`

### Aliases/functions not working
- Make sure `~/.shell_functions` is in your home directory
- Verify your rc file sources `.shell_functions` correctly
- Reload with `source ~/.bashrc` (or `source ~/.zshrc`) or use the `reload` alias

### Backup issues
- Backups are saved with timestamp: `.bashrc.bak.YYYYMMDD-HHMMSS`
- Find them with: `ls -la ~/ | grep bak`

## License

MIT License - See [LICENSE](LICENSE) file for details

## Contributing

Found a bug or want to add a feature? Open an issue or pull request!

## Support

For detailed documentation on all aliases and functions, see [FEATURES.md](FEATURES.md).

For setup and customization tips, see [SETUP.md](SETUP.md).
