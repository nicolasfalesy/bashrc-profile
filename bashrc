#!/usr/bin/env bash
# =============================================================================
#  bashrc-profile — entry point
#  ~/.bashrc is a symlink to this file (created by install.sh).
#
#  Load order (see docs/ARCHITECTURE.md):
#    1. interactive guard           non-interactive shells (scp, rsync, ssh cmd) stop here
#    2. ~/.config/bashrc-profile/config   machine profile + feature toggles (written by installer)
#    3. lib/core.sh                 shell options, history, PATH, env, readline, completion
#    4. lib/aliases.sh              aliases (editor, packages, git, docker, systemd, listing…) + bt/bup/prereqs
#    5. lib/navigation.sh           ll, cd (auto-list), up, mkcd, take, tre
#    6. lib/files.sh                extract, ftext, size, bak, diff2, path
#    7. lib/system.sh               sys, psg, port, killport, topp, myip, weather, t (tmux), rcon
#    8. lib/dev.sh                  C toolchain helpers — lazy-loaded on first use
#    9. profiles/<profile>.sh       pi | nas | desktop | server
#   10. ~/.bashrc.local             per-machine secrets, ssh aliases, overrides (never in git)
#   11. lib/prompt.sh               fzf, starship, zoxide, ble.sh (must be last)
# =============================================================================

# 1. Interactive shells only.
case $- in *i*) ;; *) return ;; esac

[[ ${BASHRC_TIMING-} == 1 ]] && _bashrc_t0=$EPOCHREALTIME

BASHRC_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bashrc-profile"
BASHRC_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bashrc-profile"

# 2. Feature toggles — defaults, overridden by the config file (bt config).
BASHRC_PROFILE="${BASHRC_PROFILE:-}"        # pi | nas | desktop | server  (empty = autodetect)
BASHRC_BLESH="${BASHRC_BLESH:-0}"           # 1 = load ble.sh (syntax highlighting, autosuggest)
BASHRC_FASTFETCH="${BASHRC_FASTFETCH:-0}"   # 1 = run fastfetch on new terminals
BASHRC_CD_LS_MAX="${BASHRC_CD_LS_MAX:-200}" # cd auto-lists dirs with at most this many entries
BASHRC_LAZY_COMPLETION="${BASHRC_LAZY_COMPLETION:-1}"  # 1 = load bash-completion on first Tab
BASHRC_FZF_COMPLETION="${BASHRC_FZF_COMPLETION:-0}"    # 1 = fzf **<Tab> fuzzy completion (slow)

[[ -r "$BASHRC_CONFIG_DIR/config" ]] && . "$BASHRC_CONFIG_DIR/config"

# Where is the repo? The installer records it; otherwise resolve the ~/.bashrc symlink.
if [[ -z ${BASHRC_PROFILE_DIR-} || ! -f $BASHRC_PROFILE_DIR/lib/core.sh ]]; then
    BASHRC_PROFILE_DIR=$(readlink -f "${BASH_SOURCE[0]}"); BASHRC_PROFILE_DIR=${BASHRC_PROFILE_DIR%/*}
fi
export BASHRC_PROFILE_DIR

# Autodetect the machine profile when nothing set one.
if [[ -z $BASHRC_PROFILE ]]; then
    if [[ -r /proc/device-tree/model ]] && { read -r _m < /proc/device-tree/model; [[ $_m == *"Raspberry Pi"* ]]; }; then
        BASHRC_PROFILE=pi
    elif [[ -d /usr/share/truenas || -x /usr/bin/midclt ]]; then
        BASHRC_PROFILE=nas
    elif [[ -n ${DISPLAY-} || -n ${WAYLAND_DISPLAY-} ]]; then
        BASHRC_PROFILE=desktop
    else
        BASHRC_PROFILE=server
    fi
    unset _m
fi
export BASHRC_PROFILE

# ble.sh must be sourced before anything touches readline; attached at the very end.
if [[ $BASHRC_BLESH == 1 && -z ${BLE_VERSION-} && -r "$HOME/.local/share/blesh/ble.sh" ]]; then
    . "$HOME/.local/share/blesh/ble.sh" --noattach
fi

# 3–7. Shared modules, in order.
for _m in core aliases navigation files system; do
    . "$BASHRC_PROFILE_DIR/lib/$_m.sh"
done
unset _m

# 8. lib/dev.sh is big and rarely needed: stubs load it on first call or Tab.
_bashrc_lazy dev ru run rud rund rut mkt

# 9. Machine profile.
[[ -r "$BASHRC_PROFILE_DIR/profiles/$BASHRC_PROFILE.sh" ]] && . "$BASHRC_PROFILE_DIR/profiles/$BASHRC_PROFILE.sh"

# 10. Local overrides — secrets, ssh hosts, anything that must not be committed.
[[ -r "$HOME/.bashrc.local" ]] && . "$HOME/.bashrc.local"

# 11. Prompt and interactive tooling. Last on purpose.
. "$BASHRC_PROFILE_DIR/lib/prompt.sh"

# BASHRC_TIMING=1 bash -i   →  prints how long startup took
if [[ ${BASHRC_TIMING-} == 1 ]]; then
    printf 'bashrc-profile: %d ms (profile=%s)\n' "$(( (${EPOCHREALTIME/./} - ${_bashrc_t0/./}) / 1000 ))" "$BASHRC_PROFILE"
    unset _bashrc_t0
fi
