#!/usr/bin/env bash
# =============================================================================
#  bashrc-profile — installer, updater, dependency manager
#
#  curl -fsSL https://raw.githubusercontent.com/nicolasfalesy/bashrc-profile/main/install.sh | bash
#  bash install.sh [options]              (from a clone)
#
#  What it does
#    1. detects the machine profile (pi / nas / desktop / server) — or takes --profile
#    2. gets the repo (uses the clone you ran it from, else clones to ~/.local/share/bashrc-profile)
#    3. installs every dependency the profile uses (system packages where apt works,
#       user-local binaries where it doesn't — e.g. TrueNAS)
#    4. backs up and symlinks ~/.bashrc, ~/.config/starship.toml, ~/.blerc
#    5. writes ~/.config/bashrc-profile/config and seeds ~/.bashrc.local
#    6. verifies the result by starting a real interactive shell
# =============================================================================
set -uo pipefail

REPO_URL='https://github.com/nicolasfalesy/bashrc-profile.git'
TARBALL_URL='https://github.com/nicolasfalesy/bashrc-profile/archive/refs/heads/main.tar.gz'
DEFAULT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/bashrc-profile"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bashrc-profile"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bashrc-profile"
TS=$(date +%Y%m%d-%H%M%S)
PATH="$HOME/.local/bin:$HOME/.fzf/bin:$PATH"   # see tools installed for this user only

# ── Options ──────────────────────────────────────────────────────────────────
PROFILE=auto        # pi | nas | desktop | server | auto
MODE=install        # install | deps | update | uninstall
DEPS=1              # install dependencies during install
DRY=0
YES=0
WITH_DEV=0          # gcc/make/gdb/valgrind/clang
WITH_BLESH=1        # ble.sh on by default (--no-blesh to skip)
WITH_MCRCON=0
TARGET_DIR=''

# ── Output helpers ───────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    R=$'\033[0;31m' G=$'\033[0;32m' Y=$'\033[1;33m' B=$'\033[0;34m' N=$'\033[0m'
else
    R='' G='' Y='' B='' N=''
fi
info()  { printf '%s·%s  %s\n' "$B" "$N" "$*"; }
ok()    { printf '%s✓%s  %s\n' "$G" "$N" "$*"; }
warn()  { printf '%s!%s  %s\n' "$Y" "$N" "$*"; }
err()   { printf '%s✗%s  %s\n' "$R" "$N" "$*" >&2; }
step()  { printf '\n%s--- %s ---%s\n' "$B" "$*" "$N"; }
die()   { err "$*"; exit 1; }
have()  { command -v "$1" >/dev/null 2>&1; }

# run <cmd...> — execute, or just print in dry-run mode
run() {
    if (( DRY )); then printf '%s[dry-run]%s %s\n' "$Y" "$N" "$*"; return 0; fi
    "$@"
}

# ask <question> — yes/no, honours --yes, reads from the terminal even when piped
ask() {
    (( YES )) && return 0
    local reply
    if [[ -r /dev/tty ]]; then
        read -rp "$1 [Y/n] " reply < /dev/tty
    else
        warn "no terminal to ask '$1' — assuming yes"; return 0
    fi
    [[ -z $reply || $reply =~ ^[Yy] ]]
}

usage() {
    cat <<'USAGE'
Usage: install.sh [options]

Modes (default: full install)
  --deps-only          only install/refresh dependencies for the profile
  --update             git pull the repo, relink, clear caches
  --uninstall          remove symlinks, restore the newest ~/.bashrc backup

Options
  --profile <p>        pi | nas | desktop | server | auto   (default: auto)
  --no-deps            skip dependency installation
  --with-dev           C toolchain: gcc make gdb valgrind clang
  --with-blesh         install ble.sh and enable it (default)
  --no-blesh           skip ble.sh (saves ~30 ms per shell start)
  --with-mcrcon        build mcrcon (Minecraft RCON client)
  --dir <path>         where to keep the repo when cloning (default: ~/.local/share/bashrc-profile)
  -n, --dry-run        show what would happen, change nothing
  -y, --yes            no questions
  -h, --help           this help
USAGE
}

