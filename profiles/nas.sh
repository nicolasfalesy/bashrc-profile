#!/usr/bin/env bash
# profiles/nas.sh — TrueNAS SCALE.
#
# TrueNAS SCALE is Debian with a read-only root filesystem and apt disabled.
# Nothing in this file needs a system package: everything the profile uses on
# the NAS lives in ~/.local (starship, fzf, ble.sh — see install.sh --profile nas).
# Package aliases (ni/nu/…) are skipped automatically because lib/aliases.sh
# only defines them when apt is executable.

export ZPOOL="${ZPOOL:-tank}"          # override in ~/.bashrc.local
unalias apt ni np ns nu nclean 2>/dev/null   # no package manager on TrueNAS

# nvim unpacked by hand into ~/nvim-linux-x86_64 (no package manager on SCALE):
# put it on PATH and point it at its runtime files.
if [[ -d $HOME/nvim-linux-x86_64/bin ]]; then
    _path_prepend "$HOME/nvim-linux-x86_64/bin"
    export VIMRUNTIME="$HOME/nvim-linux-x86_64/share/nvim/runtime"
fi
hash nvidia-smi 2>/dev/null && alias wn='watch -n 0.1 nvidia-smi'   # live GPU monitor

# ── ZFS shortcuts ────────────────────────────────────────────────────────────
alias zs='sudo zpool status -v'                                      # full status
alias zh='sudo zpool status -x'                                      # one-line health
alias zl='zfs list -o name,used,avail,refer,mountpoint'              # datasets
alias zsnap='zfs list -t snapshot -o name,used,creation -s creation' # snapshots
alias zio='zpool iostat -v 2'                                        # live I/O
alias smart='sudo smartctl -a'                                       # smart /dev/sda

# Extra lines for `sys`.
_sys_extra() {
    hash zpool 2>/dev/null || return 0
    local line
    while read -r line; do
        [[ -n $line ]] && printf '\033[0;32mZFS:\033[0m      %s\n' "$line"
    done < <(zpool list -H -o name,size,alloc,free,cap,health 2>/dev/null | awk '{printf "%s %s used %s/%s (%s) %s\n",$1,$6,$3,$2,$5,$4}')
}

# dsv [-n] [pattern] — delete files that `zpool status -v` lists as damaged,
# then clear the pool errors. Default pattern: /mnt/$ZPOOL/
dsv() {
    local dry=0 pattern='' arg
    for arg in "$@"; do
        case $arg in
            -h|--help)
                cat <<'HELP'
Delete files reported as permanently damaged by `zpool status -v $ZPOOL`.

Usage: dsv [-n] [PATTERN]
  -n         dry run — list, don't delete
  PATTERN    only paths matching this (default: /mnt/$ZPOOL/)

Files are removed with sudo (they usually belong to other users/services).
After deleting, runs `zpool clear $ZPOOL`.
HELP
                return 0 ;;
            -n) dry=1 ;;
            -*) echo "dsv: unknown option '$arg'" >&2; return 1 ;;
            *)  [[ -z $pattern ]] || { echo "dsv: one pattern only" >&2; return 1; }; pattern=$arg ;;
        esac
    done
    pattern=${pattern:-/mnt/$ZPOOL/}
    hash zpool 2>/dev/null || { echo "dsv: zpool not found" >&2; return 1; }

    local -a files=()
    mapfile -t files < <(sudo zpool status -v "$ZPOOL" 2>/dev/null | command grep -- "$pattern" | sed 's/^ *//')
    if (( ${#files[@]} == 0 )); then echo "dsv: no damaged files matching '$pattern'"; return 0; fi

    printf '%s file(s) matching %s:\n' "${#files[@]}" "$pattern"
    printf '  %s\n' "${files[@]}"
    (( dry )) && { echo "[dry run] nothing deleted"; return 0; }

    local confirm; read -rp "Permanently delete these ${#files[@]} file(s)? [y/N] " confirm
    [[ $confirm =~ ^[Yy]$ ]] || { echo "Aborted."; return 0; }

    local f removed=0 failed=0
    for f in "${files[@]}"; do
        if [[ -e $f ]] && sudo rm -v -- "$f"; then (( removed++ )); else echo "dsv: skipped $f" >&2; (( failed++ )); fi
    done
    printf '\nSummary: %d removed, %d failed/skipped\n' "$removed" "$failed"
    (( removed )) && sudo zpool clear "$ZPOOL" && echo "Pool errors cleared."
    return 0
}
_dsv_completions() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    if [[ $cur == -* ]]; then COMPREPLY=($(compgen -W '-h --help -n' -- "$cur"))
    else COMPREPLY=($(compgen -d -- "${cur:-/mnt/$ZPOOL/}")); fi
}
complete -F _dsv_completions dsv
