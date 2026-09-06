#!/usr/bin/env bash
# tests/smoke.sh — does the profile still load, and do the core functions still answer?
#
#   bash tests/smoke.sh              every profile
#   bash tests/smoke.sh nas pi       only these
#
# What it checks
#   1. every file parses (bash -n) and, if shellcheck is on PATH, is clean
#   2. sourcing bashrc from a NON-interactive shell prints nothing (the scp/rsync guard)
#   3. for each profile: a real interactive shell starts inside a throw-away HOME
#      (own HISTFILE, no config file, no ~/.bashrc.local, ble.sh off) and the
#      functions below run without error
# Exit status is non-zero on any failure, so this can run in CI or before a commit.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
profiles=("$@"); (( ${#profiles[@]} )) || profiles=(pi nas desktop uw server)
fail=0
red=$'\033[0;31m' green=$'\033[0;32m' dim=$'\033[2m' n=$'\033[0m'
[[ -t 1 ]] || red='' green='' dim='' n=''

echo "── syntax"
for f in "$here"/bashrc "$here"/lib/*.sh "$here"/profiles/*.sh "$here"/install.sh "$here"/tests/smoke.sh; do
    if bash -n "$f"; then :; else echo "${red}FAIL${n} bash -n $f"; fail=1; fi
done
(( fail )) || echo "${green}ok${n}   all files parse"
# Lint with shellcheck: the binary if installed, else through uvx (python's shellcheck-py wheel —
# the only route on TrueNAS where apt is off), else skipped.
sc=()
if command -v shellcheck >/dev/null 2>&1; then sc=(shellcheck)
elif command -v uvx >/dev/null 2>&1; then sc=(uvx --from shellcheck-py shellcheck); fi
if (( ${#sc[@]} )); then
    if (cd "$here" && "${sc[@]}" bashrc lib/*.sh profiles/*.sh install.sh tests/smoke.sh); then
        echo "${green}ok${n}   shellcheck"
    else
        echo "${red}FAIL${n} shellcheck"; fail=1
    fi
else
    echo "${dim}skip shellcheck (neither shellcheck nor uvx installed)${n}"
fi

echo "── non-interactive guard"
out=$(bash -c ". '$here/bashrc'; printf x" 2>&1)
if [[ $out == x ]]; then echo "${green}ok${n}   bashrc is silent in a non-interactive shell"
else echo "${red}FAIL${n} non-interactive shell printed: ${out%x}"; fail=1; fi

# The checks run inside the sandboxed interactive shell. `_t NAME CMD…` prints
# ok/FAIL; the outer loop greps for FAIL.
# shellcheck disable=SC2016  # expanded by the sandbox shell, not here
checks='
_t() { local name=$1; shift; if "$@" >/dev/null 2>&1; then echo "ok   $name"; else echo "FAIL $name"; fi; }
_t "ll"          ll
_t "cd"          cd "$T"
_t "up"          up
_t "mkcd"        mkcd "$T/a/b"
_t "cd back"     cd "$T"
_t "extract -h"  extract -h
_t "bak"         bak "$T/f"
_t "bak -h"      bak -h
_t "size"        size "$T"
_t "path -c"     path -c
_t "sys"         sys
_t "psg"         psg bash
_t "port -h"     port -h
_t "topp"        topp 1
_t "t -h"        t -h
_t "weather -h"  weather -h
_t "rcon -h"     rcon -h
_t "ru lazy"     ru -h
_t "rut -h"      rut -h
_t "bt -l"       bt -l
_t "tre"         tre 1 "$T"
_t "reload"      source "$HOME/.bashrc"
case $BASHRC_PROFILE in
    pi)      _t "pi: temp"   declare -F temp;  _t "pi: cloud" declare -F cloud ;;
    nas)     _t "nas: dsv"   declare -F dsv;   _t "nas: zh"   alias zh ;;
    desktop) _t "desktop: cpy" declare -F cpy; _t "desktop: vpn" declare -F vpn; _t "desktop: note" declare -F note ;;
    uw)      _t "uw: rm -iv" bash -c "[[ \"$(alias rm)\" == *-iv* ]]" ;;
esac
exit
'

for p in "${profiles[@]}"; do
    echo "── profile $p"
    tmp=$(mktemp -d)
    mkdir -p "$tmp/.config" "$tmp/.cache"
    ln -s "$here/bashrc" "$tmp/.bashrc"
    ln -s "$here/themes/aurora.toml" "$tmp/.config/starship.toml"
    printf 'hello\n' > "$tmp/f"
    out=$(HOME=$tmp XDG_CONFIG_HOME=$tmp/.config XDG_CACHE_HOME=$tmp/.cache HISTFILE=$tmp/hist T=$tmp \
          BASHRC_PROFILE=$p BASHRC_BLESH=0 BASHRC_PROFILE_DIR=$here \
          bash --rcfile "$here/bashrc" -i <<< "$checks" 2>&1 </dev/stdin)
    # bash echoes prompts and commands when stdin is not a terminal; strip the
    # colour codes once, then keep only our ok/FAIL lines and anything that
    # smells like an error.
    # (sed, not ${out//…}: an extglob substitution over this much output takes minutes)
    # shellcheck disable=SC2001
    out=$(sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' <<< "$out")
    while IFS= read -r line; do
        case $line in
            ok\ *)   echo "${green}ok${n}   ${line#ok }" ;;
            FAIL\ *) echo "${red}FAIL${n} ${line#FAIL }"; fail=1 ;;
            *"command not found"*|*"syntax error"*|*"unbound variable"*|*"No such file"*)
                     echo "${red}!!${n}   $line"; fail=1 ;;
        esac
    done <<< "$out"
    rm -rf "$tmp"
done

echo
if (( fail )); then echo "${red}smoke test FAILED${n}"; exit 1; else echo "${green}smoke test passed${n}"; fi