while (( $# )); do
    case $1 in
        --profile)      PROFILE=$2; shift ;;
        --profile=*)    PROFILE=${1#*=} ;;
        --deps-only)    MODE=deps ;;
        --update)       MODE=update ;;
        --uninstall)    MODE=uninstall ;;
        --no-deps)      DEPS=0 ;;
        --with-dev)     WITH_DEV=1 ;;
        --with-blesh)   WITH_BLESH=1 ;;
        --no-blesh)     WITH_BLESH=0 ;;
        --with-mcrcon)  WITH_MCRCON=1 ;;
        --dir)          TARGET_DIR=$2; shift ;;
        --dir=*)        TARGET_DIR=${1#*=} ;;
        -n|--dry-run)   DRY=1 ;;
        -y|--yes)       YES=1 ;;
        -h|--help)      usage; exit 0 ;;
        *)              err "unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done
case $PROFILE in pi|nas|desktop|server|auto) ;; *) die "--profile must be pi, nas, desktop, server or auto" ;; esac

# ── 1. Detect environment ────────────────────────────────────────────────────
detect_profile() {
    [[ $PROFILE != auto ]] && return
    if [[ -r "$CONFIG_DIR/config" ]] && grep -q '^BASHRC_PROFILE=' "$CONFIG_DIR/config"; then
        PROFILE=$(sed -n 's/^BASHRC_PROFILE=//p' "$CONFIG_DIR/config" | tr -d '"'"'")
        info "profile from existing config: $PROFILE"; return
    fi
    local model=''
    [[ -r /proc/device-tree/model ]] && read -r model < /proc/device-tree/model
    if [[ $model == *"Raspberry Pi"* ]]; then PROFILE=pi
    elif [[ -d /usr/share/truenas || -x /usr/bin/midclt ]]; then PROFILE=nas
    elif [[ -n ${DISPLAY-} || -n ${WAYLAND_DISPLAY-} ]]; then PROFILE=desktop
    else PROFILE=server; fi
}

SUDO=''
PKG=none        # nala | apt | dnf | pacman | none
detect_system() {
    if [[ $EUID -ne 0 ]]; then
        if have sudo; then SUDO=sudo; else warn "no sudo — system packages will be skipped"; fi
    fi
    if [[ $PROFILE == nas ]]; then
        PKG=none           # TrueNAS: read-only root, apt intentionally disabled
    elif have nala && [[ -x $(command -v apt-get) ]]; then PKG=nala
    elif [[ -x $(command -v apt-get 2>/dev/null || echo /nonexistent) ]]; then PKG=apt
    elif have dnf; then PKG=dnf
    elif have pacman; then PKG=pacman
    fi
    ARCH=$(uname -m)
    info "profile: $PROFILE   packages: $PKG   arch: $ARCH   home: $HOME"
}

# ── 2. Locate or fetch the repo ──────────────────────────────────────────────
REPO_DIR=''
locate_repo() {
    step "Repository"
    local here=''
    if [[ -n ${BASH_SOURCE[0]-} && -f ${BASH_SOURCE[0]} ]]; then
        here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    fi
    if [[ -n $here && -f $here/bashrc && -d $here/lib ]]; then
        REPO_DIR=$here
        ok "using checkout at $REPO_DIR"
        return
    fi
    REPO_DIR=${TARGET_DIR:-$DEFAULT_DIR}
    if [[ -d $REPO_DIR/.git ]]; then
        info "updating existing clone at $REPO_DIR"
        run git -C "$REPO_DIR" pull --ff-only || warn "git pull failed — continuing with what is there"
    elif have git; then
        info "cloning to $REPO_DIR"
        run git clone --depth 1 "$REPO_URL" "$REPO_DIR" || die "git clone failed"
    else
        info "git not available — downloading tarball to $REPO_DIR"
        (( DRY )) && return
        local tmp; tmp=$(mktemp -d)
        curl -fsSL "$TARBALL_URL" | tar xz -C "$tmp" || die "download failed"
        mkdir -p "$REPO_DIR" && cp -r "$tmp"/bashrc-profile-main/. "$REPO_DIR"/ && rm -rf "$tmp"
    fi
    ok "repo: $REPO_DIR"
}

