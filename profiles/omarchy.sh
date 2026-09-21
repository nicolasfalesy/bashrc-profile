#!/usr/bin/env bash
# profiles/omarchy.sh — Arch laptop running Omarchy (Hyprland, foot, limine).
#
# This profile is LAYERED, unlike every other one in the repo. ~/.bashrc keeps
# sourcing Omarchy's own rc chain (/usr/share/omarchy/default/bash/rc) and then
# sources this repo's bashrc on top of it, so both sets of aliases and functions
# are live. Nothing under /usr/share/omarchy is modified — reverting the whole
# integration is deleting three lines from ~/.bashrc.
#
# Because of that, this file has a second job beyond the usual per-machine
# extras: it settles the names Omarchy and this repo both define. It is sourced
# after lib/aliases.sh (step 10 of bashrc), so it gets the last word.
#
#   name  winner   note
#   ----  -------  ----------------------------------------------------------
#   cd    omarchy  Omarchy's `alias cd='zd'` (zoxide) beats our cd() function
#                  on its own — an alias outranks a function — so there is
#                  nothing to do here. z/zi jump; no auto-listing.
#   c     ours     clear. Omarchy's `opencode --auto` moves to `o`.
#   h     omarchy  herdr. Our `history | grep` moves to `hg`.
#   lt    omarchy  eza tree (and its `lta` companion). Our `ll -tr` → `ltr`.
#   t     merged   our session manager, but bare `t` attaches "Work" the way
#                  Omarchy's one-liner did.
#   ga    ours     git add.  Omarchy's worktree-add    moves to `wta`.
#   gd    ours     git diff. Omarchy's worktree-remove moves to `wtd`.
#
# `..`, `...` and `gcm` also collide but are defined identically on both sides.
# starship, fzf key bindings and command_not_found_handle overlap harmlessly:
# ours loads last, and lib/prompt.sh's cached starship init is the faster one.
#
# Deliberately NOT taken from profiles/desktop.sh:
#   at, kt   Alacritty config editors — only foot is installed, and Omarchy has
#            its own theme system (omarchy-theme-set).
#   grub     this machine boots limine; `update-grub` does not exist on Arch.
#   QT_QPA_PLATFORMTHEME=qt5ct — Omarchy already handles Qt theming.
#   claude   lib/aliases.sh's `claude --dangerously-skip-permissions` is undone
#            below: this box has its own permission-mode wiring, and a CLI flag
#            beats settings.json, so the alias would quietly defeat it. Omarchy's
#            `cx` already covers the pre-set case.

export TERMINAL=/usr/bin/foot
export NOTES_FILE="${NOTES_FILE:-$HOME/Documents/quick-notes.txt}"

# Our starship theme, without touching ~/.config/starship.toml — that file is
# Omarchy's, byte-identical to what it ships. STARSHIP_CONFIG wins over it and
# is read fresh at every prompt, so `bt theme` edits show up immediately.
#
# The prompt follows the desktop theme. themes/omarchy-auto.toml refers to its
# colours by name only; bin/starship-omarchy-palette renders it against the
# current theme's colors.toml into the cache, and the theme-set hook re-renders
# it whenever `omarchy theme set` runs. What is left here is the cold-start path:
# a cleared cache, or a template edited since the last render. When the rendered
# file is present and current this is two [[ ]] tests and no fork.
export BASHRC_STARSHIP_TEMPLATE="$BASHRC_PROFILE_DIR/themes/omarchy-auto.toml"
export STARSHIP_CONFIG="$BASHRC_CACHE_DIR/starship-omarchy.toml"
if [[ ! -s $STARSHIP_CONFIG || $BASHRC_STARSHIP_TEMPLATE -nt $STARSHIP_CONFIG ]]; then
    # Silent: a theme that cannot be rendered (no Omarchy colors.toml — this
    # profile forced on a box without it) must not print on every new terminal.
    BASHRC_STARSHIP_OUT=$STARSHIP_CONFIG \
        "$BASHRC_PROFILE_DIR/bin/starship-omarchy-palette" --force 2>/dev/null ||
        export STARSHIP_CONFIG="$BASHRC_PROFILE_DIR/themes/aurora.toml"
