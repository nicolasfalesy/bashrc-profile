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
profiles=("$@"); (( ${#profiles[@]} )) || profiles=(pi nas desktop omarchy uw server)
fail=0
red=$'\033[0;31m' green=$'\033[0;32m' dim=$'\033[2m' n=$'\033[0m'
[[ -t 1 ]] || red='' green='' dim='' n=''

echo "── syntax"
for f in "$here"/bashrc "$here"/lib/*.sh "$here"/profiles/*.sh "$here"/bin/* "$here"/hooks/* \
         "$here"/install.sh "$here"/tests/smoke.sh "$here"/tests/claude-account.sh "$here"/tests/dev.sh "$here"/.githooks/pre-push; do
    if bash -n "$f"; then :; else echo "${red}FAIL${n} bash -n $f"; fail=1; fi
done
(( fail )) || echo "${green}ok${n}   all files parse"
# Lint with shellcheck: the binary if installed, else through uvx (python's shellcheck-py wheel —
# the only route on TrueNAS where apt is off), else skipped.
sc=()
if command -v shellcheck >/dev/null 2>&1; then sc=(shellcheck)
elif command -v uvx >/dev/null 2>&1; then sc=(uvx --from shellcheck-py shellcheck); fi
if (( ${#sc[@]} )); then
    if (cd "$here" && "${sc[@]}" bashrc lib/*.sh profiles/*.sh bin/* hooks/* .githooks/pre-push install.sh tests/smoke.sh tests/claude-account.sh tests/dev.sh); then
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
_t "cpy -h"      cpy -h
_t "pst -h"      pst -h
_clip_rt() { local BASHRC_CLIP_BACKEND=file; cpy "smoke-clip" && [[ $(pst) == smoke-clip ]]; }
_t "cpy/pst"     _clip_rt
# a paste that never arrives must fail fast and leave the clipboard untouched
_clip_np() { local BASHRC_CLIP_BACKEND=file BASHRC_CLIP_PASTE_WAIT=1
             cpy "keep-me"; cpy -p; (( $? == 1 )) && [[ $(pst) == keep-me ]]; }
_t "cpy -p safe" _clip_np
# a fresh cpy -p capture must beat the terminal clipboard: 2026-09-23 pst returned the
# command copied on the laptop AFTER the paste instead of the pasted token. The stubs
# stand in for a terminal that can be read (the sandbox has none).
_clip_fresh() ( BASHRC_CLIP_BACKEND=file
                _clip_slurp() { printf "caught-token"; }; _clip_read_raw() { printf "laptop-clip"; }
                cpy -p && [[ $(pst) == caught-token ]] && [[ $(pst -l) == caught-token ]] )
_t "cpy -p wins" _clip_fresh
# ...only while fresh, and a plain cpy ends it: then the terminal is read again, as before
_clip_ages() ( BASHRC_CLIP_BACKEND=file
               _clip_slurp() { printf "caught-token"; }; _clip_read_raw() { printf "laptop-clip"; }
               cpy -p && [[ $(BASHRC_CLIP_PASTE_FRESH=0 pst) == laptop-clip ]] &&
               cpy -p && cpy "plain" && [[ $(pst) == laptop-clip ]] && [[ $(pst -l) == plain ]] )
_t "cpy -p ages" _clip_ages
_t "sys"         sys
_t "psg"         psg bash
_t "port -h"     port -h
_t "topp"        topp 1
_t "t -h"        t -h
_t "tkill -h"    tkill -h
# tkill on a private tmux server (own TMUX_TMPDIR, TMUX unset): never touches a real session
_tkill_rt() ( unset TMUX; export TMUX_TMPDIR="$T/tmux"; mkdir -p "$TMUX_TMPDIR"
              command -v tmux >/dev/null || exit 0
              tmux new-session -d -s keepme && tmux new-session -d -s dropme &&
              tkill -y keepme && tmux has-session -t =keepme && ! tmux has-session -t =dropme; rc=$?
              tmux kill-server 2>/dev/null; exit $rc )
_t "tkill keeps" _tkill_rt
_t "weather -h"  weather -h
_t "rcon -h"     rcon -h
_t "ru lazy"     ru -h
_t "rut -h"      rut -h
_t "bt -l"       bt -l
_t "tre"         tre 1 "$T"
_t "reload"      source "$HOME/.bashrc"
case $BASHRC_PROFILE in
    pi)      _t "pi: temp"   declare -F temp;  _t "pi: cloud" declare -F cloud ;;
    nas)     _t "nas: dsv"   declare -F dsv;   _t "nas: zh"   alias zh
             _t "nas: tmake -h" tmake -h
             # tmake on a private tmux server with a stand-in for claude: makes the missing
             # sessions only, and leaves the running one alone
             _tmake_rt() ( unset TMUX; export TMUX_TMPDIR="$T/tmux-tmake"; mkdir -p "$TMUX_TMPDIR"
                         command -v tmux >/dev/null || exit 0
                         export BASHRC_TMAKE_RUN="sleep 30"
                         tmake 2 >/dev/null && out=$(tmake 3) && [[ $out == *"Made 1: claude3"* ]] &&
                         [[ $(tmux list-sessions -F "#{session_name}" | sort | tr "\n" " ") == "claude1 claude2 claude3 " ]] &&
                         ! tmake 17 2>/dev/null && ! tmake x 2>/dev/null; rc=$?
                         tmux kill-server 2>/dev/null; exit $rc )
             _t "nas: tmake makes" _tmake_rt
             # pw against a stand-in for sudo (never the real /root): the password reaches
             # tee on stdin only, a 10-minute root timer is set, an empty one writes nothing,
             # and -c stops the timer before shredding
             _pw_nas() ( log="$T/sudo"; : >"$log"; : >"$T/pwf"
                         sudo() { echo "$*" >>"$log"; case $1 in tee) cat >"$T/pwf" ;; stat) echo "600 root" ;; esac; }
                         pw <<< "s3cret pass" >/dev/null && [[ $(<"$T/pwf") == "s3cret pass" ]] &&
                         grep -q "^systemd-run .*--unit=bw-master-expire --on-active=600 " "$log" &&
                         ! grep -q s3cret "$log" && n=$(wc -l <"$log") &&
                         ! pw <<< "" 2>/dev/null && [[ $(wc -l <"$log") == "$n" ]] &&
                         pw -c >/dev/null && tail -2 "$log" | head -1 | grep -qx "systemctl stop bw-master-expire.timer" && ! pw -x 2>/dev/null )
             _t "nas: pw timer" _pw_nas ;;
    desktop) _t "desktop: vpn" declare -F vpn; _t "desktop: note" declare -F note ;;
    omarchy) _t "omarchy: pw -h" pw -h
             # pw against stand-ins for keyctl and secret-tool (never the real keyrings):
             # the password reaches keyctl on stdin only, with the name, user read and
             # the 10-minute expiry; an empty one writes nothing; -c revokes it
             _pw_rt() ( kc="$T/kc"; : >"$kc"; : >"$T/kv"
                        keyctl() { echo "$*" >>"$kc"
                                   case $1 in padd) cat >"$T/kv"; echo 42 ;; search) [[ -s $T/kv ]] && echo 42 ;; esac; }
                        pw <<< "s3cret pass" && [[ $(<"$T/kv") == "s3cret pass" ]] &&
                        grep -qx "padd user claude-bw-master @u" "$kc" && grep -qx "setperm 42 0x3f3f0000" "$kc" &&
                        grep -qx "timeout 42 600" "$kc" && ! grep -q s3cret "$kc" &&
                        ! pw <<< "" && [[ $(grep -c ^padd "$kc") == 1 ]] &&
                        pw -c && grep -qx "revoke 42" "$kc" && ! pw -x )
             _t "omarchy: pw keyring" _pw_rt
             # pw --setup: both halves reach secret-tool on stdin; a client_id that is not
             # "user.…" stores nothing
             _pw_setup() ( st="$T/st"; : >"$st"
                           secret-tool() { echo "$* = $(cat)" >>"$st"; }
                           printf "user.abc\nsec123\n" | pw --setup &&
                           grep -qx "store --label=Claude bw API key (client_id) service claude-bw key client_id = user.abc" "$st" &&
                           grep -qx "store --label=Claude bw API key (client_secret) service claude-bw key client_secret = sec123" "$st" &&
                           : >"$st" && ! printf "sec123\nuser.abc\n" | pw --setup && [[ ! -s $st ]] )
             _t "omarchy: pw --setup" _pw_setup ;;
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

# claude-account has its own sandboxed suite (fake logins, stub claude and sudo; never Anthropic).
echo "── claude-account"
if command -v jq >/dev/null 2>&1; then
    while IFS= read -r line; do
        case $line in
            ok\ *)   echo "${green}ok${n}   ${line#ok }" ;;
            FAIL\ *) echo "${red}FAIL${n} ${line#FAIL }"; fail=1 ;;
        esac
    done < <(bash "$here/tests/claude-account.sh" 2>&1 || echo "FAIL tests/claude-account.sh exited non-zero")
else
    echo "${dim}skip claude-account (jq not installed)${n}"
fi

# The dev commands build tiny real programs in a temp folder (C needs a compiler; Rust checks skip without cargo).
echo "── dev commands"
if command -v cc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1; then
    while IFS= read -r line; do
        case $line in
            ok\ *)   echo "${green}ok${n}   ${line#ok }" ;;
            skip\ *) echo "${dim}skip ${line#skip }${n}" ;;
            FAIL\ *) echo "${red}FAIL${n} ${line#FAIL }"; fail=1 ;;
        esac
    done < <(bash "$here/tests/dev.sh" 2>&1 || echo "FAIL tests/dev.sh exited non-zero")
else
    echo "${dim}skip dev commands (no C compiler)${n}"
fi

# bup must show incoming commits and pull only on a yes. update_repo and its helpers are lifted out of
# install.sh and run against a throw-away origin; `ask` is stubbed, so no terminal is needed.
echo "── bup asks before pulling"
bup_t=$(mktemp -d)
# shellcheck disable=SC2016  # expanded by the inner shell, not here
bup_out=$(cd "$bup_t" && bash -c '
    g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
    g init -q --bare o.git && g clone -q o.git a 2>/dev/null && g -C a commit -q --allow-empty -m one && g -C a push -q origin HEAD 2>/dev/null
    g clone -q o.git b && g -C a commit -q --allow-empty -m two-incoming && g -C a push -q origin HEAD 2>/dev/null
    source <(sed -n "/^info()/,/^have()/p; /^run()/,/^}/p; /^update_repo()/,/^}/p" "$1")
    DRY=0 REPO_FROM_CHECKOUT=1 REPO_DIR=$PWD/b
    ask() { return 1; }; o=$(update_repo 2>&1)
    [[ $o == *two-incoming* && $o == *"pull skipped"* && $(git -C b log -1 --format=%s) == one ]] && echo "ok   a no keeps the old commit and lists the new one"
    ask() { return 0; }; update_repo >/dev/null 2>&1
    [[ $(git -C b log -1 --format=%s) == two-incoming ]] && echo "ok   a yes pulls"
    [[ $(update_repo 2>&1) == *"already up to date"* ]] && echo "ok   nothing incoming: no question"
    # The real ask with no terminal (setsid: no controlling tty, like ssh without -t) must assume yes, not die.
    g -C a commit -q --allow-empty -m three && g -C a push -q origin HEAD 2>/dev/null
    source <(sed -n "/^ask()/,/^}/p" "$1"); YES=0
    o=$(setsid -w bash -uc "$(declare -f info ok warn run ask update_repo); B= G= Y= N= DRY=0 YES=0 REPO_FROM_CHECKOUT=1 REPO_DIR=$PWD/b; update_repo" </dev/null 2>&1)
    [[ $o == *"assuming yes"* && $(git -C b log -1 --format=%s) == three ]] && echo "ok   no terminal: assumes yes and pulls"
' _ "$here/install.sh" 2>&1)
rm -rf "${bup_t:?}"
for want in "a no keeps the old commit and lists the new one" "a yes pulls" "nothing incoming: no question" "no terminal: assumes yes and pulls"; do
    if [[ $bup_out == *"ok   $want"* ]]; then echo "${green}ok${n}   $want"; else echo "${red}FAIL${n} bup: $want"; fail=1; fi
done

echo
if (( fail )); then echo "${red}smoke test FAILED${n}"; exit 1; else echo "${green}smoke test passed${n}"; fi
