# bashrc-profile Features

Complete reference for all 40+ aliases and 25+ custom functions.

## Table of Contents

- [Aliases](#aliases)
  - [Editor](#editor)
  - [Docker](#docker)
  - [Package Management](#package-management)
  - [Configuration Shortcuts](#configuration-shortcuts)
  - [SSH](#ssh)
  - [Core Commands](#core-commands)
  - [Listing & Filesystem](#listing--filesystem)
  - [Permissions](#permissions)
  - [Search & Info](#search--info)
  - [System](#system)
- [Functions](#functions)
  - [Navigation](#navigation)
  - [File Operations](#file-operations)
  - [Networking & VPN](#networking--vpn)
  - [Clipboard](#clipboard)
  - [System & Applications](#system--applications)
  - [Theme Manager](#theme-manager)
  - [GRUB Management](#grub-management)
  - [Minecraft RCON](#minecraft-rcon)
  - [Cloudflare Tunnel](#cloudflare-tunnel)
  - [Prerequisites](#prerequisites)
  - [Shell Functions](#shell-functions-from-shell_functions-file)
  - [CS136 C Programming & Test Suite](#cs136-c-programming--test-suite)

---

## Aliases

### Editor
| Alias | Command | Purpose |
|-------|---------|---------|
| `vim` | `nvim` | Use Neovim instead of Vim |
| `vi` | `nvim` | Use Neovim instead of Vi |
| `svim` | `sudo nvim` | Sudo Neovim |
| `svi` | `sudo nvim` | Sudo Vi (Neovim) |
| `snvim` | `sudo nvim` | Sudo Neovim |

### Docker
| Alias | Command | Purpose |
|-------|---------|---------|
| `du` | `sudo docker compose up -d` | Docker Compose up (detached) |
| `dd` | `sudo docker compose down` | Docker Compose down |
| `dr` | `sudo docker compose down && sudo docker compose up -d` | Docker Compose restart |

### Package Management
| Alias | Command | Purpose |
|-------|---------|---------|
| `apt` | `sudo nala` | Apt using nala |
| `apt-get` | `sudo nala` | Apt-get using nala |
| `np` | `sudo nala purge` | Nala purge (remove + clean) |
| `ni` | `sudo nala install ` | Nala install |
| `nfi` | `sudo nala install --update ` | Nala install with update |
| `nf` | `sudo nala full-upgrade -y` | Nala full upgrade |
| `nu` | `nf` | Nala upgrade (alias to nf) |

### Configuration Shortcuts
| Alias | Command | Purpose |
|-------|---------|---------|
| `kt` | `vim ~/.config/alacritty/keybinds.toml` | Edit Alacritty keybinds |
| `bt` | `vim +102 ~/.bashrc` | Edit bashrc (jumps to line 102) |
| `nt` | `vim ~/.config/nvim/init.lua` | Edit Neovim config |
| `notes` | `vim $HOME/Nextcloud/constant\ notes.txt` | Edit notes file |
| `reload` | `source ~/.bashrc && echo "🚀 Bash config reloaded!"` | Reload shell config |
| `e` | `exit` | Quick exit |
| `c` | `clear` | Clear screen |

### SSH
| Alias | Command | Purpose |
|-------|---------|---------|
| `uw` | `ssh nfalesy@ubuntu2404-010.student.cs.uwaterloo.ca` | UW student server |
| `nas` | `ssh truenas_admin@192.168.2.182` | NAS server |
| `pi` | `ssh raspby@192.168.2.181` | Raspberry Pi |

### Core Commands
| Alias | Command | Purpose |
|-------|---------|---------|
| `cp` | `cp -i` | Copy with confirmation |
| `mv` | `mv -i` | Move with confirmation |
| `rm` | `trash -v` | Delete to trash (safe) |
| `mkdir` | `mkdir -p` | Create with parents |
| `ps` | `ps auxf` | Process list (formatted) |
| `ping` | `ping -c 10` | Ping 10 times |
| `home` | `cd ~` | Go home |
| `cd..` | `cd ..` | Go up one level |
| `bd` | `cd "$OLDPWD"` | Back to last directory |
| `rmd` | `/bin/rm --recursive --force --verbose ` | Force remove (dangerous) |
| `k9` | `pkill` | Kill process by name |
| `da` | `date "+%Y-%m-%d %A %T %Z"` | Date with details |

### Listing & Filesystem
| Alias | Command | Purpose |
|-------|---------|---------|
| `ll` | `ls -AFlsh --color=auto` | Long listing (all, formatted) |
| `l` | `ll` | Alias to ll |
| `tree` | `tree -CAhF --dirsfirst` | Tree view (custom formatting) |
| `treed` | `tree -CAFd` | Tree view (directories only) |
| `folders` | `du -h --max-depth=1` | Folder sizes (current level) |
| `folderssort` | `find . -maxdepth 1 -type d ... \| sort -rn` | Sorted folder sizes |
| `mnts` | `df -hT` | Mount points and disk usage |

### Permissions
| Alias | Command | Purpose |
|-------|---------|---------|
| `mx` | `chmod a+x` | Make executable |
| `000` | `sudo chmod -R 000 ` | Remove all permissions |
| `600` | `sudo chmod -R 600 ` | Owner read/write only |
| `666` | `sudo chmod -R 666 ` | Everyone read/write |
| `700` | `sudo chmod -R 700 ` | Owner rwx only |
| `777` | `sudo chmod -R 777 ` | Everyone rwx |

### Search & Info
| Alias | Command | Purpose |
|-------|---------|---------|
| `grep` | `rg` or `/usr/bin/grep` | Ripgrep if available, else grep |
| `h` | `history \| grep ` | Search history |
| `f` | `find . \| grep ` | Find files |
| `countfiles` | Find all file types recursively | Count files/links/dirs |
| `ports` | `netstat -nape --inet` | Show listening ports |

### System
| Alias | Command | Purpose |
|-------|---------|---------|
| `rebootsafe` | `sudo shutdown -r now` | Safe reboot |
| `rebootforce` | `sudo shutdown -r -n now` | Force reboot (no sync) |
| `linutil` | `curl -fsSL https://christitus.com/linux \| sh` | LinuxToolbox installer |

---

## Functions

### Navigation

#### `cd [directory]`
Automatically list directory contents after changing directory.
```bash
cd ~             # Changes to home and runs 'll'
cd               # Changes to home and lists
```

#### `up [levels]`
Go up multiple directory levels.
```bash
up 3             # Go up 3 directories
up 1             # Go up 1 directory
```

#### `cpg <file> <directory>`
Copy file and jump to destination directory.
```bash
cpg config.yml /etc/      # Copy and cd into /etc
```

#### `mvg <file> <destination>`
Move file and jump to destination directory.
```bash
mvg old-name.txt ~/backup/   # Move and cd into ~/backup
```

#### `mkdirg <directory>`
Create directory (with parents) and jump into it.
```bash
mkdirg ~/projects/my-app     # Create and cd
```

### File Operations

#### `extract <file>`
Extract archive files (supports 10+ formats).
```bash
extract archive.tar.gz       # Auto-detects format
extract file.zip
extract file.rar
```
**Supported formats**: .tar.bz2, .tar.gz, .bz2, .rar, .gz, .tar, .tbz2, .tgz, .zip, .Z, .7z

#### `ftext <pattern>`
Search for text in all files in current directory (recursive, colored).
```bash
ftext "TODO"                 # Find all TODOs
ftext "function_name"        # Find function definitions
```

#### `size [OPTIONS] [DIRECTORY...]`
Show directory size with auto-unit detection.
```bash
size                         # Size of current dir
size /var/log                # Size of /var/log
size --size G /var           # Force GiB units
size /var/log /tmp           # Multiple dirs + total
```

### Networking & VPN

#### `whatsmyip`
Show internal and external IP addresses.
```bash
whatsmyip                    # Shows both IPs
```

#### `pubip`
Show only public (external) IP address.
```bash
pubip                        # Just the external IP
```

#### `vpn [OPTION]`
Manage WireGuard VPN connection.
```bash
vpn                          # Connect to VPN
vpn -s                       # Show status
vpn -d                       # Disconnect
vpn -h                       # Show help
```

### Clipboard

#### `cpy [text]`
Copy text to clipboard (argument or stdin).
```bash
cpy "hello world"            # Copy argument
echo "text" | cpy            # Copy from stdin
```

#### `pst`
Paste clipboard contents to stdout.
```bash
pst                          # Print clipboard
pst | wc -w                  # Pipe clipboard
```

### System & Applications

#### `sys`
Show system status (CPU, RAM, disk, IP, battery).
```bash
sys                          # Display system info
```

#### `apps [OPTION]`
Manage local applications.
```bash
apps                         # CD to ~/.local/share/applications
apps -u                      # Update desktop database
```

#### `install_app <path>`
Link desktop files to local applications.
```bash
install_app /path/to/app.desktop    # Link app
install_app -l                      # List apps
install_app -l query                # Filter apps
```

### Theme Manager

#### `at [OPTION]`
Manage Alacritty themes.
```bash
at                           # Open Alacritty config
at -l                        # List themes
at -l dracula                # Filter themes
at -t dracula                # Set theme
```

### GRUB Management

#### `grub [OPTION]`
Manage GRUB boot loader.
```bash
grub                         # Update GRUB
grub -e                      # Edit GRUB config
grub -t /path/to/theme       # Install theme
grub -d                      # CD to GRUB themes dir
```

### Minecraft RCON

#### `rcon <command> [args...]`
Send commands to Minecraft server via RCON.
```bash
rcon list                    # List players
rcon say Hello everyone!     # Broadcast message
rcon whitelist add Steve     # Add to whitelist
rc tp Player1 Player2        # Teleport player
```

**Environment variables**:
- `RCON_IP` (default: 192.168.2.182)
- `RCON_PORT` (default: 25575)
- `RCON_PASS` (required)

### Cloudflare Tunnel

#### `cloud <subdomain>`
Create Cloudflare tunnel DNS route.
```bash
cloud myapp                  # Creates myapp.nicolasfalesy.com
```

### Prerequisites

#### `install_prereqs` / `prereqs`
Install all missing dependencies for this bashrc profile.
```bash
install_prereqs              # Install everything missing
prereqs                      # Same thing (alias)
install_prereqs -h           # Show help
```

**Installs**:
- APT packages: fastfetch, neovim, trash-cli, ripgrep, xclip, alacritty, wireguard-tools, curl, net-tools, tree, bc, git, make, gawk
- Special: nala, starship, zoxide, mcrcon (from source), ble.sh (from source)

---

## Shell Functions (from shell_functions file)

### Shell Functions

#### `mkcd <directory>`
Create directory and immediately CD into it.
```bash
mkcd ~/my-project            # Create and enter
mkcd /tmp/deep/nested/dir    # Create parents too
```

#### `psg <pattern> [pattern2...]`
Search running processes by name.
```bash
psg docker                   # Find docker processes
psg nginx postgres           # Find multiple patterns
```
**Output**: Count, header, process list

#### `port [PORT...]`
Show what's listening on a port.
```bash
port                         # List all listening ports
port 80                      # What's on port 80?
port 80 443 8080             # Check multiple ports
```

#### `weather [OPTIONS] [LOCATION]`
Show weather for a location (via wttr.in).
```bash
weather                      # Waterloo, ON (default)
weather Toronto              # Toronto weather
weather -s                   # Short format (current location)
weather -s Paris             # Short format (Paris)
```

#### `take <url|directory>`
Download and extract archive, or create directory.
```bash
take https://example.com/file.tar.gz    # Download & extract
take my-project                         # Create dir
```

#### `path [OPTIONS] [pattern]`
Pretty-print PATH or search entries.
```bash
path                         # List all PATH entries
path cargo                   # Find cargo in PATH
path -c                      # Count entries
```

#### `bak <file> [file2...]`
Create timestamped backup of files.
```bash
bak config.yml               # Creates config.yml.bak.YYYYMMDD-HHMMSS
bak file1.txt file2.txt      # Backup multiple
bak -r file.bak.20260101-120000    # Restore backup
```

#### `diff2 <file1> <file2>`
Side-by-side colored diff.
```bash
diff2 old.conf new.conf      # Compare configs
diff2 ~/.bashrc ~/.bashrc.bak   # Compare bashrc
```

#### `tre [DEPTH] [DIRECTORY]`
Tree with ignores (.git, node_modules, etc.).
```bash
tre                          # 3 levels, current dir
tre 2                        # 2 levels deep
tre 5 /etc                   # 5 levels in /etc
```

#### `note [OPTIONS] [text...]`
Quick scratchpad notes (saved to ~/Nextcloud/quick-notes.txt).
```bash
note Remember to update configs    # Add note
note -l                            # List all notes
note -e                            # Edit notes
note -c                            # Clear notes
```

### CS136 C Programming & Test Suite

> **Requires:** `clang` (install via `prereqs` or `sudo nala install clang`)

#### `ru [-f FILE]`
Compile `main.c` (or a specified file) with CS136 course flags.
```bash
ru                           # Compile main.c
ru -f solution.c             # Compile solution.c
```

#### `run [-f FILE]`
Compile and immediately run the program.
```bash
run                          # Compile and run main.c
run -f solution.c            # Compile and run solution.c
```

#### `rut [-v] [-f FILE]`
Compile and run all test cases in the current directory. Tests are defined by file stems with `.in`, `.expect`, and optional `.args` files.
```bash
rut                          # Compile and test
rut -v                       # Verbose (show passing test details)
rut -v -f sol.c              # Compile sol.c, verbose test run
```
**Test file format**: For a stem `foo`:
- `foo.in` — stdin input (optional)
- `foo.expect` — expected output (required)
- `foo.args` — command-line arguments (optional)

#### `mkt [-a] <stem> [stem2...]`
Create test case file pairs for the test runner.
```bash
mkt basic                    # Creates basic.in, basic.expect
mkt test1 test2              # Creates files for both stems
mkt -a with-args             # Also creates .args file
```

---

## Tips & Tricks

### Combining Functions
```bash
# Navigate to a downloaded file and extract it
take https://github.com/user/repo/archive/main.zip

# Backup before editing
bak ~/.bashrc && nvim ~/.bashrc

# Check what's listening, then show connections
port 8080 && psg node

# Show disk usage sorted
folders | sort -rn
```

### Shell Reload
After editing `.bashrc`, reload with:
```bash
reload    # Built-in alias
# or
source ~/.bashrc
```

### Tab Completion
Many functions have tab completion:
- `size` - directory names
- `rcon` - minecraft commands
- `bak` - filenames
- `port` - port numbers
- `weather` - options
- `path` - options
- `note` - options
- `psg` - options
- `rut` / `run` / `ru` - options, `.c` files
- `mkt` - options

### Performance Tips
- Use `rg` (ripgrep) for searching: it's ~3x faster than grep
- Use `mkcd` instead of `mkdir` + `cd` separately
- Use `take` for downloading archives (auto-extracts)
- Use `tre` instead of `tree` (pre-filtered)

---

## Customization

Want to add your own aliases or functions?

1. **Aliases**: Edit `.bashrc`, find appropriate section
2. **Functions**: Add to `.shell_functions` for better organization
3. **Settings**: Edit `ENVIRONMENT VARIABLES` section
4. **Reload**: Run `reload` after changes

## Questions or Issues?

See [SETUP.md](SETUP.md) for troubleshooting and setup tips.