# ── 3. Dependencies ──────────────────────────────────────────────────────────
# Package lists. Format: "package[:command-to-check]"
CORE_PKGS=(bash-completion curl git wget tree ripgrep:rg neovim:nvim trash-cli:trash tmux htop
           unzip p7zip-full:7z xz-utils:xz zstd gawk iproute2:ss fzf zoxide starship)
PI_PKGS=(nala raspi-utils:vcgencmd wireguard-tools:wg)
DESKTOP_PKGS=(alacritty xclip wl-clipboard:wl-copy wireguard-tools:wg fonts-noto-color-emoji desktop-file-utils:update-desktop-database)
DEV_PKGS=(gcc make gdb valgrind clang)

declare -a INSTALLED=() SKIPPED=() FAILED=()

pkg_installed() {   # <pkg>
    case $PKG in
        nala|apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
        dnf)      rpm -q "$1" >/dev/null 2>&1 ;;
        pacman)   pacman -Q "$1" >/dev/null 2>&1 ;;
        *)        return 1 ;;
    esac
}
pkg_available() {   # <pkg>
    case $PKG in
        nala|apt) [[ -n $(apt-cache policy "$1" 2>/dev/null | sed -n 's/^  Candidate: //p' | grep -v '(none)') ]] ;;
        dnf)      dnf list --available "$1" >/dev/null 2>&1 ;;
        pacman)   pacman -Si "$1" >/dev/null 2>&1 ;;
        *)        return 1 ;;
    esac
}
pkg_install_many() {   # <pkg>...
    (( $# )) || return 0
    case $PKG in
        nala)   run $SUDO nala install -y "$@" ;;
        apt)    run $SUDO apt-get install -y "$@" ;;
        dnf)    run $SUDO dnf install -y "$@" ;;
        pacman) run $SUDO pacman -S --noconfirm --needed "$@" ;;
    esac
}
pkg_update_lists() {
    case $PKG in
        nala) run $SUDO nala update ;;
        apt)  run $SUDO apt-get update ;;
    esac
}

