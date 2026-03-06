# bashrc-profile

A fully-featured, well-organized bash configuration with 40+ aliases and 25+ custom functions designed for power users.

## Quick Start

### One-Line Install
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/bashrc-profile/main/install.sh | bash
```

### Manual Install
```bash
git clone https://github.com/YOUR_USERNAME/bashrc-profile.git
cd bashrc-profile
bash install.sh
```

## Features

- **40+ carefully curated aliases** for common tasks (Docker, package management, SSH, Git, etc.)
- **25+ custom shell functions** for navigation, file operations, networking, system info, and more
- **Organized structure** with clear sections and comments
- **Bash completions** for complex functions
- **Color-coded output** for better readability
- **Compatible with modern tools** (ripgrep, nala, starship, zoxide, ble.sh)

## Installation Options

### Option 1: Curl Install (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/bashrc-profile/main/install.sh | bash
```

### Option 2: Clone & Install
```bash
git clone https://github.com/YOUR_USERNAME/bashrc-profile.git
cd bashrc-profile
bash install.sh
```

### Option 3: Manual Install
```bash
# Copy files to home directory
cp bashrc ~/.bashrc
cp shell_functions ~/.shell_functions

# Reload shell
source ~/.bashrc
```

## Install Script Features

The `install.sh` script handles:
- ✅ **Automatic backups** - Creates timestamped backups of existing `.bashrc` and `.shell_functions`
- ✅ **Dry-run mode** - Preview changes before applying with `bash install.sh --dry-run`
- ✅ **Fresh & update installs** - Supports both new installations and updates to existing setups
- ✅ **Automatic reload** - Reloads your shell after installation (or notifies you to restart)
- ✅ **Prerequisites check** - Verifies dependencies

## What's Included

### Aliases
- **Editor**: vim, vi, svim, svi, snvim
- **Docker**: du, dd, dr
- **Package Management**: apt, np, ni, nfi, nf, nu
- **Config Shortcuts**: kt, bt, nt, notes
- **SSH**: uw, nas, pi
- **Core Commands**: cp, mv, rm, mkdir, ps, ping, etc.
- **Filesystem**: ll, l, tree, folders, mnts
- **Permissions**: mx, 000, 600, 666, 700, 777
- **Search**: grep, h, f, countfiles, ports
- And more!

### Functions
- **Navigation**: cd (auto-ls), up, cpg, mvg, mkdirg
- **File Operations**: extract, ftext, size (with completion)
- **Networking**: whatsmyip, pubip, vpn
- **Clipboard**: cpy, pst
- **System**: sys, apps, install_app
- **Theme Manager**: at (Alacritty themes)
- **GRUB Management**: grub
- **Minecraft RCON**: rcon, rc (with command completion)
- **Cloudflare Tunnel**: cloud
- **Prerequisites Installer**: install_prereqs, prereqs
- **Shell Functions**: mkcd, psg, port, weather, take, path, bak, diff2, tre, note

## Configuration

### Environment Variables
Edit `.bashrc` to customize:
- `EDITOR` - Your preferred editor (default: nvim)
- `RCON_IP`, `RCON_PORT`, `RCON_PASS` - Minecraft server settings
- `TERMINAL` - Terminal application (default: alacritty)

### Aliases & Functions
All aliases and functions are in the `.bashrc` and `.shell_functions` files. Edit them directly to customize for your workflow.

## Dependencies

The profile works best with:
- **fastfetch** - System info display
- **neovim** - Editor
- **starship** - Shell prompt
- **zoxide** - Smart directory navigation
- **ripgrep** - Fast grep alternative
- **trash-cli** - Safe file deletion
- **alacritty** - GPU-accelerated terminal
- **ble.sh** - Enhanced readline

Run `install_prereqs` (or `prereqs`) to install missing dependencies.

## Uninstall

To restore your previous bash configuration:
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

1. **Add new aliases**: Add them to the appropriate section in `.bashrc`
2. **Add new functions**: Add them to `.shell_functions` or `.bashrc`
3. **Modify existing settings**: Edit the `ENVIRONMENT VARIABLES` section
4. **Create custom themes**: Customize colors and prompt in `.bashrc`

See [FEATURES.md](FEATURES.md) for detailed documentation of all aliases and functions.

## Troubleshooting

### Command not found errors
- Run `install_prereqs` to install missing dependencies
- Verify the command is in your PATH: `which command_name`

### Aliases/functions not working
- Make sure `.shell_functions` is in your home directory
- Verify `.bashrc` sources `.shell_functions` correctly
- Reload with `source ~/.bashrc` or `reload` alias

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
