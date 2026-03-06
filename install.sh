#!/usr/bin/env bash

###############################################################################
# bashrc-profile Installer
###############################################################################
# Installs the bashrc-profile configuration with smart backups and updates.
# Features:
#   - Automatic timestamped backups of existing .bashrc & .shell_functions
#   - Dry-run mode to preview changes (--dry-run or -n)
#   - Handles both fresh installs and updates
#   - Auto-reloads shell after installation (or notifies user)
#   - Validates installation success

set -euo pipefail

###############################################################################
# Colors for output
###############################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

###############################################################################
# Configuration
###############################################################################
HOME_DIR="${HOME:-$(eval echo ~)}"
DRY_RUN=false
TRUENAS=false
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Determine if running from file or pipe
if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ "${BASH_SOURCE[0]}" != "-" ]] && [[ -f "$(dirname "${BASH_SOURCE[0]}")/bashrc" ]]; then
    REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    # Running from pipe (curl | bash) or files not found, download from GitHub
    REPO_DIR="$(mktemp -d)"
    GITHUB_RAW="https://raw.githubusercontent.com/nicolasfalesy/bashrc-profile/main"
fi

SHELL_FUNCS_SRC="$REPO_DIR/shell_functions"
STARSHIP_SRC="$REPO_DIR/starship.toml"
SHELL_FUNCS_DEST="$HOME_DIR/.shell_functions"
STARSHIP_DEST="${XDG_CONFIG_HOME:-$HOME_DIR/.config}/starship.toml"

# Set RC file paths — resolved after TrueNAS flag is determined in main()
BASHRC_SRC=""
BASHRC_DEST=""

###############################################################################
# Helper functions
###############################################################################

print_header() {
    echo -e "${BLUE}=== bashrc-profile Installer ===${NC}"
    echo ""
}

print_info() {
    echo -e "${BLUE}ℹ${NC}  $*"
}

print_success() {
    echo -e "${GREEN}✓${NC}  $*"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  $*"
}

print_error() {
    echo -e "${RED}✗${NC}  $*" >&2
}

print_section() {
    echo ""
    echo -e "${BLUE}--- $1 ---${NC}"
}

download_from_github() {
    print_section "Downloading files from GitHub"

    if [[ "$TRUENAS" == true ]]; then
        print_info "Downloading zshrc..."
        if ! curl -fsSL "$GITHUB_RAW/zshrc" -o "$BASHRC_SRC"; then
            print_error "Failed to download zshrc"
            return 1
        fi
        print_success "Downloaded zshrc"
    else
        print_info "Downloading bashrc..."
        if ! curl -fsSL "$GITHUB_RAW/bashrc" -o "$BASHRC_SRC"; then
            print_error "Failed to download bashrc"
            return 1
        fi
        print_success "Downloaded bashrc"
    fi

    print_info "Downloading shell_functions..."
    if ! curl -fsSL "$GITHUB_RAW/shell_functions" -o "$SHELL_FUNCS_SRC"; then
        print_error "Failed to download shell_functions"
        return 1
    fi
    print_success "Downloaded shell_functions"

    print_info "Downloading starship.toml..."
    if ! curl -fsSL "$GITHUB_RAW/starship.toml" -o "$STARSHIP_SRC"; then
        print_error "Failed to download starship.toml"
        return 1
    fi
    print_success "Downloaded starship.toml"
}

validate_files() {
    print_section "Validating source files"

    local rc_label
    [[ "$TRUENAS" == true ]] && rc_label="zshrc" || rc_label="bashrc"

    if [[ ! -f "$BASHRC_SRC" ]]; then
        print_error "Source $rc_label not found: $BASHRC_SRC"
        return 1
    fi
    print_success "Found $rc_label"

    if [[ ! -f "$SHELL_FUNCS_SRC" ]]; then
        print_error "Source shell_functions not found: $SHELL_FUNCS_SRC"
        return 1
    fi
    print_success "Found shell_functions"

    if [[ ! -f "$STARSHIP_SRC" ]]; then
        print_error "Source starship.toml not found: $STARSHIP_SRC"
        return 1
    fi
    print_success "Found starship.toml"
}

