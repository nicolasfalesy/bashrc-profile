#!/usr/bin/env bash
# lib/navigation.sh — listing and moving around.
# shellcheck disable=SC2119,SC2120  # ll is called with and without arguments on purpose

# ll — the listing everything else uses. A function (not an alias) so it works
# inside other functions regardless of when they were parsed.
ll() { command ls -AFlsh --color=auto --group-directories-first "$@"; }

# cd — change directory, then list it (unless it is huge).
# `z`/`zi` (zoxide) route through this too, see lib/prompt.sh.
# Counting with a glob instead of `ls | wc -l` keeps this fork-free; nullglob/dotglob
# are restored afterwards so the caller's settings survive.
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
    cd "${p:-.}" || return
}

# mkcd <dir> — create (with parents) and enter it.
mkcd() {
    case ${1-} in
        -h|--help|'')
            echo "Usage: mkcd <directory>   — mkdir -p then cd into it"; return 0 ;;
    esac
    command mkdir -p -- "$1" && cd -- "$1" || return
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
        if (( ${#dirs[@]} == 1 )) && [[ -d ${dirs[0]} ]]; then cd "${dirs[0]}" || return; else ll; fi
    else
        mkcd "$1"
    fi
}

# tre [depth] [dir] — tree with sane ignores (default depth 3).
# Falls back to find(1) where `tree` cannot be installed (TrueNAS, UW servers).
tre() {
    case ${1-} in
        -h|--help)
            echo "Usage: tre [DEPTH] [DIRECTORY]   — tree, ignoring .git/node_modules/__pycache__/.venv/.cache"
            return 0 ;;
    esac
    local depth=${1:-3} dir=${2:-.}
    [[ $depth =~ ^[0-9]+$ ]] || { echo "tre: depth must be a number" >&2; return 1; }
    [[ -d $dir ]] || { echo "tre: '$dir' is not a directory" >&2; return 1; }
    if command -v tree >/dev/null 2>&1; then
        command tree -CAhF --dirsfirst -L "$depth" -I '.git|node_modules|__pycache__|.venv|.cache|*.pyc' "$dir"
    else
        # poor man's tree: indent by depth, directories get a trailing /
        command find "$dir" -mindepth 1 -maxdepth "$depth" \
            \( -name .git -o -name node_modules -o -name __pycache__ -o -name .venv -o -name .cache \) -prune -o \
            -print | sort | while IFS= read -r p; do
                local rel=${p#"$dir"/} pad=''
                local d=${rel//[^\/]/}; pad=${d//\//    }
                if [[ -d $p ]]; then printf '%s\033[1;34m%s/\033[0m\n' "$pad" "${rel##*/}"
                else printf '%s%s\n' "$pad" "${rel##*/}"; fi
            done
    fi
}
