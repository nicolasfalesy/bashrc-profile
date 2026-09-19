#!/usr/bin/env bash
# =============================================================================
#  bashrc-profile — entry point
#  ~/.bashrc is a symlink to this file (created by install.sh).
#
#  Load order (see docs/ARCHITECTURE.md):
#    1. interactive guard           non-interactive shells (scp, rsync, ssh cmd) stop here
#    2. toggles                     defaults ← ~/.config/bashrc-profile/config ← environment
#    3. lib/core.sh                 shell options, history, PATH, env, readline, completion, lazy loader
#    4. lib/aliases.sh              aliases (editor, packages, git, docker, systemd, listing…) + bt/bup/bgit/prereqs
#    5. lib/navigation.sh           ll, cd (auto-list), up, mkcd, take, tre
#    6. lib/files.sh                extract, ftext, size, bak, diff2, path
#    7. lib/clipboard.sh            cpy, pst (OSC 52 — works over SSH)
#    8. lib/system.sh               sys, psg, port, killport, topp, myip, weather, t (tmux), rcon
#    9. lib/dev.sh                  C toolchain helpers — lazy-loaded on first use
#   10. profiles/<profile>.sh       pi | nas | desktop | omarchy | uw | server
#                                  (omarchy layers under Omarchy's own rc chain and
#                                   settles the names both sides define)
#   11. ~/.bashrc.local             per-machine secrets, ssh aliases, overrides (never in git)
#   12. lib/prompt.sh               fzf, starship, zoxide, ble-attach (must be last)
#
#  Quirks to keep in mind when editing (the long version is docs/ARCHITECTURE.md):
#    • Nothing below the interactive guard may print in a non-interactive shell —
#      scp/rsync/sftp break on stray output.
#    • ble.sh is sourced here with --noattach, *before* any `bind`, and attached at
#      the very end of lib/prompt.sh. Sourcing or attaching it anywhere else breaks
#      readline. It refuses to load in `bash -c …` shells (so `bash -ic exit`
#      timings never include it; use BASHRC_TIMING=1 in a real terminal).
#    • Aliases expand when a function is *parsed*. Inside functions call shadowed
#      tools as `command ls`, `command grep`, `command rm`…, and keep lib/aliases.sh
#      ahead of the function modules.
#    • Every module must be safe to source twice: `reload`, `bup` and `bt` re-source
#      this file in the running shell (ble.sh stays loaded; the BLE_VERSION guard
#      below skips it the second time).
#    • Try a different profile or toggle without editing anything:
#      BASHRC_PROFILE=pi BASHRC_BLESH=0 bash -i     (environment beats the config file)
#    • Helpers named _bashrc_* and _path_* are internal; the startup-only ones are
#      unset at the end of lib/prompt.sh.
# =============================================================================

# 1. Interactive shells only.
case $- in *i*) ;; *) return ;; esac

[[ ${BASHRC_TIMING-} == 1 ]] && _bashrc_t0=$EPOCHREALTIME

BASHRC_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bashrc-profile"
BASHRC_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bashrc-profile"

# 2. Feature toggles.  Precedence: environment > config file > defaults below.
#    The config file is plain bash written by install.sh (edit: bt config). Any
#    toggle already exported in the environment is put back after the file is
#    read, so `BASHRC_BLESH=0 bash -i` works even when the config says 1.
_bashrc_toggles=(BASHRC_PROFILE BASHRC_BLESH BASHRC_FASTFETCH BASHRC_CD_LS_MAX
                 BASHRC_LAZY_COMPLETION BASHRC_FZF_COMPLETION BASHRC_ZOXIDE)
_bashrc_env=()
for _m in "${_bashrc_toggles[@]}"; do [[ -n ${!_m-} ]] && _bashrc_env+=("$_m=${!_m}"); done
[[ -r "$BASHRC_CONFIG_DIR/config" ]] && . "$BASHRC_CONFIG_DIR/config"
for _m in "${_bashrc_env[@]}"; do declare -g "$_m"; done   # -g: bup sources this from inside a function
unset _bashrc_env _bashrc_toggles

BASHRC_PROFILE="${BASHRC_PROFILE:-}"        # pi | nas | desktop | omarchy | uw | server  (empty = autodetect)
BASHRC_BLESH="${BASHRC_BLESH:-1}"           # 1 = ble.sh (syntax highlighting, autosuggestions) when installed
BASHRC_FASTFETCH="${BASHRC_FASTFETCH:-0}"   # 1 = run fastfetch on new terminals
BASHRC_CD_LS_MAX="${BASHRC_CD_LS_MAX:-200}" # cd auto-lists dirs with at most this many entries
BASHRC_LAZY_COMPLETION="${BASHRC_LAZY_COMPLETION:-1}"  # 1 = load bash-completion on first Tab
BASHRC_FZF_COMPLETION="${BASHRC_FZF_COMPLETION:-0}"    # 1 = fzf **<Tab> fuzzy completion (+25 ms)
BASHRC_ZOXIDE="${BASHRC_ZOXIDE:-0}"         # 1 = zoxide z/zi (needs `prereqs --with-zoxide`)

