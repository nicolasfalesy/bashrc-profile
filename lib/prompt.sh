#!/usr/bin/env bash
# lib/prompt.sh — fastfetch, fzf, starship, zoxide, ble-attach. Loaded last.
#
# Speed: `starship init` and `zoxide init` each spawn a process that just prints
# a shell script. That output is cached in ~/.cache/bashrc-profile and rebuilt
# only when the binary is newer than the cache — zero forks on a normal start.
# The starship script is also patched so the shell's own $EPOCHREALTIME replaces
# the `starship time` subprocess it would otherwise run before and after every
# command (two forks per prompt on a Pi).
#
# Quirks:
#   • starship replaces PROMPT_COMMAND with `starship_precmd` and runs whatever was
#     there before (our `history -a` from lib/core.sh) from $STARSHIP_PROMPT_COMMAND.
#     Don't "fix" PROMPT_COMMAND after this file — append to it before it instead.
#   • With ble.sh attached, ble.sh owns history writing (bleopt history_share in
#     blerc) and PROMPT_COMMAND is unset *during* command execution — a function
#     that reads $PROMPT_COMMAND at runtime will see it empty. Normal.
#   • Anything that must not run twice on `reload` needs its own guard; the cache
#     helper is naturally idempotent, ble-attach is a no-op when already attached.

[[ -d $BASHRC_CACHE_DIR ]] || command mkdir -p "$BASHRC_CACHE_DIR" 2>/dev/null

_bashrc_cached_init() {   # <cache-name> <binary> <command...>
    local name=$1 bin=$2; shift 2
    hash "$bin" 2>/dev/null || return 1
    local path=${BASH_CMDS[$bin]} cache="$BASHRC_CACHE_DIR/$name.bash"
    if [[ ! -s $cache || $path -nt $cache ]]; then
        if "$@" > "$cache.$$" 2>/dev/null; then
            [[ $name == starship ]] && _bashrc_patch_starship "$cache.$$" "$path"
            command mv -f "$cache.$$" "$cache"
        else
            command rm -f "$cache.$$"; return 1
        fi
    fi
    . "$cache"
}
_bashrc_patch_starship() {   # <file> <starship-path>
    local ps2
    ps2=$("$2" prompt --continuation 2>/dev/null)
    {
        # shellcheck disable=SC2016  # the $ in this banner is meant literally
        printf '# patched by bashrc-profile: literal PS2, $EPOCHREALTIME instead of `starship time`\n'
        sed -e "s|\"\$($2 prompt --continuation)\"|'${ps2//\'/\'\\\'\'}'|" \
            -e "s|\$($2 time)|\$(( \${EPOCHREALTIME/./} / 1000 ))|g" \
            -e "s|^\( *\)$2 time\$|\1echo \$(( \${EPOCHREALTIME/./} / 1000 ))|" "$1"
    } > "$1.p" && command mv -f "$1.p" "$1"
}

# ── fastfetch on new terminals (toggle: BASHRC_FASTFETCH in bt config) ───────
# Only top-level terminals (not tmux panes, not `bash` typed inside bash).
if [[ $BASHRC_FASTFETCH == 1 && -z ${TMUX-} && $SHLVL -le 2 ]] && hash fastfetch 2>/dev/null; then
    fastfetch
fi

# ── fzf: Ctrl-R history, Ctrl-T files, Alt-C cd ──────────────────────────────
# completion.bash (the `vim **<Tab>` feature) costs ~25 ms, so it is opt-in.
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
if [[ $BASHRC_BLESH == 1 && -n ${BLE_VERSION-} ]]; then
    ble-import -d integration/fzf-key-bindings
    [[ $BASHRC_FZF_COMPLETION == 1 ]] && ble-import -d integration/fzf-completion
else
    for _f in "$HOME/.fzf/shell" /usr/share/doc/fzf/examples /usr/share/fzf; do
        if [[ -r $_f/key-bindings.bash ]]; then
            . "$_f/key-bindings.bash"
            [[ $BASHRC_FZF_COMPLETION == 1 && -r $_f/completion.bash ]] && . "$_f/completion.bash"
            break
        fi
    done
    unset _f
fi

# ── starship prompt (fallback: plain coloured PS1) ───────────────────────────
if ! _bashrc_cached_init starship starship starship init bash --print-full-init; then
    PS1='\[\e[01;32m\]\u@\h\[\e[0m\]:\[\e[01;34m\]\w\[\e[0m\]\$ '
fi

# ── zoxide: z <dir>, zi (interactive) — opt-in: BASHRC_ZOXIDE=1 in bt config ─
if [[ $BASHRC_ZOXIDE == 1 ]] && _bashrc_cached_init zoxide zoxide zoxide init bash; then
    __zoxide_cd() { cd "$@" || return; }     # route z/zi through our auto-listing cd
fi

# ── ble.sh: attach (sourced with --noattach at the top of bashrc) ────────────
[[ $BASHRC_BLESH == 1 && -n ${BLE_VERSION-} ]] && ble-attach

# Startup-only helpers. (_bashrc_cached_init stays: bup clears the cache and
# a reload rebuilds it.)
unset -f _path_prepend _path_append
return 0