# install_pkgs <label> <spec>... — skip what is present, install the rest in one go
install_pkgs() {
    local label=$1; shift
    local spec pkg cmd want=() missing_repo=()
    for spec in "$@"; do
        pkg=${spec%%:*}; cmd=${spec#*:}; [[ $spec == *:* ]] || cmd=$pkg
        if have "$cmd" || pkg_installed "$pkg"; then
            SKIPPED+=("$pkg")
        elif pkg_available "$pkg"; then
            want+=("$pkg")
        else
            missing_repo+=("$pkg")
        fi
    done
    for pkg in "${missing_repo[@]}"; do warn "$label: '$pkg' not in the package repos (will try a user-local fallback if one exists)"; done
    if (( ${#want[@]} )); then
        info "$label: installing ${want[*]}"
        if pkg_install_many "${want[@]}"; then INSTALLED+=("${want[@]}"); else FAILED+=("${want[@]}"); fi
    else
        ok "$label: nothing to install"
    fi
}

# ── user-local installers (no root, no apt): used on the NAS and as fallbacks ─
LOCAL_BIN="$HOME/.local/bin"
install_starship_local() {
    have starship && return 0
    info "starship → $LOCAL_BIN"
    run mkdir -p "$LOCAL_BIN"
    if (( DRY )); then return 0; fi
    curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$LOCAL_BIN" >/dev/null && INSTALLED+=(starship) || FAILED+=(starship)
}
install_zoxide_local() {
    have zoxide && return 0
    info "zoxide → $LOCAL_BIN"
    if (( DRY )); then return 0; fi
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh >/dev/null && INSTALLED+=(zoxide) || FAILED+=(zoxide)
}
install_fzf_local() {
    have fzf && return 0
    if [[ -x $HOME/.fzf/bin/fzf ]]; then SKIPPED+=(fzf); return 0; fi
    have git || { warn "fzf: git needed for the user-local install"; FAILED+=(fzf); return 1; }
    info "fzf → ~/.fzf"
    if (( DRY )); then return 0; fi
    git clone --depth 1 -q https://github.com/junegunn/fzf.git "$HOME/.fzf" &&
        "$HOME/.fzf/install" --bin >/dev/null && INSTALLED+=(fzf) || FAILED+=(fzf)
}
install_blesh() {
    local dest="$HOME/.local/share/blesh"
    if [[ -f $dest/ble.sh ]]; then SKIPPED+=(ble.sh); return 0; fi
    info "ble.sh → $dest (nightly release tarball)"
    if (( DRY )); then return 0; fi
    local tmp; tmp=$(mktemp -d)
    if curl -fsSL https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz | tar xJ -C "$tmp" &&
       mkdir -p "$(dirname "$dest")" && rm -rf "$dest" && mv "$tmp"/ble-nightly "$dest"; then
        INSTALLED+=(ble.sh)
    else
        FAILED+=(ble.sh)
    fi
    rm -rf "$tmp"
}
install_mcrcon() {
    have mcrcon && { SKIPPED+=(mcrcon); return 0; }
    info "mcrcon: building from source"
    if (( DRY )); then return 0; fi
    have gcc && have make || { warn "mcrcon needs gcc and make (--with-dev)"; FAILED+=(mcrcon); return 1; }
    local tmp; tmp=$(mktemp -d)
    if git clone -q --depth 1 https://github.com/Tiiffi/mcrcon.git "$tmp/mcrcon" && make -s -C "$tmp/mcrcon"; then
        if [[ -n $SUDO || $EUID -eq 0 ]] && $SUDO make -s -C "$tmp/mcrcon" install; then INSTALLED+=(mcrcon)
        else mkdir -p "$LOCAL_BIN" && cp "$tmp/mcrcon/mcrcon" "$LOCAL_BIN/" && INSTALLED+=("mcrcon (~/.local/bin)"); fi
    else
        FAILED+=(mcrcon)
    fi
    rm -rf "$tmp"
}
install_nerd_font() {
    local dir="$HOME/.local/share/fonts/MesloLGS-NF"
    if [[ -d $dir ]] || fc-list 2>/dev/null | grep -qi 'MesloLGS Nerd'; then SKIPPED+=("MesloLGS Nerd Font"); return 0; fi
    info "MesloLGS Nerd Font → $dir (starship's icons need a Nerd Font in your terminal)"
    if (( DRY )); then return 0; fi
    local tmp; tmp=$(mktemp -d)
    if curl -fsSL -o "$tmp/Meslo.zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip &&
       mkdir -p "$dir" && unzip -qo "$tmp/Meslo.zip" -d "$dir" '*.ttf' && fc-cache -f >/dev/null 2>&1; then
        INSTALLED+=("MesloLGS Nerd Font")
    else
        FAILED+=("MesloLGS Nerd Font")
    fi
    rm -rf "$tmp"
}

install_dependencies() {
    step "Dependencies ($PROFILE)"
    if [[ $PKG == none ]]; then
        if [[ $PROFILE == nas ]]; then
            info "TrueNAS: apt is disabled and / is read-only — installing user-local tools only"
        else
            warn "no supported package manager found — installing user-local tools only"
        fi
    else
        pkg_update_lists
        install_pkgs "core" "${CORE_PKGS[@]}"
        case $PROFILE in
            pi)      install_pkgs "pi" "${PI_PKGS[@]}" ;;
            desktop) install_pkgs "desktop" "${DESKTOP_PKGS[@]}" ;;
        esac
        (( WITH_DEV )) && install_pkgs "dev" "${DEV_PKGS[@]}"
    fi
    # Fallbacks / user-local installs for the things the prompt needs.
    install_starship_local
    install_zoxide_local
    install_fzf_local
    (( WITH_BLESH ))  && install_blesh
    (( WITH_MCRCON )) && install_mcrcon
    [[ $PROFILE == desktop ]] && install_nerd_font

    # Things we do not install for you but the profile can use.
    case $PROFILE in
        pi)  have docker      || warn "docker not found — install with: curl -fsSL https://get.docker.com | sh"
             have cloudflared || warn "cloudflared not found — see https://pkg.cloudflare.com" ;;
        nas) have nvim || have vim || warn "no vim/nvim on this NAS — EDITOR will fall back to nano" ;;
    esac
    return 0
}

