# Setup & Customization Guide

Detailed guide to setting up and customizing your bashrc profile.

## Table of Contents

- [Post-Installation](#post-installation)
- [Installing Dependencies](#installing-dependencies)
- [Customization](#customization)
- [Troubleshooting](#troubleshooting)
- [Advanced Configuration](#advanced-configuration)

---

## Post-Installation

### Step 1: Verify Installation
After running the install script, verify everything is working:

```bash
# Check bashrc is installed
cat ~/.bashrc | head -5

# Check shell_functions is installed
cat ~/.shell_functions | head -5

# Verify sourcing
source ~/.bashrc
```

### Step 2: Install Dependencies
The profile includes many features that depend on external tools. Install them:

```bash
install_prereqs    # Or: prereqs
```

This will install:
- System packages via apt/nala
- Starship (shell prompt)
- Zoxide (smart navigation)
- ble.sh (enhanced readline)
- mcrcon (Minecraft RCON)

### Step 3: Customize for Your System
Edit `.bashrc` to match your setup:

```bash
nvim ~/.bashrc
```

Key sections to customize:

#### Editor Preference
```bash
# Line ~88
export EDITOR=nvim          # Change to vim, emacs, nano, etc.
export VISUAL=nvim
```

#### Terminal Application
```bash
# Line ~71
export TERMINAL=/usr/bin/alacritty    # Change to your terminal
```

#### Minecraft RCON Settings
```bash
# Lines ~112-114
export RCON_IP="${RCON_IP:-192.168.2.182}"
export RCON_PORT="${RCON_PORT:-25575}"
export RCON_PASS="${RCON_PASS:-YOUR_PASSWORD}"
```

#### SSH Aliases
```bash
# Lines ~167-171
alias uw='ssh your_user@your_host'
alias nas='ssh your_nas_user@your_nas_ip'
alias pi='ssh your_pi_user@your_pi_ip'
```

#### Config File Shortcuts
```bash
# Lines ~148-152
alias nt='vim ~/.config/nvim/init.lua'    # Edit your nvim config
alias notes='vim /path/to/your/notes'     # Edit your notes location
```

### Step 4: Reload Shell
After customization, reload:

```bash
reload    # Built-in alias
# or
source ~/.bashrc
```

---

## Installing Dependencies

### Quick Install
Install all missing tools:
```bash
install_prereqs    # Smart installer that skips what's already installed
```

### Manual Installation

#### By Category

**Essentials** (Core functionality):
```bash
sudo nala install neovim trash-cli curl git
```

**Terminal & Prompt**:
```bash
sudo nala install alacritty
curl -sS https://starship.rs/install.sh | sh -s -- -y
```

**Navigation & Search**:
```bash
sudo nala install ripgrep tree
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
```

**Development Tools**:
```bash
sudo nala install xclip wireguard-tools bc make gawk gcc valgrind
```

**Minecraft RCON**:
```bash
git clone https://github.com/Tiiffi/mcrcon.git /tmp/mcrcon
cd /tmp/mcrcon && make && sudo make install
```

**ble.sh** (Enhanced readline):
```bash
git clone --recursive --depth 1 --shallow-submodules \
  https://github.com/akinomyoga/ble.sh.git /tmp/ble.sh
cd /tmp/ble.sh && make install PREFIX="$HOME/.local"
```

---

## Customization

### Adding Your Own Aliases

Edit `~/.bashrc` and add to the appropriate section:

```bash
# Example: Add a new development alias
alias myapp='cd ~/my-projects/my-app && nvim'

# Example: Add a docker alias
alias dl='docker logs -f'
```

Reload with `reload` or `source ~/.bashrc`.

### Adding Your Own Functions

Add to `~/.shell_functions`:

```bash
# Example: Simple function
myfunction() {
    echo "Hello from myfunction!"
}

# Example: Function with options
greet() {
    case "$1" in
        -h|--help)
            echo "Usage: greet [name]"
            return 0
            ;;
        "")
            echo "Hello, $(whoami)!"
            ;;
        *)
            echo "Hello, $1!"
            ;;
    esac
}
```

Then reload:
```bash
reload
```

### Modifying Existing Functions

Edit `~/.bashrc` or `~/.shell_functions` and change the function directly:

```bash
# Example: Modify the cd function to not auto-list
cd() {
    if [ -n "$1" ]; then
        builtin cd "$@"
    else
        builtin cd ~
    fi
}
```

Reload with `reload`.

### Changing the Prompt

The prompt is managed by Starship. Customize it:

```bash
nvim ~/.config/starship.toml
```

Common customizations:

```toml
# Change timeout for commands
scan_timeout = 10

# Customize specific modules
[directory]
truncate_to_repo = true
style = "bold blue"

[git_branch]
style = "bold purple"
```

See [Starship docs](https://starship.rs/config/) for full options.

---

## TrueNAS Setup

TrueNAS requires a few extra steps after installation due to its locked-down environment.

> **Note:** If you used `install.sh` in TrueNAS mode, zsh plugins (zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions) are installed automatically to `~/.zsh/`. The steps below are only needed if you installed manually.

### 1. Fix Shell Auto-Sourcing

TrueNAS SSH sessions do not automatically source `~/.zshrc`. Create `~/.zshenv` to fix this:

```bash
echo '[[ -o interactive ]] && [[ -f "$HOME/.zshrc" ]] && source "$HOME/.zshrc"' > ~/.zshenv
```

This file is always read by zsh regardless of how the shell is started.

### 2. Enable exec on Your Home Dataset

TrueNAS sets `exec=off` on the home directory ZFS dataset by default. This silently prevents any binary installed to `~/.local/bin` (starship, zoxide, neovim, etc.) from running.

Check your dataset:
```bash
zfs get exec $(df -P ~/.local | tail -1 | awk '{print $1}')
```

Fix via command line (replace dataset name with what the above command shows):
```bash
sudo zfs set exec=on boot-pool/ROOT/<version>/home
```

Or via **TrueNAS WebUI → Storage → Datasets → (your home dataset) → Edit → Advanced Options → Exec: On**.

> **Note:** TrueNAS system updates may reset this. Re-run the command if binaries stop working after an update.

### 3. Install Tools Manually

Package managers (`apt`/`nala`) are unsupported on TrueNAS. Install tools via curl instead.

**Starship** (prompt):
```bash
curl -sS https://starship.rs/install.sh | sh -s -- --bin-dir ~/.local/bin -y
```

**Zoxide** (smart navigation):
```bash
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
chmod +x ~/.local/bin/zoxide
```

**Neovim** (editor):
```bash
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
tar xzf nvim-linux-x86_64.tar.gz
cp nvim-linux-x86_64/bin/nvim ~/.local/bin/nvim
/bin/rm -rf nvim-linux-x86_64 nvim-linux-x86_64.tar.gz
```

### 4. Reload

```bash
source ~/.zshrc
```

---

## Troubleshooting

### Aliases Not Working

**Problem**: Alias not recognized
```bash
alias myalias='command'    # Added but doesn't work
```

**Solution**:
1. Verify it's in `.bashrc`
2. Reload: `reload` or `source ~/.bashrc`
3. Check for typos: `alias | grep myalias`

### Functions Not Found

**Problem**: "command not found: myfunction"

**Solution**:
1. Make sure it's in `.bashrc` or `.shell_functions`
2. Verify `.bashrc` sources `.shell_functions`:
   ```bash
   grep 'shell_functions' ~/.bashrc
   ```
3. Reload: `reload`

### Command Not Found Errors

**Problem**: "command not found: rg" (or other tool)

**Solution**:
1. Install missing tools: `install_prereqs`
2. Verify installation: `which rg`
3. Check PATH: `path | grep local`

### Slow Shell Startup

**Problem**: Bashrc takes too long to load

**Solution**:
1. Profile startup time:
   ```bash
   time bash -i -c exit
   ```
2. Comment out slow operations (starship, zoxide initialization)
3. Remove unused functions from `.shell_functions`

### Backup Restore Issues

**Problem**: Need to restore from backup

**Solution**:
```bash
# List backups
ls ~/.bashrc.bak.*

# Restore specific backup
cp ~/.bashrc.bak.20260101-120000 ~/.bashrc
cp ~/.shell_functions.bak.20260101-120000 ~/.shell_functions

# Reload
reload
```

### TrueNAS: Binaries Say "permission denied"

**Problem**: Commands like `nvim`, `starship`, or `zoxide` fail with `permission denied` even after `chmod +x`

**Cause**: The home directory ZFS dataset has `exec=off`

**Solution**:
```bash
# Find and fix the dataset
zfs get exec $(df -P ~/.local | tail -1 | awk '{print $1}')
sudo zfs set exec=on boot-pool/ROOT/<version>/home
```

Or enable via TrueNAS WebUI → Storage → Datasets → Edit → Advanced Options → Exec: On.

### TrueNAS: Prompt Doesn't Load on SSH Login

**Problem**: Shell shows default `truenas%` prompt instead of Starship after SSH login

**Cause**: TrueNAS doesn't auto-source `~/.zshrc` for SSH sessions

**Solution**:
```bash
echo '[[ -o interactive ]] && [[ -f "$HOME/.zshrc" ]] && source "$HOME/.zshrc"' > ~/.zshenv
```

Log out and back in. Note: this also requires `exec=on` (see above) for the Starship prompt to appear.

### SSH Aliases Not Working

**Problem**: SSH aliases fail

**Solution**:
1. Check SSH key setup: `ssh-keygen -t ed25519`
2. Verify host in known_hosts: `ssh-keyscan host.com >> ~/.ssh/known_hosts`
3. Test connection: `ssh -v user@host`

### Special Characters in Aliases

**Problem**: Alias with spaces/special chars fails

**Solution**:
```bash
# Wrong:
alias notes='vim /path with spaces.txt'

# Right:
alias notes='vim /path\ with\ spaces.txt'

# Or use single quotes for paths:
alias notes="vim $HOME/my files/notes.txt"
```

### Function Conflicts

**Problem**: Function conflicts with system command

**Solution**:
1. Rename your function:
   ```bash
   mycd() {
       builtin cd "$@" && ls
   }
   ```
2. Use `builtin` for system commands inside functions
3. Check conflicts: `type functionname`

---

## Advanced Configuration

### Environment Variables

Key variables to customize:

```bash
# Editor
export EDITOR=nvim
export VISUAL=nvim

# History
export HISTSIZE=500
export HISTFILESIZE=10000

# Colors
export CLICOLOR=1
export LS_COLORS='...'

# XDG directories
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
```

### Shell Options (shopt)

Configure bash behavior:

```bash
shopt -s histappend      # Append to history file
shopt -s checkwinsize    # Update window size after commands
shopt -s globstar        # ** matches directories recursively
```

### Key Bindings

Customize readline key bindings:

```bash
# In .bashrc:
bind '"\C-l": clear-screen'
bind '"\C-z": undo'
bind '"\C-f":"zi\n"'
```

### History Management

Configure command history:

```bash
export HISTTIMEFORMAT="%F %T "      # Include timestamps
export HISTCONTROL=ignoredups       # Don't repeat same commands
export HISTSIZE=1000                # Commands in memory
export HISTFILESIZE=2000            # Commands in history file
```

### Custom Prompt (Alternative to Starship)

If not using Starship, customize `PS1`:

```bash
PS1='\u@\h:\w\$ '              # Simple: user@host:path$
PS1='\[\033[01;32m\]\u\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '  # Colored
```

### Conditional Configuration

Load settings based on system:

```bash
# In .bashrc:
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux-specific settings
    export EDITOR=nvim
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS-specific settings
    export EDITOR=vim
fi
```

### Performance Optimization

For faster shell startup:

```bash
# Comment out slow initializers
# eval "$(starship init bash)"  # Can slow startup
# eval "$(zoxide init bash)"    # Can slow startup

# Or delay initialization
if [[ -z "${STARSHIP_INIT}" ]]; then
    eval "$(starship init bash)"
    export STARSHIP_INIT=1
fi
```

### Version Control Integration

Add git information to prompt:

```bash
__git_ps1() {
    git rev-parse --git-dir > /dev/null 2>&1 && echo " ($(git rev-parse --abbrev-ref HEAD))"
}

# In PS1:
PS1='\u@\h:\w$(__git_ps1)\$ '
```

---

## Tips for Power Users

### Aliases vs Functions
- Use **aliases** for simple commands
- Use **functions** for commands with logic/conditionals
- Keep aliases simple, functions focused

### Naming Conventions
```bash
alias del='rm'              # Short, memorable
alias ll='ls -lah'          # Common abbreviations
alias mnt='mount'           # Avoid built-in names

function extract_and_cd() { # Descriptive function names
    extract "$1" && cd ...
}
```

### Documentation
```bash
function myfunction() {
    # Brief description
    # Usage: myfunction [options] [args]
    # Options:
    #   -h, --help    Show help

    case "$1" in
        -h|--help)
            echo "Usage: myfunction [option]"
            return 0
            ;;
    esac
    # ... rest of function
}
```

### Debugging
```bash
# Enable debug mode
set -x

# Your commands here

# Disable debug mode
set +x

# Or run single command in debug
bash -x script.sh
```

---

## Further Customization

- **Starship configuration**: `~/.config/starship.toml`
- **Alacritty themes**: `~/.config/alacritty/themes/`
- **Zoxide**: Automatically learns frequently used directories
- **ble.sh**: See `~/.local/share/blesh/` for theme options

For more details, see:
- [FEATURES.md](FEATURES.md) - All aliases and functions
- [README.md](README.md) - Installation and overview

Happy bashing! 🎉
