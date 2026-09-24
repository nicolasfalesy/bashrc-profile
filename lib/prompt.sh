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
    # `type -P` and not `hash`/BASH_CMDS: a layered profile (omarchy) runs under
    # `set +h`, where the hash builtin always fails with "hashing disabled" and
    # BASH_CMDS is never populated — which silently cost us the cached starship
    # init and dropped the prompt to the plain-PS1 fallback.
    _bashrc_typep "$bin" || return 1           # lib/core.sh; no fork on bash 5.3
    local path=$REPLY
    local cache="$BASHRC_CACHE_DIR/$name.bash"
    # Also rebuilt when this file is newer than the cache: the patch below lives
    # here, so a change to it reaches the next terminal without a manual `bup`.
    if [[ ! -s $cache || $path -nt $cache || ( $name == starship && ${BASH_SOURCE[0]} -nt $cache ) ]]; then
        if "$@" > "$cache.$$" 2>/dev/null; then
            [[ $name == starship ]] && _bashrc_patch_starship "$cache.$$" "$path"
            command mv -f "$cache.$$" "$cache"
        else
            command rm -f "$cache.$$"; return 1
        fi
    fi
    . "$cache"
}
# What the patch changes in starship's own init script (2026-09-23 additions
# measured in a pty stand-in for a new kitty window, ble.sh on):
#  - PS2 is a literal instead of a `starship prompt --continuation` run.
#  - $EPOCHREALTIME instead of `starship time`, before and after every command,
#    also in PS0 (plain bash) where it was a $(starship_preexec_ps0) fork.
#  - With ble.sh, starship_precmd ran `starship prompt --right` on every prompt
#    to fill ble.sh's right prompt: a second starship process (~5 ms) that
#    printed nothing, since no theme here has a right_format. It now runs only
#    while _bashrc_starship_rps1 is set, which _bashrc_starship_rps1_check sets
#    from the config in use at startup (and `bt theme` after an edit).
#  - bash 5.3: `for job in $(jobs -p)` becomes ${ jobs -p; }, no fork (~1.8 ms
#    with ble.sh loaded). Decided when the cache is built; the cache is per
#    machine, and on an older bash the line is left alone. (If bash is ever
#    downgraded, `bup` rebuilds the cache.)
# Together about 24 ms per command with ble.sh on this laptop.
_bashrc_patch_starship() {   # <file> <starship-path>
    local ps2 funsub=()
    # STARSHIP_SHELL=bash, or starship leaves the \[ \] out around its colour
    # codes: the variable is only exported by this very init script, so a cache
    # built in a brand-new terminal (no parent starship) came out without them.
    ps2=$(STARSHIP_SHELL=bash "$2" prompt --continuation 2>/dev/null)
    # Quote it for the shell ('\''), then escape \ & | for the sed replacement
    # below. Unescaped, sed ate every backslash: the \[ \] became bare brackets
    # and the continuation prompt read "[]∙[] " instead of "∙ " (seen
    # 2026-09-23 in the cache built 2026-09-22).
    ps2=${ps2//\'/\'\\\'\'}
    ps2=${ps2//\\/\\\\}; ps2=${ps2//'&'/'\&'}; ps2=${ps2//'|'/'\|'}
    # shellcheck disable=SC2016  # the ${ } here is text for sed, not an expansion
    (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 503 )) &&
        funsub=(-e 's|\$(jobs -p)|${ jobs -p; }|')
    {
        # shellcheck disable=SC2016  # the $ in this banner is meant literally
        printf '# patched by bashrc-profile: literal PS2, $EPOCHREALTIME instead of `starship time`, right prompt only when configured\n'
        # shellcheck disable=SC2016  # the $ and ${ } in these sed scripts are meant literally
        sed -e "s|\"\$($2 prompt --continuation)\"|'$ps2'|" \
            -e "s|\$($2 time)|\$(( \${EPOCHREALTIME/./} / 1000 ))|g" \
            -e "s|^\( *\)$2 time\$|\1echo \$(( \${EPOCHREALTIME/./} / 1000 ))|" \
            -e 's|"\$(starship_preexec_ps0)"|$(( ${EPOCHREALTIME/./} / 1000 ))|' \
            -e 's|^\( *\)if \[\[ \${BLE_ATTACHED-} \]\]; then$|\1if [[ ${BLE_ATTACHED-} \&\& ${_bashrc_starship_rps1-} ]]; then|' \
            "${funsub[@]}" "$1"
    } > "$1.p" && command mv -f "$1.p" "$1"
}
# Does the starship config in use have a right prompt? A plain read of the file,
# no fork on bash 5.3. Sets _bashrc_starship_rps1 for the patched starship_precmd.
_bashrc_starship_rps1_check() {
    local f=${STARSHIP_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml} c=
    [[ -r $f ]] && c=$(<"$f")
    if [[ $c =~ (^|$'\n')[[:space:]]*right_format[[:space:]]*= ]]; then
        _bashrc_starship_rps1=1
    else
        _bashrc_starship_rps1=
    fi
}

# ── fastfetch on new terminals (toggle: BASHRC_FASTFETCH in bt config) ───────
# Only top-level terminals (not tmux panes, not `bash` typed inside bash).
if [[ $BASHRC_FASTFETCH == 1 && -z ${TMUX-} && $SHLVL -le 2 ]] && command -v fastfetch >/dev/null 2>&1; then
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
_bashrc_starship_rps1_check
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