fi

# ── helper: move an Omarchy function aside instead of losing it ───────────────
# Safe to run twice: `reload` re-sources Omarchy's rc chain first, which puts the
# original function back, and the grep guard skips a wrapper we already made.
_omarchy_rename_fn() {   # <old> <new>
    # Already moved (a reload re-sourced Omarchy's rc, which put the original
    # back): just drop the duplicate. This is the common path and costs nothing.
    if declare -F "$2" >/dev/null 2>&1; then unset -f "$1" 2>/dev/null; return 0; fi
    declare -F "$1" >/dev/null 2>&1 || return 0
    # One command substitution, and bash's own prefix-strip instead of piping
    # through grep and sed — this runs on every new shell, so three renames used
    # to mean nine forked processes before the prompt appeared.
    local body; body=$(declare -f "$1")
    eval "$2${body#"$1"}" && unset -f "$1"
    return 0
}

# ── collisions ───────────────────────────────────────────────────────────────
alias o='opencode --auto'                  # Omarchy's `c`, rehomed (ours is clear)
alias h='herdr'                            # Omarchy wins: Ctrl-R already does history
alias hg='history | grep'                  # ours, rehomed
alias lt='eza --tree --level=2 --long --icons --git'   # Omarchy wins: git-aware tree
alias ltr='ll -tr'                         # ours, rehomed (mnemonic: ls -tr)

# `c` is in lib/core.sh's HISTIGNORE, which was written when `c` meant clear.
# It still does here, so nothing to adjust — but keep it in mind if that flips.

# t — our session manager, with Omarchy's zero-argument attach-or-create.
unalias t 2>/dev/null
_omarchy_rename_fn t _t_session
t() {
    if (( $# == 0 )); then _t_session Work; else _t_session "$@"; fi
}

# ga / gd stay `git add` / `git diff` from lib/aliases.sh (an alias outranks the
# function, so they already win). Omarchy's worktree helpers are moved rather
# than left shadowed — and this also takes `gd` out of the "delete this worktree
# and branch?" business, which is a bad thing to trigger by muscle memory.
_omarchy_rename_fn ga wta                  # wta <branch>  → add worktree + cd into it
_omarchy_rename_fn gd wtd                  # wtd           → remove worktree + branch

# Leave `claude` as the real binary — see the header. Omarchy's `cx` is the
# pre-set-permission-mode shortcut on this machine.
unalias claude 2>/dev/null

# ── packages (lib/aliases.sh only defines these for nala/apt) ────────────────
alias ni='sudo pacman -S --needed'
alias np='sudo pacman -Rns'
alias ns='pacman -Ss'
alias nq='pacman -Q'
# Not `pacman -Syu`: this machine's mirror is pinned to a frozen snapshot on
# purpose, and omarchy-update is what advances that pin and runs the migrations.
alias nu='omarchy-update'
nclean() {
    local orphans
    orphans=$(pacman -Qtdq 2>/dev/null)
    if [[ -n $orphans ]]; then
        # shellcheck disable=SC2086  # deliberate word splitting: one package per line
        sudo pacman -Rns --noconfirm $orphans
    else
        echo "No orphaned packages."
    fi
    if command -v paccache >/dev/null 2>&1; then
        sudo paccache -rk2
    else
        echo "paccache: install pacman-contrib to prune the package cache"
    fi
}

# btop is what this machine has; `htop` is the reflex.
if ! command -v htop >/dev/null 2>&1 && command -v btop >/dev/null 2>&1; then
    alias htop='btop'
fi

# ── vpn — WireGuard wg0 ──────────────────────────────────────────────────────
# Shares its logic with the taskbar toggle: both go through omarchy-vpn-toggle
# when it is installed, so the bar and the shell can never disagree about state.
# (No WG_QUICK_USERSPACE_IMPLEMENTATION=bash here — that was an Ubuntu-on-ARM
# stat bug workaround, irrelevant on x86 Arch.)
vpn() {
    local helper="$HOME/.local/bin/omarchy-vpn-toggle"
    case ${1-} in
        -h|--help)
            echo "Usage: vpn        connect wg0"
            echo "       vpn -s     status"
            echo "       vpn -d     disconnect"
            echo "       vpn -t     toggle (what the taskbar button does)"
            return 0 ;;
        -s) if [[ -x $helper ]]; then
                echo "wg0: $("$helper" status)"
                # An `if`, not `[[ … ]] &&`: as the last command in the branch a
                # false guard would become the function's exit status, so `vpn -s`
                # returned 1 merely because the tunnel was down.
                if [[ -d /sys/class/net/wg0 ]]; then sudo -n wg show wg0 2>/dev/null; fi
            else
                sudo wg show
            fi
            return 0 ;;
        -d|-r|-p) if [[ -x $helper ]]; then "$helper" down; else sudo wg-quick down wg0; fi ;;
        -t) [[ -x $helper ]] && { "$helper" toggle; return; }
            if sudo wg show wg0 >/dev/null 2>&1; then vpn -d; else vpn; fi ;;
        *)  if [[ -x $helper ]]; then "$helper" up; return; fi
            echo "Connecting… 🔒"
            sudo wg-quick up wg0 && echo "VPN is up ✅" ;;
    esac
}