# ── 4. Link files ────────────────────────────────────────────────────────────
# link <source> <target> — back up whatever is at target, then symlink
link() {
    local src=$1 dst=$2 bak="$2.bak.$TS"
    if [[ -L $dst && $(readlink -f "$dst") == "$(readlink -f "$src")" ]]; then
        ok "$dst already → $src"; return 0
    fi
    if [[ -e $dst || -L $dst ]]; then
        if [[ -L $dst ]]; then
            run cp -L "$dst" "$bak" 2>/dev/null; run rm -f "$dst"
        else
            run mv "$dst" "$bak"
        fi
        info "backed up $dst → $bak"
    fi
    run mkdir -p "$(dirname "$dst")"
    run ln -s "$src" "$dst" && ok "$dst → $src"
}

link_files() {
    step "Linking files"
    link "$REPO_DIR/bashrc"        "$HOME/.bashrc"
    link "$REPO_DIR/starship.toml" "$HOME/.config/starship.toml"
    link "$REPO_DIR/blerc"         "$HOME/.blerc"

    # Login shells must reach ~/.bashrc (ssh does a login shell).
    if [[ -f $HOME/.bash_profile ]] && ! grep -q 'bashrc' "$HOME/.bash_profile"; then
        warn "~/.bash_profile exists but never sources ~/.bashrc — add:  [ -f ~/.bashrc ] && . ~/.bashrc"
    elif [[ ! -f $HOME/.bash_profile && ! -f $HOME/.profile ]]; then
        info "creating ~/.profile so login shells load ~/.bashrc"
        (( DRY )) || printf '# ~/.profile\n[ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' > "$HOME/.profile"
    elif [[ -f $HOME/.profile ]] && ! grep -q 'bashrc' "$HOME/.profile"; then
        info "~/.profile exists but never sources ~/.bashrc — appending the standard snippet"
        (( DRY )) || printf '\n# added by bashrc-profile: login shells load ~/.bashrc\n[ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' >> "$HOME/.profile"
    fi
}

