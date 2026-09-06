#!/usr/bin/env bash
# lib/files.sh — working with files: extract, ftext, size, bak, diff2, path.

# extract <archive>... — unpack anything by extension.
extract() {
    case ${1-} in
        -h|--help|'')
            echo "Usage: extract <archive>...  📦"
            echo "  tar (gz/bz2/xz/zst), tgz, tbz2, txz, zip, 7z, rar, gz, bz2, xz, zst, Z, deb"
            return 0 ;;
    esac
    local f rc=0
    for f in "$@"; do
        if [[ ! -f $f ]]; then echo "extract: '$f' is not a file ❌" >&2; rc=1; continue; fi
        case $f in
            *.tar|*.tar.*|*.tgz|*.tbz2|*.txz|*.tzst) tar xf "$f" ;;      # GNU tar autodetects compression
            *.zip)   unzip -q "$f" ;;
            *.7z)    7z x "$f" ;;
            *.rar)   unrar x "$f" 2>/dev/null || unrar-free -x "$f" ;;
            *.gz)    gunzip "$f" ;;
            *.bz2)   bunzip2 "$f" ;;
            *.xz)    unxz "$f" ;;
            *.zst)   unzstd "$f" ;;
            *.Z)     uncompress "$f" ;;
            *.deb)   dpkg-deb -x "$f" "${f%.deb}" ;;
            *)       echo "extract: don't know how to extract '$f' ❌" >&2; rc=1; continue ;;
        esac || { echo "extract: failed on '$f' ❌" >&2; rc=1; }
    done
    return $rc
}

# ftext <pattern> — search text in all files under the current directory.
ftext() {
    case ${1-} in
        -h|--help|'')
            echo "Usage: ftext <pattern>   — case-insensitive recursive search, paged (ripgrep if available)"
            return 0 ;;
    esac
    if hash rg 2>/dev/null; then
        rg -in --color=always --no-heading -- "$1" . | less
    else
        command grep -iIHrn --color=always -- "$1" . | less
    fi
}

# size [--size K|M|G|T] [dir...] — total size of directories, with a spinner.
_size_fmt() {   # <bytes> [unit]
    local b=$1 u=${2:-}
    if [[ -z $u ]]; then
        if   (( b >= 1099511627776 )); then u=T
        elif (( b >= 1073741824 ));    then u=G
        elif (( b >= 1048576 ));       then u=M
        elif (( b >= 1024 ));          then u=K
        else printf '%d B' "$b"; return; fi
    fi
    case $u in
        K) awk -v b="$b" 'BEGIN{printf "%.2f KiB", b/1024}' ;;
        M) awk -v b="$b" 'BEGIN{printf "%.2f MiB", b/1048576}' ;;
        G) awk -v b="$b" 'BEGIN{printf "%.2f GiB", b/1073741824}' ;;
        T) awk -v b="$b" 'BEGIN{printf "%.2f TiB", b/1099511627776}' ;;
    esac
}
size() {
    local unit='' targets=() t
    while (( $# )); do
        case $1 in
            -h|--help)
                cat <<'HELP'
Show the size of one or more directories (default: current directory).

Usage: size [--size K|M|G|T] [DIRECTORY...]

Examples:
  size                  current directory, auto units
  size /var/log /tmp    several directories + total
  size --size G /var    force GiB
HELP
                return 0 ;;
            --size)
                shift; unit=${1^^}
                [[ $unit =~ ^[KMGT]$ ]] || { echo "size: --size needs K, M, G or T" >&2; return 1; } ;;
            *) targets+=("$1") ;;
        esac
        shift
    done
    (( ${#targets[@]} )) || targets=(.)

    local total=0 bytes tmp pid i spin='|/-\'
    for t in "${targets[@]}"; do
        [[ -d $t ]] || { echo "size: '$t' is not a directory" >&2; continue; }
        tmp=$(mktemp)
        { command du -sb -- "$t" > "$tmp" 2>/dev/null & } 2>/dev/null
        pid=$!; i=0
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r  [%s] scanning %s…' "${spin:i++%4:1}" "$t"; sleep 0.1
        done
        printf '\r\033[K'
        wait "$pid" 2>/dev/null
        read -r bytes _ < "$tmp"; command rm -f "$tmp"
        [[ -n $bytes ]] || { echo "size: couldn't read '$t'" >&2; continue; }
        (( total += bytes ))
        printf '%s  %s\n' "$(_size_fmt "$bytes" "$unit")" "$t"
    done
    if (( ${#targets[@]} > 1 )); then
        echo "---------------------"
        printf '%s  total\n' "$(_size_fmt "$total" "$unit")"
    fi
}
_size_completions() {
    local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]}
    if [[ $prev == --size ]]; then COMPREPLY=($(compgen -W 'K M G T' -- "$cur"))
    elif [[ $cur == -* ]]; then COMPREPLY=($(compgen -W '-h --help --size' -- "$cur"))
    else COMPREPLY=($(compgen -d -- "$cur")); fi
}
complete -F _size_completions size

# bak <file>... | bak -r <file.bak.TIMESTAMP> — timestamped backups and restore.
bak() {
    case ${1-} in
        -h|--help|'')
            cat <<'HELP'
Create a timestamped backup copy of one or more files, or restore one.

Usage: bak <file>...
       bak -r <file.bak.YYYYMMDD-HHMMSS>

Examples:
  bak config.yml                       → config.yml.bak.20260905-141500
  bak -r config.yml.bak.20260905-141500
HELP
            return 0 ;;
        -r|--restore)
            local b=${2-} orig
            [[ -n $b ]] || { echo "bak: give the .bak file to restore" >&2; return 1; }
            orig=${b%.bak.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]}
            [[ $orig != "$b" ]] || { echo "bak: '$b' doesn't look like a .bak.TIMESTAMP file" >&2; return 1; }
            command cp -i -- "$b" "$orig" && echo "Restored: $b → $orig"
            return ;;
    esac
    local f ts n=0
    ts=$(date +%Y%m%d-%H%M%S)
    for f in "$@"; do
        [[ -f $f ]] || { echo "bak: '$f' not found" >&2; continue; }
        command cp -- "$f" "$f.bak.$ts" && echo "Backed up: $f → $f.bak.$ts" && (( n++ ))
    done
    (( $# > 1 )) && echo "--- $n file(s) backed up ---"
    return 0
}
_bak_completions() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    if [[ $cur == -* ]]; then COMPREPLY=($(compgen -W '-h --help -r --restore' -- "$cur"))
    else COMPREPLY=($(compgen -f -- "$cur")); fi
}
complete -F _bak_completions bak

# diff2 <a> <b> — side-by-side coloured diff in a pager.
diff2() {
    case ${1-} in -h|--help) echo "Usage: diff2 <file1> <file2>"; return 0 ;; esac
    (( $# == 2 )) || { echo "diff2: exactly two files required" >&2; return 1; }
    [[ -f $1 ]] || { echo "diff2: '$1' not found" >&2; return 1; }
    [[ -f $2 ]] || { echo "diff2: '$2' not found" >&2; return 1; }
    command diff --color=always --side-by-side -- "$1" "$2" | less
}
complete -f diff2

# path [pattern|-c] — show PATH one entry per line.
path() {
    case ${1-} in
        -h|--help) echo "Usage: path [pattern]   |   path -c (count)"; return 0 ;;
        -c|--count) tr ':' '\n' <<< "$PATH" | wc -l ;;
        '') tr ':' '\n' <<< "$PATH" | nl ;;
        *)  tr ':' '\n' <<< "$PATH" | command grep -i --color=always -- "$1" | nl ;;
    esac
}