# ── note — quick scratchpad (NOTES_FILE) ─────────────────────────────────────
note() {
    case ${1-} in
        -h|--help|'')
            echo "Usage: note <text>  |  note -l (list)  |  note -e (edit)  |  note -c (clear)"
            echo "File: $NOTES_FILE"; return 0 ;;
        -l|--list)  [[ -f $NOTES_FILE ]] && cat -n "$NOTES_FILE" || echo "(no notes yet)" ;;
        -e|--edit)  $EDITOR "$NOTES_FILE" ;;
        -c|--clear) local ok; read -rp "Clear all notes? [y/N] " ok
                    [[ $ok =~ ^[Yy]$ ]] && : > "$NOTES_FILE" && echo "Notes cleared." ;;
        *)  command mkdir -p "$(dirname "$NOTES_FILE")"
            echo "[$(date '+%Y-%m-%d %H:%M')] $*" >> "$NOTES_FILE" && echo "Note saved." ;;
    esac
}
alias notes='$EDITOR "$NOTES_FILE"'

# ── apps / install_app — ~/.local/share/applications helpers ─────────────────
apps() {
    case ${1-} in
        -h|--help) echo "Usage: apps        cd to ~/.local/share/applications"
                   echo "       apps -u     update desktop database"; return 0 ;;
        -u) update-desktop-database ~/.local/share/applications && echo "Desktop database updated ✅" ;;
        *)  cd ~/.local/share/applications || return ;;
    esac
}
install_app() {
    local dir="$HOME/.local/share/applications"
    case ${1-} in
        -h|--help|'')
            echo "Usage: install_app <file.desktop>   symlink a .desktop file into $dir"
            echo "       install_app -l [query]        list installed local apps"; return 0 ;;
        -l) command ls "$dir" | command grep '\.desktop$' | sed 's/\.desktop$//' | command grep -i -- "${2:-.}" ;;
        *)  local src; src=$(realpath -- "$1" 2>/dev/null)
            [[ -f $src && $src == *.desktop ]] || { echo "install_app: not a .desktop file" >&2; return 1; }
            ln -sf "$src" "$dir/$(basename "$src")" && echo "✅ Linked $(basename "$src")" ;;
    esac
}