check_existing_files() {
    print_section "Checking for existing files"

    local has_bashrc=false
    local has_shell_funcs=false

    if [[ -f "$BASHRC_DEST" ]]; then
        has_bashrc=true
        print_info "Found existing .bashrc"
    else
        print_info "No existing .bashrc (fresh install)"
    fi

    if [[ -f "$SHELL_FUNCS_DEST" ]]; then
        has_shell_funcs=true
        print_info "Found existing .shell_functions"
    else
        print_info "No existing .shell_functions (fresh install)"
    fi

    return 0
}

create_backups() {
    print_section "Creating backups"

    if [[ -f "$BASHRC_DEST" ]]; then
        local backup_file="$BASHRC_DEST.bak.$TIMESTAMP"
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY-RUN] Would backup: $BASHRC_DEST → $backup_file"
        else
            cp "$BASHRC_DEST" "$backup_file"
            print_success "Backed up .bashrc → $backup_file"
        fi
    else
        print_info "No .bashrc to backup"
    fi

    if [[ -f "$SHELL_FUNCS_DEST" ]]; then
        local backup_file="$SHELL_FUNCS_DEST.bak.$TIMESTAMP"
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY-RUN] Would backup: $SHELL_FUNCS_DEST → $backup_file"
        else
            cp "$SHELL_FUNCS_DEST" "$backup_file"
            print_success "Backed up .shell_functions → $backup_file"
        fi
    else
        print_info "No .shell_functions to backup"
    fi

    if [[ -f "$STARSHIP_DEST" ]]; then
        local backup_file="$STARSHIP_DEST.bak.$TIMESTAMP"
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY-RUN] Would backup: $STARSHIP_DEST → $backup_file"
        else
            cp "$STARSHIP_DEST" "$backup_file"
            print_success "Backed up starship.toml → $backup_file"
        fi
    else
        print_info "No starship.toml to backup"
    fi
}

install_files() {
    print_section "Installing files"

    local rc_dest_label
    [[ "$TRUENAS" == true ]] && rc_dest_label="~/.zshrc" || rc_dest_label="~/.bashrc"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would install $(basename "$BASHRC_SRC") → $BASHRC_DEST"
        print_info "[DRY-RUN] Would install shell_functions → $SHELL_FUNCS_DEST"
        print_info "[DRY-RUN] Would install starship.toml → $STARSHIP_DEST"
        print_success "Dry-run complete (no changes made)"
    else
        cp "$BASHRC_SRC" "$BASHRC_DEST"
        print_success "Installed $rc_dest_label"

        cp "$SHELL_FUNCS_SRC" "$SHELL_FUNCS_DEST"
        print_success "Installed .shell_functions"

        mkdir -p "$(dirname "$STARSHIP_DEST")"
        cp "$STARSHIP_SRC" "$STARSHIP_DEST"
        print_success "Installed starship.toml"
    fi
}

validate_installation() {
    print_section "Validating installation"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Skipping validation"
        return 0
    fi

    local rc_dest_label2
    [[ "$TRUENAS" == true ]] && rc_dest_label2=".zshrc" || rc_dest_label2=".bashrc"

    if [[ ! -f "$BASHRC_DEST" ]]; then
        print_error "$rc_dest_label2 not found after installation"
        return 1
    fi
    print_success "$rc_dest_label2 installed correctly"

    if [[ ! -f "$SHELL_FUNCS_DEST" ]]; then
        print_error ".shell_functions not found after installation"
        return 1
    fi
    print_success ".shell_functions installed correctly"

    if [[ ! -f "$STARSHIP_DEST" ]]; then
        print_error "starship.toml not found after installation"
        return 1
    fi
    print_success "starship.toml installed correctly"

    # Check if shell_functions is sourced in bashrc
    if grep -q 'shell_functions' "$BASHRC_DEST"; then
        print_success ".bashrc sources .shell_functions"
    else
        print_warning ".bashrc doesn't seem to source .shell_functions"
    fi
}

reload_shell() {
    print_section "Shell configuration"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would reload shell"
        return 0
    fi

    if [[ -n "${BASH_VERSION:-}" ]]; then
        print_info "Attempting to reload bash configuration..."
        # Source in a subshell to avoid interfering with script execution
        ( source "$BASHRC_DEST" 2>/dev/null && print_success "Shell reloaded!" ) || \
            print_warning "Could not reload automatically. Restart your terminal or run: source ~/.bashrc"
    fi
}

