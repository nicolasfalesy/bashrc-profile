#!/usr/bin/env bash
# lib/navigation.sh — listing and moving around.

# ll — the listing everything else uses. A function (not an alias) so it works
# inside other functions and in non-interactive contexts.
ll() { command ls -AFlsh --color=auto --group-directories-first "$@"; }

# cd — change directory, then list it (unless it is huge).
# `z`/`zi` (zoxide) route through this too, see lib/prompt.sh.
cd() {
    builtin cd "${@:-$HOME}" || return
    local -a entries
    local saved
    saved=$(shopt -p nullglob dotglob)
    shopt -s nullglob dotglob
    entries=(*)
    eval "$saved"
    if (( ${#entries[@]} <= BASHRC_CD_LS_MAX )); then
        ll
    else
        printf '%s entries — run ll to list\n' "${#entries[@]}"
    fi
}

# up [n] — go up n directories (default 1).
up() {
    local n=${1:-1} p=''
    if [[ $n == -h || $n == --help || ! $n =~ ^[0-9]+$ ]]; then
        echo "Usage: up [levels]   e.g. up 3  →  cd ../../.."; return 0
    fi
    while (( n-- > 0 )); do p+=../; done
    cd "${p:-.}"
}

# mkcd <dir> — create (with parents) and enter it.
mkcd() {
    case ${1-} in
        -h|--help|'')
            echo "Usage: mkcd <directory>   — mkdir -p then cd into it"; return 0 ;;
    esac
    command mkdir -p -- "$1" && cd -- "$1"
}

# take <url|dir> — download+extract an archive into a temp dir and enter it,
# or just mkcd a directory.
take() {
    case ${1-} in
        -h|--help|'')
            cat <<'HELP'
Download and extract an archive, or create and enter a directory.

Usage: take <url|directory>

Examples:
  take https://github.com/user/repo/archive/main.zip
  take my-new-project
HELP
            return 0 ;;
    esac
    if [[ $1 =~ ^https?:// ]]; then
        local tmp name
        name=$(basename "$1"); tmp=$(mktemp -d)
        echo "Downloading $1 …"
        if ! curl -fSL "$1" -o "$tmp/$name"; then
            echo "take: download failed" >&2; command rm -rf "$tmp"; return 1
        fi
        builtin cd "$tmp" || return 1
        extract "$name" && command rm -f "$name"
        local -a dirs=(*/)
        if (( ${#dirs[@]} == 1 )) && [[ -d ${dirs[0]} ]]; then cd "${dirs[0]}"; else ll; fi
    else
        mkcd "$1"
    fi
}

# tre [depth] [dir] — tree with sane ignores (default depth 3).
tre() {
    case ${1-} in
        -h|--help)
            echo "Usage: tre [DEPTH] [DIRECTORY]   — tree, ignoring .git/node_modules/__pycache__/.venv/.cache"
            return 0 ;;
    esac
    hash tree 2>/dev/null || { echo "tre: tree is not installed (run prereqs)" >&2; return 1; }
    local depth=${1:-3} dir=${2:-.}
    [[ -d $dir ]] || { echo "tre: '$dir' is not a directory" >&2; return 1; }
    command tree -CAhF --dirsfirst -L "$depth" -I '.git|node_modules|__pycache__|.venv|.cache|*.pyc' "$dir"
}
