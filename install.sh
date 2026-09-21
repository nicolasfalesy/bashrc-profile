#!/usr/bin/env bash
# =============================================================================
#  bashrc-profile — installer, updater, dependency manager
#
#  curl -fsSL https://raw.githubusercontent.com/nicolasfalesy/bashrc-profile/main/install.sh | bash
#  bash install.sh [options]              (from a clone)
#
#  What it does
#    1. detects the machine profile (pi / nas / desktop / omarchy / uw / server) — or takes --profile
#    2. gets the repo (uses the clone you ran it from, else clones to ~/.local/share/bashrc-profile)
#    3. installs every dependency the profile uses (system packages where apt works,
#       user-local binaries where it doesn't — e.g. TrueNAS)
#    4. backs up and symlinks ~/.bashrc, ~/.config/starship.toml, ~/.blerc
#       (profile "omarchy": layered instead — see link_layered)
#    5. writes ~/.config/bashrc-profile/config and seeds ~/.bashrc.local
#    6. verifies the result by starting a real interactive shell
#
#  Modes: (default) install · --update (bup) · --deps-only (prereqs) · --uninstall
#         --upgrade (prereqs --upgrade): refresh the user-local tools to their latest
#  Quirks:
#    • Executed, never sourced. `set -u` is on: every optional variable is read as
#      ${var-}. There is no `set -e` on purpose — a failed optional install must
#      not abort the run; failures are collected in FAILED and shown at the end.
#    • `run` here is the dry-run wrapper, unrelated to lib/dev.sh's `run`.
#    • --update never rewrites an existing config: it only appends toggles that
#      did not exist when the file was written (refresh_config).
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
PROFILE=auto        # pi | nas | desktop | uw | server | auto
MODE=install        # install | deps | update | uninstall
DEPS=1              # install dependencies during install
DRY=0
YES=0
WITH_DEV=0          # gcc/make/gdb/valgrind/clang
WITH_BLESH=1        # ble.sh on by default (--no-blesh to skip)
WITH_MCRCON=0
WITH_ZOXIDE=0       # zoxide was removed upstream; --with-zoxide brings z/zi back
UPGRADE=0           # --upgrade: reinstall the user-local tools (ble.sh, starship, fzf, zoxide) at their latest
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
  --update             git pull, relink, add new toggles to the config, clear caches (what bup runs)
  --uninstall          remove symlinks, restore the newest ~/.bashrc backup
                       (profile "omarchy": strips the appended block instead)

Options
  --profile <p>        pi | nas | desktop | uw | server | auto   (default: auto)
                       uw = UW CS student servers: no root, Waterloo Gold prompt
  --no-deps            skip dependency installation
  --with-dev           C toolchain: gcc make gdb valgrind clang
  --with-blesh         install ble.sh and enable it (default)
  --no-blesh           skip ble.sh. Worth measuring rather than assuming: on the
                       Omarchy laptop ble.sh costs ~205 ms of the ~215 ms startup
                       (~95 ms to source, ~110 ms to attach), independent of what
                       blerc sets. BASHRC_TIMING=1 reports it.
  --with-mcrcon        build mcrcon (Minecraft RCON client)
  --with-zoxide        install zoxide and enable z / zi (off by default)
  --upgrade            refresh the user-local tools to their latest: ble.sh nightly, starship,
                       fzf (~/.fzf), zoxide — apt-managed copies are left to apt (nu).
                       Usually run as: prereqs --upgrade
  --dir <path>         where to keep the repo when cloning (default: ~/.local/share/bashrc-profile)
  -n, --dry-run        show what would happen, change nothing
  -y, --yes            no questions
  -h, --help           this help
USAGE
}

while (( $# )); do
    case $1 in
        --profile)      [[ -n ${2-} ]] || die "--profile needs a value (pi|nas|desktop|omarchy|uw|server|auto)"; PROFILE=$2; shift ;;
        --profile=*)    PROFILE=${1#*=} ;;
        --deps-only)    MODE=deps ;;
        --update)       MODE=update ;;
        --uninstall)    MODE=uninstall ;;
        --no-deps)      DEPS=0 ;;
        --with-dev)     WITH_DEV=1 ;;
        --with-blesh)   WITH_BLESH=1 ;;
        --no-blesh)     WITH_BLESH=0 ;;
        --with-mcrcon)  WITH_MCRCON=1 ;;
        --with-zoxide)  WITH_ZOXIDE=1 ;;
        --upgrade)      UPGRADE=1; [[ $MODE == install ]] && MODE=deps ;;
        --dir)          [[ -n ${2-} ]] || die "--dir needs a path"; TARGET_DIR=$2; shift ;;
        --dir=*)        TARGET_DIR=${1#*=} ;;
        -n|--dry-run)   DRY=1 ;;
        -y|--yes)       YES=1 ;;
        -h|--help)      usage; exit 0 ;;
        *)              err "unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done