# Where is the repo? The installer records it; otherwise resolve the ~/.bashrc symlink.
if [[ -z ${BASHRC_PROFILE_DIR-} || ! -f $BASHRC_PROFILE_DIR/lib/core.sh ]]; then
    BASHRC_PROFILE_DIR=$(readlink -f "${BASH_SOURCE[0]}"); BASHRC_PROFILE_DIR=${BASHRC_PROFILE_DIR%/*}
fi
export BASHRC_PROFILE_DIR

# Autodetect the machine profile when nothing set one. Same rules as install.sh.
# UW student servers: hostname or DNS search domain under uwaterloo.ca (no fork).
_bashrc_is_uw() {
    [[ $HOSTNAME == *uwaterloo* ]] && return 0
    local l; [[ -r /etc/resolv.conf ]] || return 1
    while read -r l; do [[ $l == search*uwaterloo.ca* || $l == domain*uwaterloo.ca* ]] && return 0; done < /etc/resolv.conf
    return 1
}
if [[ -z $BASHRC_PROFILE ]]; then
    if [[ -r /proc/device-tree/model ]] && { read -r _m < /proc/device-tree/model; [[ $_m == *"Raspberry Pi"* ]]; }; then
        BASHRC_PROFILE=pi
    elif [[ -d /usr/share/truenas || -x /usr/bin/midclt ]]; then
        BASHRC_PROFILE=nas
    elif [[ -d /usr/share/omarchy ]]; then
        BASHRC_PROFILE=omarchy
    elif [[ -n ${DISPLAY-} || -n ${WAYLAND_DISPLAY-} ]]; then
        BASHRC_PROFILE=desktop
    elif _bashrc_is_uw; then
        BASHRC_PROFILE=uw
    else
        BASHRC_PROFILE=server
    fi
fi
unset -f _bashrc_is_uw
export BASHRC_PROFILE

# ble.sh must be sourced before anything touches readline; attached at the very end.
# The BLE_VERSION guard keeps `reload` from loading it a second time.
if [[ $BASHRC_BLESH == 1 && -z ${BLE_VERSION-} && -r "$HOME/.local/share/blesh/ble.sh" ]]; then
    . "$HOME/.local/share/blesh/ble.sh" --noattach
fi

# A layered profile (omarchy) sources this file *after* another framework's rc,
# so that framework's aliases are already live while our modules are parsed —
# and bash expands aliases when a function is *defined*. Omarchy aliases both
# `t` and `cd`, which silently wrecked two of our functions:
#   `t() {`  → `tmux attach || tmux new -s Work() {`  → syntax error, and the
#              rest of lib/system.sh (rcon) never loaded
#   `cd() {` → `zd() {`  → defined our body under zoxide's name, clobbering it
# Defining aliases still works with expansion off, and nothing in this repo
# relies on an alias expanding inside a function body (that is why the modules
# call `command ls`, `command rm` … in the first place), so switch expansion off
# for the load and restore whatever the shell had afterwards.
_bashrc_ea=$(shopt -p expand_aliases)
[[ $BASHRC_PROFILE == omarchy ]] && shopt -u expand_aliases

# 3–8. Shared modules, in order. clipboard.sh borrows _size_fmt from files.sh, so it follows it.
for _m in core aliases navigation files clipboard system; do
    . "$BASHRC_PROFILE_DIR/lib/$_m.sh"
done
unset _m

# 9. lib/dev.sh is big and rarely needed: stubs load it on first call or Tab.
_bashrc_lazy dev ru run rud rund rut mkt

# 10. Machine profile.
[[ -r "$BASHRC_PROFILE_DIR/profiles/$BASHRC_PROFILE.sh" ]] && . "$BASHRC_PROFILE_DIR/profiles/$BASHRC_PROFILE.sh"

# 11. Local overrides — secrets, ssh hosts, anything that must not be committed.
[[ -r "$HOME/.bashrc.local" ]] && . "$HOME/.bashrc.local"

eval "$_bashrc_ea"; unset _bashrc_ea      # alias expansion back to normal

# 12. Prompt and interactive tooling. Last on purpose.
. "$BASHRC_PROFILE_DIR/lib/prompt.sh"

# BASHRC_TIMING=1 bash -i   →  prints how long startup took (includes ble-attach)
# shellcheck disable=SC2317  # reachable: the `return` above only fires for non-interactive shells
if [[ ${BASHRC_TIMING-} == 1 ]]; then
    printf 'bashrc-profile: %d ms (profile=%s)\n' "$(( (${EPOCHREALTIME/./} - ${_bashrc_t0/./}) / 1000 ))" "$BASHRC_PROFILE"
    unset _bashrc_t0
fi
