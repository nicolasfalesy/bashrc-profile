#!/usr/bin/env bash
# lib/core.sh — shell options, history, PATH, environment, readline, completion.
# Loaded first; every other module may rely on what is set here.

# ── Shell options ────────────────────────────────────────────────────────────
shopt -s histappend               # append to HISTFILE instead of overwriting it
shopt -s checkwinsize             # keep LINES/COLUMNS correct after a resize
shopt -s cmdhist                  # save multi-line commands as one history entry
shopt -s cdspell                  # fix minor typos in `cd` paths
shopt -s no_empty_cmd_completion  # don't scan PATH on Tab at an empty prompt

# ── History ──────────────────────────────────────────────────────────────────
HISTSIZE=50000                     # lines kept in memory
HISTFILESIZE=100000                # lines kept on disk
HISTCONTROL=ignoreboth:erasedups   # skip dupes + space-prefixed cmds, drop older dupes
HISTTIMEFORMAT='%F %T '            # timestamps in `history`
HISTIGNORE='ls:ll:l:c:clear:e:exit:bg:fg:history*'
PROMPT_COMMAND='history -a'        # write each command immediately (starship keeps this)

# ── Readline / keys ──────────────────────────────────────────────────────────
bind 'set bell-style visible'
bind 'set completion-ignore-case on'
bind 'set show-all-if-ambiguous on'          # one Tab shows the list
bind 'set colored-stats on'                  # colour file types in completion lists
bind 'set colored-completion-prefix on'      # highlight the part already typed
bind 'set mark-symlinked-directories on'
bind '"\C-z": undo'
stty -ixon 2>/dev/null                       # free Ctrl-S for forward history search

# ── XDG base directories ─────────────────────────────────────────────────────
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# ── PATH: prepend user dirs, append system extras, never duplicate ───────────
_path_prepend() { [[ -d $1 && ":$PATH:" != *":$1:"* ]] && PATH="$1:$PATH"; return 0; }
_path_append()  { [[ -d $1 && ":$PATH:" != *":$1:"* ]] && PATH="$PATH:$1"; return 0; }
_path_prepend "$HOME/.local/bin"
_path_prepend "$HOME/.cargo/bin"
_path_prepend "$HOME/.fzf/bin"
_path_append  /usr/local/go/bin
_path_append  /var/lib/flatpak/exports/bin
_path_append  "$XDG_DATA_HOME/flatpak/exports/bin"
export PATH

# ── Editor: first available of nvim → vim → nano ────────────────────────────
# An EDITOR already in the environment is respected (ssh SendEnv, a systemd
# user session, `EDITOR=nano bt local` for one call). Set a permanent choice in
# ~/.bashrc.local, which is sourced after this.
if [[ -z ${EDITOR-} ]]; then
    for _e in nvim vim nano; do
        if command -v "$_e" >/dev/null 2>&1; then export EDITOR=$_e; break; fi
    done
    unset _e
fi
export VISUAL="${VISUAL:-$EDITOR}"

# ── Pager / man page colours ─────────────────────────────────────────────────
export LESS='-R'                        # let colour through (git log, diff2, ftext…)
export LESS_TERMCAP_mb=$'\E[01;31m'     # blink     → bold red
export LESS_TERMCAP_md=$'\E[01;31m'     # bold      → bold red        (headings)
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'  # standout  → yellow on blue  (search hits)
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'     # underline → bold green      (options)

# ── Programmable completion ──────────────────────────────────────────────────
# bash-completion costs ~35 ms on a Pi. Login shells (ssh) already have it from
# /etc/profile.d, so it is skipped there. In other shells it is loaded on the
# first Tab press instead of at startup (BASHRC_LAZY_COMPLETION=0 to load eagerly).
_bashrc_completion_file=''
for _f in /usr/share/bash-completion/bash_completion /etc/bash_completion; do
    [[ -r $_f ]] && { _bashrc_completion_file=$_f; break; }
done
unset _f
_bashrc_load_completion() {   # installed as the default (-D) completer
    complete -r -D 2>/dev/null
    [[ -n $_bashrc_completion_file ]] && . "$_bashrc_completion_file"
    local loader
    loader=$(complete -p -D 2>/dev/null); loader=${loader#* -F }; loader=${loader%% *}
    [[ -n $loader && $loader != _bashrc_load_completion ]] && "$loader" "$@"
    return 124                # 124 = "spec changed, retry the completion"
}
if [[ -z ${BASH_COMPLETION_VERSINFO-} ]] && ! shopt -oq posix && [[ -n $_bashrc_completion_file ]]; then
    if [[ $BASHRC_LAZY_COMPLETION == 1 ]]; then
        complete -D -F _bashrc_load_completion
    else
        . "$_bashrc_completion_file"
    fi
fi

# ── Lazy loading ─────────────────────────────────────────────────────────────
# _bashrc_lazy <module> <function>...
# Installs stub functions that source lib/<module>.sh on first use (or first Tab
# completion) and then run the real function. Keeps big, rarely used modules
# (the C toolchain) out of the startup path.
_bashrc_lazy() {
    local mod=$1 fn; shift
    for fn in "$@"; do
        eval "$fn() { _bashrc_lazy_load $mod $*; $fn \"\$@\"; }"
        eval "_bashrc_lazy_complete_$fn() { _bashrc_lazy_load $mod $*; _bashrc_lazy_dispatch $fn \"\$@\"; }"
        complete -F "_bashrc_lazy_complete_$fn" "$fn"
    done
}
_bashrc_lazy_load() {           # <module> <function>...  (idempotent)
    local mod=$1 fn; shift
    for fn in "$@"; do unset -f "$fn"; complete -r "$fn" 2>/dev/null; done
    # bashrc sources the startup modules with alias expansion off so a
    # framework alias cannot rewrite our function bodies. This one is sourced
    # at first *use*, long after that guard was lifted, so it needs its own —
    # otherwise `rm` inside dev.sh becomes `trash -v` and `cp` becomes `cp -i`.
    local _ea; _ea=$(shopt -p expand_aliases)
    [[ $BASHRC_PROFILE == omarchy ]] && shopt -u expand_aliases
    . "$BASHRC_PROFILE_DIR/lib/$mod.sh"
    eval "$_ea"
}
_bashrc_lazy_dispatch() {       # call the completer the module registered for $1
    local spec
    spec=$(complete -p "$1" 2>/dev/null) || return 0
    [[ $spec == *" -F "* ]] || return 0
    spec=${spec#* -F }; spec=${spec%% *}
    "$spec" "$@"
}

# ── Red "command not found" (only when Debian's command-not-found is absent) ─
if ! declare -F command_not_found_handle >/dev/null; then
    command_not_found_handle() {
        printf '\033[0;31mcommand not found: %s\033[0m\n' "$1" >&2
        return 127
    }
fi
