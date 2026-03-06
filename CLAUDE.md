# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**bashrc-profile** is a comprehensive bash shell configuration package designed for power users. It provides 40+ carefully curated aliases and 25+ custom functions organized by category (navigation, file operations, networking, system utilities, etc.), with features like tab completion, environment setup, and integration with modern tools.

## Architecture & File Organization

### Core Files

- **`bashrc`** (37KB) - Main bash configuration file
  - Sections: BLE.sh init → Source files → Shell options → Environment variables → Aliases → Functions → Starship/Zoxide init
  - Sourced automatically by `.bashrc` in user's home directory
  - Contains: aliases, environment variables, keybindings, history config, XDG directory setup

- **`shell_functions`** (13KB) - Additional shell functions separated for better organization
  - Contains all custom functions not in bashrc
  - Sourced from bashrc (line ~30: `. "$HOME/.shell_functions"`)
  - Functions are organized into logical groups (see FEATURES.md)

- **`install.sh`** - Installation script with smart backups and dry-run support
  - Handles both fresh installs and updates
  - Creates timestamped backups (`.bashrc.bak.YYYYMMDD-HHMMSS`)
  - Includes dependency validation and shell reload
  - Usage: `bash install.sh [--dry-run]`

### Documentation Files

- **`README.md`** - Quick start, features overview, installation options
- **`FEATURES.md`** - Complete reference of all aliases and functions with usage examples
- **`SETUP.md`** - Detailed customization, dependency installation, troubleshooting
- **`LICENSE`** - MIT License
- **`.gitignore`** - Standard git ignore patterns

## Development Workflow

### Testing Changes Locally

To test changes without affecting your system configuration:

```bash
# Copy files to a test location
cp bashrc ~/bashrc.test
cp shell_functions ~/shell_functions.test

# Source the test version in a new shell
bash --rcfile ~/bashrc.test -i

# Verify aliases/functions work
alias | grep <alias_name>
type <function_name>
```

### Testing the Install Script

```bash
# Dry-run mode (shows what would be installed without making changes)
bash install.sh --dry-run

# Full installation
bash install.sh

# Verify installation
cat ~/.bashrc | head -5
cat ~/.shell_functions | head -5
source ~/.bashrc
```

### Testing Individual Functions

Most functions have built-in help via `-h` or `--help`:

```bash
# Test a function with help
vpn -h
size --help
grub -h

# Test tab completion (manually trigger with Tab key)
# Examples: size <tab>, rcon <tab>, bak <tab>

# Check function exists and works
type <function_name>
<function_name>  # Call it
```

### Dependency Verification

```bash
# Quick check of key dependencies
which fastfetch neovim starship zoxide ripgrep trash-cli alacritty mcrcon

# Test full prerequisite check
bash -c "source bashrc && install_prereqs"  # Shows what's missing
```

## Key Design Patterns

### 1. **Layered Initialization** (in bashrc)
- BLE.sh early init (line 6) for enhanced readline before other config
- Global bash completions sourced
- Custom shell_functions sourced
- Starship and Zoxide initialized at end (can be slow, commented out for optimization if needed)

### 2. **Function Structure** (in shell_functions)
- Functions include usage examples as comments
- Help text via `-h`/`--help` flags (using case statements)
- Tab completion support defined inline or as separate `_complete_<function>` functions
- Error handling with meaningful messages

### 3. **Alias Organization** (in bashrc)
- Grouped by category with section headers
- Simple one-liners only (complex logic goes to functions)
- Uses existing commands or aliases (e.g., `grep` alias uses `rg` if available, falls back to `/usr/bin/grep`)

### 4. **Environment Setup** (lines 67-105 in bashrc)
- XDG directory compliance
- Editor and terminal preferences
- History configuration with timestamps
- Colors for ls and man pages
- Terminal-specific settings (e.g., RCON, TERMINAL path)

## Common Development Tasks

### Adding a New Alias

1. Edit `bashrc` - find appropriate section (Docker, SSH, Package Management, etc.)
2. Add one-liner: `alias myalias='command'`
3. For complex logic, create a function in `shell_functions` instead
4. Test: `bash --rcfile bashrc -i` then `myalias`
5. Update `FEATURES.md` with the new alias in the correct table

### Adding a New Function

1. Add to `shell_functions`:
   ```bash
   myfunction() {
       # Brief description
       # Usage: myfunction [options] [args]
       # Options:
       #   -h, --help    Show help

       case "$1" in
           -h|--help)
               echo "Usage: myfunction [option]"
               return 0
               ;;
           *)
               # Implementation
               ;;
       esac
   }
   ```
2. Add tab completion if applicable (see `port`, `size`, `rcon` functions for examples)
3. Test in subshell: `bash --rcfile bashrc -i` then `myfunction`
4. Update `FEATURES.md` with documentation and usage examples

### Modifying Existing Functions

- Edit the function in `bashrc` or `shell_functions`
- Test in isolation: `bash --rcfile bashrc -i` then `type <function>` and call it
- If behavior changes significantly, update `FEATURES.md` examples
- Run install script to verify: `bash install.sh --dry-run`

### Updating Documentation

- **FEATURES.md**: Tables with all aliases/functions, usage examples, options
- **SETUP.md**: Customization guides, troubleshooting, advanced config
- **README.md**: High-level overview, quick start

Update these when adding/removing/significantly changing any alias or function.

## Testing Checklist

When making changes, verify:

- [ ] Changes work in a test shell: `bash --rcfile ./bashrc -i`
- [ ] Tab completions work (if applicable)
- [ ] Help messages display: `command -h`
- [ ] No syntax errors: `bash -n bashrc` and `bash -n shell_functions`
- [ ] Documentation updated (FEATURES.md, SETUP.md, etc.)
- [ ] Install script still works: `bash install.sh --dry-run`
- [ ] Backup/restore tested if modifying install.sh

## Performance Considerations

- ble.sh initialization is early (line 6) but can slow startup slightly
- Starship and Zoxide initialization (end of bashrc) are optional and can be commented out for faster startup
- History with timestamps adds minimal overhead
- Tab completions are lazy-loaded by bash completion framework

To profile startup time:
```bash
time bash -i -c exit
```

## Notes on Dependencies

The configuration works with but doesn't require all dependencies. Core functionality includes:
- **Essential**: bash 4+, standard GNU tools
- **Recommended**: neovim (EDITOR), ripgrep (grep alias), trash-cli (safe rm)
- **Optional**: starship (prompt), zoxide (smart nav), alacritty (TERMINAL), fastfetch, mcrcon, ble.sh

The `install_prereqs` function helps users install missing dependencies.

## Important Files Not to Modify

- `.git/` - Version control, never modify directly
- `.gitignore` - Package distribution patterns
- `LICENSE` - MIT License terms, keep as-is

## Related Documentation

- `README.md` - Installation and feature overview
- `FEATURES.md` - Complete alias/function reference with examples
- `SETUP.md` - Customization and troubleshooting guide