show_summary() {
    print_section "Installation Summary"

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "DRY-RUN MODE - No changes were made"
        echo ""
        echo "To proceed with actual installation, run:"
        echo "  bash install.sh"
        return 0
    fi

    echo ""
    echo "✨ Installation complete!"
    echo ""
    echo "Files installed:"
    if [[ "$TRUENAS" == true ]]; then
        echo "  • ~/.zshrc"
    else
        echo "  • ~/.bashrc"
    fi
    echo "  • ~/.shell_functions"
    echo "  • ~/.config/starship.toml"
    echo ""
    echo "Next steps:"
    if [[ "$TRUENAS" == true ]]; then
        echo "  1. Restart your shell or run: source ~/.zshrc"
        echo "  2. Check FEATURES.md for a complete list of aliases & functions"
        echo "  Note: Package installation (install_prereqs) is not available on TrueNAS."
    else
        echo "  1. Restart your terminal or run: source ~/.bashrc"
        echo "  2. Run 'install_prereqs' to install optional dependencies"
        echo "  3. Check FEATURES.md for a complete list of aliases & functions"
    fi
    echo ""
    echo "To restore your previous config:"
    echo "  cp ~/.bashrc.bak.$TIMESTAMP ~/.bashrc"
    echo "  cp ~/.shell_functions.bak.$TIMESTAMP ~/.shell_functions"
}

show_help() {
    cat <<'EOF'
Usage: bash install.sh [OPTIONS]

bashrc-profile installer with smart backups and validation.

OPTIONS:
  -h, --help      Show this help message
  -n, --dry-run   Preview changes without installing
  -f, --force     Force install (skip confirmations)

EXAMPLES:
  bash install.sh              # Install with prompts
  bash install.sh --dry-run    # Preview what will happen
  bash install.sh --force      # Force install without asking

FEATURES:
  • Creates timestamped backups of existing files
  • Supports both fresh installs and updates
  • Auto-reloads shell after installation
  • Validates installation success
EOF
}

###############################################################################
# Main installation flow
###############################################################################

main() {
    local force_install=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=true
                ;;
            -f|--force)
                force_install=true
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done

    print_header

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "DRY-RUN MODE - No changes will be made"
        echo ""
    fi

    # Ask if this is a TrueNAS installation
    if [[ "$force_install" == false ]]; then
        echo ""
        read -rp "Are you installing on TrueNAS? [y/N] " -n 1 truenas_confirm
        echo ""
        if [[ "$truenas_confirm" =~ ^[Yy]$ ]]; then
            TRUENAS=true
            print_info "TrueNAS mode: will install zshrc → ~/.zshrc (no package manager installs)"
        fi
    fi

    # Set RC source/dest based on TrueNAS flag
    if [[ "$TRUENAS" == true ]]; then
        BASHRC_SRC="$REPO_DIR/zshrc"
        BASHRC_DEST="$HOME_DIR/.zshrc"
    else
        BASHRC_SRC="$REPO_DIR/bashrc"
        BASHRC_DEST="$HOME_DIR/.bashrc"
    fi

    # Download files from GitHub if running from pipe
    if [[ -n "${GITHUB_RAW:-}" ]]; then
        if ! download_from_github; then
            print_error "Installation failed: could not download files"
            rm -rf "$REPO_DIR"
            exit 1
        fi
    fi

    # Validate source files exist
    if ! validate_files; then
        print_error "Installation failed: source files not found"
        exit 1
    fi

    # Check for existing files
    check_existing_files

    # Confirm before proceeding (unless force flag)
    if [[ "$force_install" == false && "$DRY_RUN" == false ]]; then
        echo ""
        read -rp "Continue with installation? [y/N] " -n 1 confirm
        echo ""
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_error "Installation cancelled"
            exit 1
        fi
    fi

    # Run installation steps
    create_backups
    install_files
    validate_installation
    reload_shell
    show_summary

    # Clean up temporary directory if we created one
    if [[ -n "${GITHUB_RAW:-}" ]]; then
        rm -rf "$REPO_DIR"
    fi

    echo ""
}

# Run main function
main "$@"