case $PROFILE in pi|nas|desktop|omarchy|uw|server|auto) ;; *) die "--profile must be pi, nas, desktop, omarchy, uw, server or auto" ;; esac

# ── 1. Detect environment ────────────────────────────────────────────────────
detect_profile() {
    [[ $PROFILE != auto ]] && return
    if [[ -r "$CONFIG_DIR/config" ]] && grep -q '^BASHRC_PROFILE=' "$CONFIG_DIR/config"; then
        PROFILE=$(sed -n 's/^BASHRC_PROFILE=//p' "$CONFIG_DIR/config" | tr -d '"'"'")
        PROFILE=${PROFILE%%#*}; PROFILE=${PROFILE//[[:space:]]/}   # drop the trailing "# pi | nas | …" comment
        case $PROFILE in
            pi|nas|desktop|omarchy|uw|server) info "profile from existing config: $PROFILE"; return ;;
            *) warn "config has an unknown profile '$PROFILE' — autodetecting"; PROFILE=auto ;;
        esac
    fi
    local model=''
    [[ -r /proc/device-tree/model ]] && read -r model < /proc/device-tree/model
    if [[ $model == *"Raspberry Pi"* ]]; then PROFILE=pi
    elif [[ -d /usr/share/truenas || -x /usr/bin/midclt ]]; then PROFILE=nas
    elif [[ -d /usr/share/omarchy ]]; then PROFILE=omarchy
    elif [[ -n ${DISPLAY-} || -n ${WAYLAND_DISPLAY-} ]]; then PROFILE=desktop
    elif [[ $HOSTNAME == *uwaterloo* ]] || grep -qsE '^(search|domain).*uwaterloo\.ca' /etc/resolv.conf; then PROFILE=uw
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
    elif [[ $PROFILE == uw ]]; then
        PKG=none           # student servers: sudo exists but you are not allowed to use it
    elif [[ $EUID -ne 0 && -z $SUDO ]]; then
        PKG=none           # no root at all → user-local installs only
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
REPO_FROM_CHECKOUT=0   # 1 = running from a clone (no pull here; update_repo does it in --update)
locate_repo() {
    step "Repository"
    local here=''
    if [[ -n ${BASH_SOURCE[0]-} && -f ${BASH_SOURCE[0]} ]]; then
        here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    fi
    if [[ -n $here && -f $here/bashrc && -d $here/lib ]]; then
        REPO_DIR=$here; REPO_FROM_CHECKOUT=1
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

# update_repo — --update from a checkout: pull it (locate_repo only pulls the
# clone it made itself under ~/.local/share).
update_repo() {
    (( REPO_FROM_CHECKOUT )) || return 0
    if [[ -d $REPO_DIR/.git ]]; then
        run git -C "$REPO_DIR" pull --ff-only || warn "git pull failed — continuing with what is there"
    else
        warn "$REPO_DIR is not a git clone (tarball install) — re-run the curl installer to update"
    fi
}

# ── 3. Dependencies ──────────────────────────────────────────────────────────
# Package lists. Format: "package[:command-to-check]"
CORE_PKGS=(bash-completion curl git wget tree ripgrep:rg neovim:nvim trash-cli:trash tmux htop
           unzip p7zip-full:7z xz-utils:xz zstd gawk iproute2:ss fzf starship)
PI_PKGS=(nala raspi-utils:vcgencmd wireguard-tools:wg)
DESKTOP_PKGS=(alacritty xclip wl-clipboard:wl-copy wireguard-tools:wg fonts-noto-color-emoji desktop-file-utils:update-desktop-database)
# Omarchy already ships eza, zoxide, fzf, starship, bat, ripgrep, neovim, tmux,
# fastfetch, btop and wl-clipboard. This is only what it does not have.
OMARCHY_PKGS=(tree trash-cli:trash 7zip:7z unrar wireguard-tools:wg desktop-file-utils:update-desktop-database)
DEV_PKGS=(gcc make gdb valgrind clang)

declare -a INSTALLED=() SKIPPED=() FAILED=() UPGRADED=()

# is_user_local <command> — true when the binary lives under ~/.local/bin or ~/.fzf
# (ours to upgrade); false for a package-manager copy (apt's job).
is_user_local() { local p; p=$(command -v "$1" 2>/dev/null) && [[ $p == "$HOME"/.local/bin/* || $p == "$HOME"/.fzf/* ]]; }
# note_upgrade <name> <old> <new> — record the result of a refresh for the summary
note_upgrade() { if [[ $2 == "$3" ]]; then SKIPPED+=("$1 $3 (latest)"); else UPGRADED+=("$1 $2 → $3"); fi; }

# pkg_translate <pkg> — the lists above are written with Debian names, because
# that is what most of these machines run. Arch spells a few of them differently;
# an empty result means "no equivalent, skip it".
pkg_translate() {
    [[ $PKG == pacman ]] || { printf '%s' "$1"; return 0; }
    case $1 in
        p7zip-full)             printf 7zip ;;
        xz-utils)               printf xz ;;
        fonts-noto-color-emoji) printf noto-fonts-emoji ;;
        nala)                   printf '' ;;      # apt front-end: nothing to install
        *)                      printf '%s' "$1" ;;
    esac
}

# pkg_skipped <pkg> — a CORE_PKGS entry this profile deliberately does not want,
# because the machine already has an equivalent. Nothing in this repo calls either
# of these; `ni htop` / `ni wget` any time you disagree.
pkg_skipped() {
    case $PROFILE:$1 in
        omarchy:htop) return 0 ;;   # Omarchy ships btop; profiles/omarchy.sh aliases htop→btop
        omarchy:wget) return 0 ;;   # curl is what the code actually uses, and it is installed
        *)            return 1 ;;
    esac
}

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
        nala|apt) apt-cache policy "$1" 2>/dev/null | sed -n 's/^  Candidate: //p' | grep -qv '(none)' ;;
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
        pkg=$(pkg_translate "$pkg") || true
        [[ -n $pkg ]] || continue                 # no equivalent on this distro
        if pkg_skipped "$pkg"; then SKIPPED+=("$pkg (not wanted on $PROFILE)"); continue; fi
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
# Each user-local installer: skip when present — unless --upgrade, in which case
# a copy under ~/.local/bin or ~/.fzf is refreshed and an apt copy is left alone.
install_starship_local() {
    local old=''
    if have starship; then
        (( UPGRADE )) || return 0
        is_user_local starship || { info "starship: package-manager copy, leave it to apt (nu)"; SKIPPED+=(starship); return 0; }
        old=$(starship --version 2>/dev/null | head -1); old=${old#starship }
        info "starship: refreshing (have $old)"
    else
        info "starship → $LOCAL_BIN"
    fi
    run mkdir -p "$LOCAL_BIN"
    if (( DRY )); then return 0; fi
    if curl -sS https://starship.rs/install.sh | sh -s -- -y -f -b "$LOCAL_BIN" >/dev/null; then
        if [[ -n $old ]]; then local new; new=$("$LOCAL_BIN/starship" --version | head -1); note_upgrade starship "$old" "${new#starship }"
        else INSTALLED+=(starship); fi
    else
        FAILED+=(starship)
    fi
}
install_zoxide_local() {
    local old=''
    if have zoxide; then
        (( UPGRADE )) || return 0
        is_user_local zoxide || { info "zoxide: package-manager copy, leave it to apt (nu)"; SKIPPED+=(zoxide); return 0; }
        old=$(zoxide --version 2>/dev/null); old=${old#zoxide }
        info "zoxide: refreshing (have $old)"
    else
        info "zoxide → $LOCAL_BIN"
    fi
    if (( DRY )); then return 0; fi
    if curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh >/dev/null; then
        if [[ -n $old ]]; then local new; new=$("$LOCAL_BIN/zoxide" --version); note_upgrade zoxide "$old" "${new#zoxide }"
        else INSTALLED+=(zoxide); fi
    else
        FAILED+=(zoxide)
    fi
}
install_fzf_local() {
    if (( UPGRADE )) && [[ -d $HOME/.fzf/.git ]]; then
        local old new; old=$("$HOME/.fzf/bin/fzf" --version 2>/dev/null); old=${old%% *}
        info "fzf: refreshing ~/.fzf (have $old)"
        if (( DRY )); then return 0; fi
        if git -C "$HOME/.fzf" pull -q --ff-only && "$HOME/.fzf/install" --bin >/dev/null; then
            new=$("$HOME/.fzf/bin/fzf" --version); note_upgrade fzf "$old" "${new%% *}"
        else
            FAILED+=(fzf)
        fi
        return 0
    fi
    if have fzf; then (( UPGRADE )) && { info "fzf: package-manager copy, leave it to apt (nu)"; SKIPPED+=(fzf); }; return 0; fi
    if [[ -x $HOME/.fzf/bin/fzf ]]; then SKIPPED+=(fzf); return 0; fi
    have git || { warn "fzf: git needed for the user-local install"; FAILED+=(fzf); return 1; }
    info "fzf → ~/.fzf"
    if (( DRY )); then return 0; fi
    git clone --depth 1 -q https://github.com/junegunn/fzf.git "$HOME/.fzf" &&
        "$HOME/.fzf/install" --bin >/dev/null && INSTALLED+=(fzf) || FAILED+=(fzf)
}
install_blesh() {
    local dest="$HOME/.local/share/blesh" old=''
    if [[ -f $dest/ble.sh ]]; then
        (( UPGRADE )) || { SKIPPED+=(ble.sh); return 0; }
        old=$(bash "$dest/ble.sh" --version 2>/dev/null); old=${old#*version }; old=${old%% *}   # "ble.sh (Bash Line Editor), version 0.4.0-nightly+5fe06d6"
        info "ble.sh: refreshing nightly (have $old)"
    else
        info "ble.sh → $dest (nightly release tarball)"
    fi
    if (( DRY )); then return 0; fi
    local tmp; tmp=$(mktemp -d)
    if curl -fsSL https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz | tar xJ -C "$tmp" &&
       mkdir -p "$(dirname "$dest")" && rm -rf "$dest" && mv "$tmp"/ble-nightly "$dest"; then
        if [[ -n $old ]]; then local new; new=$(bash "$dest/ble.sh" --version 2>/dev/null); new=${new#*version }; new=${new%% *}
            note_upgrade ble.sh "$old" "$new"
        else INSTALLED+=(ble.sh); fi
    else
        FAILED+=(ble.sh)
    fi
    rm -rf "$tmp"
}
install_mcrcon() {
    have mcrcon && { SKIPPED+=(mcrcon); return 0; }
    info "mcrcon: building from source"
    if (( DRY )); then return 0; fi
    if ! { have gcc && have make; }; then warn "mcrcon needs gcc and make (--with-dev)"; FAILED+=(mcrcon); return 1; fi
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
        elif [[ $PROFILE == uw ]]; then
            info "UW student server: no root — installing user-local tools only (~/.local/bin, ~/.fzf, ~/.local/share/blesh)"
        else
            warn "no supported package manager found — installing user-local tools only"
        fi
    else
        pkg_update_lists
        install_pkgs "core" "${CORE_PKGS[@]}"
        case $PROFILE in
            pi)      install_pkgs "pi" "${PI_PKGS[@]}" ;;
            desktop) install_pkgs "desktop" "${DESKTOP_PKGS[@]}" ;;
            omarchy) install_pkgs "omarchy" "${OMARCHY_PKGS[@]}" ;;
        esac
        (( WITH_DEV ))    && install_pkgs "dev" "${DEV_PKGS[@]}"
        (( WITH_ZOXIDE )) && install_pkgs "zoxide" zoxide
    fi
    # Fallbacks / user-local installs for the things the prompt needs.
    # With --upgrade, whatever is already installed user-locally is refreshed too
    # (zoxide only if it is there — it stays opt-in).
    install_starship_local
    if (( WITH_ZOXIDE )) || { (( UPGRADE )) && is_user_local zoxide; }; then install_zoxide_local; fi
    install_fzf_local
    if (( WITH_BLESH )) || { (( UPGRADE )) && [[ -f $HOME/.local/share/blesh/ble.sh ]]; }; then install_blesh; fi
    (( WITH_MCRCON )) && install_mcrcon
    [[ $PROFILE == desktop ]] && install_nerd_font

    # Things we do not install for you but the profile can use.
    case $PROFILE in
        pi)  have docker      || warn "docker not found — install with: curl -fsSL https://get.docker.com | sh"
             have cloudflared || warn "cloudflared not found — see https://pkg.cloudflare.com" ;;
        nas) have nvim || have vim || warn "no vim/nvim on this NAS — EDITOR will fall back to nano" ;;
        uw)  have nvim || warn "no nvim on this server — unpack a release into ~/.local (EDITOR falls back to vim)"
             { have gcc && have valgrind; } || warn "gcc/valgrind missing — the C helpers (ru/rut) need them" ;;
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

# link_layered — the Omarchy profile. Omarchy owns ~/.bashrc and ships its own
# ~/.config/starship.toml, so nothing is replaced: a marked block is appended to
# ~/.bashrc (idempotent, and what --uninstall removes), and the starship theme is
# selected with STARSHIP_CONFIG from profiles/omarchy.sh rather than by symlink.
link_layered() {
    local rc="$HOME/.bashrc"
    if grep -qF 'bashrc-profile: BEGIN' "$rc" 2>/dev/null; then
        ok "~/.bashrc already sources the profile"
    elif (( DRY )); then
        printf '%s[dry-run]%s append the bashrc-profile block to %s\n' "$Y" "$N" "$rc"
    else
        cp "$rc" "$rc.bak.$TS" && ok "backed up ~/.bashrc → ~/.bashrc.bak.$TS"
        cat >> "$rc" <<EOF

# --- bashrc-profile: BEGIN (layered under Omarchy) ---
# Omarchy's own defaults are sourced above; this adds my profile on top of them.
# Every name both sides define is settled in profiles/omarchy.sh.
# To revert the whole integration: delete this block (or install.sh --uninstall).
[[ -r "$REPO_DIR/bashrc" ]] && source "$REPO_DIR/bashrc"
# --- bashrc-profile: END ---
EOF
        ok "~/.bashrc now sources $REPO_DIR/bashrc"
    fi
    link "$REPO_DIR/blerc" "$HOME/.blerc"
    info "~/.config/starship.toml left as Omarchy shipped it — profiles/omarchy.sh sets STARSHIP_CONFIG"
    install_theme_hook
}

# install_theme_hook — make the prompt follow the desktop theme. The hook is a
# stub that calls bin/starship-omarchy-palette in the repo, so editing the
# generator or themes/omarchy-auto.toml never means reinstalling it.
install_theme_hook() {
    local src="$REPO_DIR/hooks/50-starship-palette"
    local dst="$HOME/.config/omarchy/hooks/theme-set.d/50-starship-palette"
    [[ -f $src ]] || return 0
    if (( DRY )); then
        printf '%s[dry-run]%s install theme-set hook → %s\n' "$Y" "$N" "$dst"; return 0
    fi
    # omarchy-hook-install is the documented route; the copy is the fallback for
    # an Omarchy old enough not to ship it.
    local installed=0
    if command -v omarchy-hook-install >/dev/null 2>&1; then
        omarchy-hook-install theme-set "$src" >/dev/null 2>&1 && installed=1
    fi
    # Separate `if`, not `elif`: a present-but-failing omarchy-hook-install must
    # still fall through to the plain copy.
    if (( ! installed )) && mkdir -p "${dst%/*}" && cp "$src" "$dst" && chmod 755 "$dst"; then
        installed=1
    fi
    if (( installed )); then
        ok "theme-set hook installed — the prompt retints with \`omarchy theme set\`"
    else
        warn "could not install the theme-set hook (the prompt still works, it just will not follow the theme)"
    fi
}

link_files() {
    step "Linking files"
    if [[ $PROFILE == omarchy ]]; then link_layered; return; fi
    # Starship theme: themes/aurora.toml everywhere, themes/waterloo-gold.toml on the
    # UW servers. A theme already linked from themes/ is kept (you picked it by hand).
    local theme=themes/aurora.toml current
    [[ $PROFILE == uw ]] && theme=themes/waterloo-gold.toml
    current=$(readlink -f "$HOME/.config/starship.toml" 2>/dev/null)
    if [[ $current == "$REPO_DIR"/themes/*.toml && -f $current ]]; then theme=${current#"$REPO_DIR"/}; fi
    link "$REPO_DIR/bashrc"  "$HOME/.bashrc"
    link "$REPO_DIR/$theme"  "$HOME/.config/starship.toml"
    link "$REPO_DIR/blerc"   "$HOME/.blerc"

    # Login shells must reach ~/.bashrc (ssh does a login shell).
    if [[ -f $HOME/.bash_profile ]] && ! grep -q 'bashrc' "$HOME/.bash_profile"; then
        warn "~/.bash_profile exists but never sources ~/.bashrc — add:  [ -f ~/.bashrc ] && . ~/.bashrc"
    elif [[ ! -f $HOME/.bash_profile && ! -f $HOME/.profile ]]; then
        info "creating ~/.profile so login shells load ~/.bashrc"
        # shellcheck disable=SC2016  # the $ must reach the file unexpanded
        (( DRY )) || printf '# ~/.profile\n[ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' > "$HOME/.profile"
    elif [[ -f $HOME/.profile ]] && ! grep -q 'bashrc' "$HOME/.profile"; then
        info "~/.profile exists but never sources ~/.bashrc — appending the standard snippet"
        # shellcheck disable=SC2016  # the $ must reach the file unexpanded
        (( DRY )) || printf '\n# added by bashrc-profile: login shells load ~/.bashrc\n[ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' >> "$HOME/.profile"
    fi
}

# config_lines — the toggle lines both write_config and refresh_config use.
# Add a new BASHRC_* toggle here (and its default in bashrc): --update then
# appends it to existing configs without touching the values already there.
config_lines() {
    local ff=0; [[ $PROFILE == desktop ]] && ff=1
    # Omarchy loads bash-completion eagerly in its own rc, so lib/core.sh's lazy
    # loader is a no-op there; say so in the file rather than implying it is live.
    local lazy=1; [[ $PROFILE == omarchy ]] && lazy=0
    cat <<CFG
BASHRC_PROFILE=$PROFILE      # pi | nas | desktop | omarchy | uw | server
BASHRC_PROFILE_DIR=$REPO_DIR
BASHRC_BLESH=$WITH_BLESH     # 1 = syntax highlighting + autosuggestions (ble.sh)
BASHRC_FASTFETCH=$ff         # 1 = fastfetch on new terminals
BASHRC_CD_LS_MAX=200         # cd auto-lists directories with at most this many entries
BASHRC_LAZY_COMPLETION=$lazy     # 1 = load bash-completion on first Tab (faster startup)
BASHRC_FZF_COMPLETION=0      # 1 = fzf **<Tab> fuzzy path completion (+25 ms startup)
BASHRC_ZOXIDE=$WITH_ZOXIDE             # 1 = zoxide z/zi (install with: prereqs --with-zoxide)
CFG
}

write_config() {
    step "Config"
    info "writing $CONFIG_DIR/config  (profile=$PROFILE blesh=$WITH_BLESH zoxide=$WITH_ZOXIDE)"
    (( DRY )) && return 0
    mkdir -p "$CONFIG_DIR"
    {
        echo "# bashrc-profile machine config — written by install.sh on $TS. Edit with: bt config"
        echo "# Environment beats this file: BASHRC_BLESH=0 bash -i tries a toggle without editing it."
        config_lines
    } > "$CONFIG_DIR/config"
    if [[ ! -f $HOME/.bashrc.local ]]; then
        cp "$REPO_DIR/bashrc.local.example" "$HOME/.bashrc.local"
        chmod 600 "$HOME/.bashrc.local"
        ok "seeded ~/.bashrc.local from the template — put secrets and ssh hosts there (bt local)"
    else
        ok "~/.bashrc.local kept"
    fi
    rm -f "$CACHE_DIR"/*.bash 2>/dev/null
}

# refresh_config — --update: append toggles that did not exist when this config
# was written. Existing lines (and their values/comments) are left alone.
refresh_config() {
    step "Config"
    [[ -f $CONFIG_DIR/config ]] || { write_config; return; }
    local line key added=0
    while IFS= read -r line; do
        key=${line%%=*}
        grep -q "^${key}=" "$CONFIG_DIR/config" && continue
        (( DRY )) || printf '%s\n' "$line" >> "$CONFIG_DIR/config"
        info "config: added ${line%%#*}"; added=1
    done < <(config_lines)
    (( added )) || ok "config up to date"
    # Keep BASHRC_PROFILE_DIR pointing at the repo we are running from.
    if ! grep -q "^BASHRC_PROFILE_DIR=$REPO_DIR\$" "$CONFIG_DIR/config"; then
        (( DRY )) || sed -i "s|^BASHRC_PROFILE_DIR=.*|BASHRC_PROFILE_DIR=$REPO_DIR|" "$CONFIG_DIR/config"
        info "config: BASHRC_PROFILE_DIR → $REPO_DIR"
    fi
}

# ── 5. Verify ────────────────────────────────────────────────────────────────
verify() {
    step "Verify"
    local f bad=0
    for f in "$REPO_DIR"/bashrc "$REPO_DIR"/lib/*.sh "$REPO_DIR"/profiles/*.sh \
             "$REPO_DIR"/bin/* "$REPO_DIR"/hooks/*; do
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
        out=${out//BASHRC_OK/}; out=$(grep -v 'Inappropriate ioctl\|no job control\|cannot set terminal\|cannot find a controlling TTY' <<< "$out")
        [[ -n $out ]] && warn "startup printed: $out"
    else
        err "test shell failed:"; echo "$out"; return 1
    fi
}

summary() {
    step "Summary"
    (( ${#INSTALLED[@]} )) && printf '%s installed:%s %s\n' "$G" "$N" "${INSTALLED[*]}"
    (( ${#UPGRADED[@]} ))  && { printf '%s upgraded:%s  ' "$G" "$N"; printf '%s; ' "${UPGRADED[@]}"; echo; }
    (( ${#SKIPPED[@]} ))   && printf '%s present:%s   %s\n' "$B" "$N" "${SKIPPED[*]}"
    (( ${#FAILED[@]} ))    && printf '%s failed:%s    %s\n' "$R" "$N" "${FAILED[*]}"
    (( DRY )) && { warn "dry run — nothing was changed"; return 0; }
    cat <<DONE

Done. Open a new terminal or run:  source ~/.bashrc

  profile   $PROFILE          (bt config to change)
  repo      $REPO_DIR
  secrets   ~/.bashrc.local   (bt local — RCON password, ssh hosts…)
  update    bup               (git pull, relink, refresh config, reload)
  deps      prereqs           (re-run dependency install;  prereqs --upgrade refreshes ble.sh/starship/fzf)
DONE
}

uninstall() {
    step "Uninstall"
    local f newest
    # Layered install: ~/.bashrc is Omarchy's real file with our block appended.
    if [[ ! -L $HOME/.bashrc ]] && grep -qF 'bashrc-profile: BEGIN' "$HOME/.bashrc" 2>/dev/null; then
        run cp "$HOME/.bashrc" "$HOME/.bashrc.bak.$TS"
        (( DRY )) || sed -i '/bashrc-profile: BEGIN/,/bashrc-profile: END/d' "$HOME/.bashrc"
        ok "removed the bashrc-profile block from ~/.bashrc (Omarchy's own config untouched)"
    fi
    for f in "$HOME/.bashrc" "$HOME/.config/starship.toml" "$HOME/.blerc"; do
        if [[ -L $f ]]; then
            run rm -f "$f"; ok "removed link $f"
            # shellcheck disable=SC2012  # backup names are ours (file.bak.TIMESTAMP), ls -t is fine
            newest=$(ls -t "$f".bak.* 2>/dev/null | head -1)
            if [[ -n $newest ]]; then run cp "$newest" "$f"; ok "restored $f from $newest"; fi
        fi
    done
    # The theme-set hook execs bin/starship-omarchy-palette in the repo. Left
    # behind, it fails on every `omarchy theme set` and omarchy-theme-set sends
    # that failure to /dev/null, so nobody would ever see it.
    f="$HOME/.config/omarchy/hooks/theme-set.d/50-starship-palette"
    if [[ -f $f ]]; then run rm -f "$f"; ok "removed theme-set hook $f"; fi
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
        update)    locate_repo; update_repo; link_files; refresh_config; rm -f "$CACHE_DIR"/*.bash 2>/dev/null; verify; summary; return ;;
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