write_config() {
    step "Config"
    local ff=0; [[ $PROFILE == desktop ]] && ff=1
    info "writing $CONFIG_DIR/config  (profile=$PROFILE blesh=$WITH_BLESH fastfetch=$ff)"
    (( DRY )) && return 0
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/config" <<CFG
# bashrc-profile machine config — written by install.sh on $TS. Edit with: bt config
BASHRC_PROFILE=$PROFILE      # pi | nas | desktop | server
BASHRC_PROFILE_DIR=$REPO_DIR
BASHRC_BLESH=$WITH_BLESH     # 1 = syntax highlighting + autosuggestions (ble.sh)
BASHRC_FASTFETCH=$ff         # 1 = fastfetch on new terminals
BASHRC_CD_LS_MAX=200         # cd auto-lists directories with at most this many entries
BASHRC_LAZY_COMPLETION=1     # 1 = load bash-completion on first Tab (faster startup)
BASHRC_FZF_COMPLETION=0      # 1 = fzf **<Tab> fuzzy path completion (+25 ms startup)
CFG
    if [[ ! -f $HOME/.bashrc.local ]]; then
        cp "$REPO_DIR/bashrc.local.example" "$HOME/.bashrc.local"
        chmod 600 "$HOME/.bashrc.local"
        ok "seeded ~/.bashrc.local from the template — put secrets and ssh hosts there (bt local)"
    else
        ok "~/.bashrc.local kept"
    fi
    rm -f "$CACHE_DIR"/*.bash 2>/dev/null
}

# ── 5. Verify ────────────────────────────────────────────────────────────────
verify() {
    step "Verify"
    local f bad=0
    for f in "$REPO_DIR"/bashrc "$REPO_DIR"/lib/*.sh "$REPO_DIR"/profiles/*.sh; do
        bash -n "$f" || { err "syntax error in $f"; bad=1; }
    done
    (( bad )) && return 1
    ok "all files parse"
    (( DRY )) && return 0
    local out t0 t1
    t0=$EPOCHREALTIME
    out=$(BASHRC_PROFILE=$PROFILE bash --rcfile "$REPO_DIR/bashrc" -ic 'type ll cd sys size >/dev/null && echo BASHRC_OK' 2>&1 </dev/null)
    t1=$EPOCHREALTIME
    if [[ $out == *BASHRC_OK* ]]; then
        ok "interactive shell starts cleanly ($(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%d", (b-a)*1000}') ms)"
        out=${out//BASHRC_OK/}; out=$(grep -v 'Inappropriate ioctl\|no job control\|cannot set terminal' <<< "$out")
        [[ -n $out ]] && warn "startup printed: $out"
    else
        err "test shell failed:"; echo "$out"; return 1
    fi
}

summary() {
    step "Summary"
    (( ${#INSTALLED[@]} )) && printf '%s installed:%s %s\n' "$G" "$N" "${INSTALLED[*]}"
    (( ${#SKIPPED[@]} ))   && printf '%s present:%s   %s\n' "$B" "$N" "${SKIPPED[*]}"
    (( ${#FAILED[@]} ))    && printf '%s failed:%s    %s\n' "$R" "$N" "${FAILED[*]}"
    (( DRY )) && { warn "dry run — nothing was changed"; return 0; }
    cat <<DONE

Done. Open a new terminal or run:  source ~/.bashrc

  profile   $PROFILE          (bt config to change)
  repo      $REPO_DIR
  secrets   ~/.bashrc.local   (bt local — RCON password, ssh hosts…)
  update    bup               (git pull + reload)
  deps      prereqs           (re-run dependency install)
DONE
}

uninstall() {
    step "Uninstall"
    local f newest
    for f in "$HOME/.bashrc" "$HOME/.config/starship.toml" "$HOME/.blerc"; do
        if [[ -L $f ]]; then
            run rm -f "$f"; ok "removed link $f"
            newest=$(ls -t "$f".bak.* 2>/dev/null | head -1)
            if [[ -n $newest ]]; then run cp "$newest" "$f"; ok "restored $f from $newest"; fi
        fi
    done
    run rm -rf "$CONFIG_DIR" "$CACHE_DIR"
    info "kept: the repo, ~/.bashrc.local, and all installed packages"
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    printf '%s=== bashrc-profile installer ===%s\n' "$B" "$N"
    (( DRY )) && warn "DRY RUN — nothing will be changed"
    detect_profile
    detect_system

    case $MODE in
        uninstall) uninstall; return ;;
        deps)      locate_repo; install_dependencies; rm -f "$CACHE_DIR"/*.bash 2>/dev/null; summary; return ;;
        update)    locate_repo; link_files; rm -f "$CACHE_DIR"/*.bash 2>/dev/null; verify; summary; return ;;
    esac

    locate_repo
    if (( ! YES && ! DRY )); then
        ask "Install profile '$PROFILE' (deps: $DEPS, ble.sh: $WITH_BLESH, dev tools: $WITH_DEV)?" || die "cancelled"
    fi
    (( DEPS )) && install_dependencies
    link_files
    write_config
    verify
    summary
}
main "$@"
