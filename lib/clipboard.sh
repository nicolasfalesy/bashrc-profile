#!/usr/bin/env bash
# lib/clipboard.sh — cpy / pst on every machine, including over SSH.
#
#   cat notes.txt | cpy        cpy "some text"        cpy < notes.txt
#   pst                        pst > notes.txt        cpy -c   (clear)
#   cpy -p                     then Ctrl+Shift+V — catch a paste, for terminals
#                              that refuse to be read (Windows Terminal, WezTerm)
#
# Backends, tried in this order (force one with BASHRC_CLIP_BACKEND):
#   wayland   wl-copy / wl-paste        when $WAYLAND_DISPLAY is set
#   x11       xclip, else xsel          when $DISPLAY is set (incl. ssh -X)
#   macos     pbcopy / pbpaste
#   osc52     the terminal itself       always available — this is the SSH case
#
# Why OSC 52: over SSH there is no clipboard on this box, but the terminal at the
# other end of the connection has one. OSC 52 is an escape sequence that hands it
# base64 and says "put this on the system clipboard", so `cat x | cpy` on the NAS
# or the Pi lands in the laptop's clipboard. Every modern terminal (Alacritty,
# kitty, WezTerm, iTerm2, Windows Terminal, foot, xterm) implements the write.
#
# Reading it back is a different story: a remote host being able to *read* your
# clipboard is a security hole, so terminals ship that half disabled. pst tries
# the read anyway, then falls back to the spool file that cpy always writes — so
# pst at minimum always returns whatever cpy last copied on this host. To get a
# true remote paste, enable the read in the terminal:
#   Alacritty   [terminal] osc52 = "CopyPaste"        in alacritty.toml
#   kitty       clipboard_control write-clipboard write-primary read-clipboard
#   iTerm2      Settings → General → Selection → "Applications may access clipboard"
#   xterm       XTerm*disallowedWindowOps: 20,21,SetXprop
#
# Env:
#   BASHRC_CLIP_BACKEND   auto (default) | wayland | x11 | macos | osc52 | file
#   BASHRC_CLIP_FILE      spool file    (default $BASHRC_CACHE_DIR/clipboard, mode 0600)
#   BASHRC_CLIP_MAX       largest base64 payload pushed through OSC 52, in bytes
#                         (default 74994 — xterm's cap; 0 = no limit)
#   BASHRC_CLIP_TIMEOUT   seconds to wait for the terminal's OSC 52 reply (default 0.5)
#   BASHRC_CLIP_PASTE_WAIT  seconds `cpy -p` waits for a paste to start (default 15)
#   BASHRC_CLIP_PASTE_IDLE  tenths of a second of silence that end a `cpy -p` capture (default 2)
#   BASHRC_CLIP_PASTE_FRESH seconds a `cpy -p` capture beats the terminal's clipboard in pst (default 600)

# The spool: what cpy last copied on THIS host. Also the only thing pst can
# return when the terminal refuses to be read.
_clip_file() {
    printf '%s' "${BASHRC_CLIP_FILE:-${BASHRC_CACHE_DIR:-$HOME/.cache/bashrc-profile}/clipboard}"
}

# Beside the spool: the epoch of the last `cpy -p` capture. pst prefers the spool
# over the terminal's clipboard while this is fresh. Why: on a terminal that CAN be
# read (Alacritty with osc52 = "CopyPaste"), the obvious flow is "cpy -p, paste the
# secret, then copy the next command from the instructions and run it" — and that
# copy replaces the laptop's clipboard, so pst used to return the COMMAND instead of
# what cpy -p had just caught (2026-09-23: `pst > ~/.cf-workers-token` wrote
# "pst > ~/.cf-workers-token && chmod 600 ~/.cf-workers-token" into the token file).
_clip_mark() { printf '%s.paste' "$(_clip_file)"; }

# Which backend is live right now? Resolved per call, not at startup: the same
# shell can be local one minute and inside tmux over SSH the next, and this keeps
# startup at zero cost.
_clip_backend() {
    case ${BASHRC_CLIP_BACKEND:-auto} in
        auto) ;;
        *)    printf '%s' "$BASHRC_CLIP_BACKEND"; return ;;
    esac
    if   [[ -n ${WAYLAND_DISPLAY-} ]] && command -v wl-copy >/dev/null 2>&1; then printf wayland
    elif [[ -n ${DISPLAY-} ]] && { command -v xclip >/dev/null 2>&1 || command -v xsel >/dev/null 2>&1; }; then printf x11
    elif command -v pbcopy >/dev/null 2>&1; then printf macos
    else printf osc52
    fi
}

# macOS decodes with -D, GNU coreutils with -d.
_clip_b64d_flag() { if base64 -d </dev/null >/dev/null 2>&1; then printf -- -d; else printf -- -D; fi; }

# Hand <base64> to the terminal emulator.
_clip_osc52_write() {
    local b64=$1 seq max=${BASHRC_CLIP_MAX-74994}
    if ! { true >/dev/tty; } 2>/dev/null; then
        echo "cpy: no terminal to send the clipboard escape to (saved locally, pst still works) ⚠️" >&2
        return 1
    fi
    if (( max > 0 && ${#b64} > max )); then
        printf 'cpy: %d base64 bytes is over BASHRC_CLIP_MAX (%d) — saved locally, terminal clipboard untouched ⚠️\n' \
               "${#b64}" "$max" >&2
        return 1
    fi
    seq=$'\033]52;c;'$b64$'\a'
    # tmux and screen swallow escape sequences from the programs they host, so the
    # whole thing goes inside a DCS passthrough to reach the real terminal. tmux
    # additionally wants every ESC in the payload doubled.
    if [[ -n ${TMUX-} ]]; then
        seq=$'\033Ptmux;'${seq//$'\033'/$'\033\033'}$'\033\\'
    elif [[ ${TERM-} == screen* ]]; then
        seq=$'\033P'$seq$'\033\\'
    fi
    printf '%s' "$seq" > /dev/tty
}

# Ask the terminal for its clipboard. Subshell + EXIT trap on purpose: raw mode
# left on would wedge the shell, so it is restored on every exit path.
_clip_osc52_read() (
    local old b64 to=${BASHRC_CLIP_TIMEOUT:-0.5}
    exec 3<>/dev/tty 2>/dev/null || return 1
    old=$(stty -g <&3 2>/dev/null) || return 1
    # Drain anything still in flight first: a late reply would otherwise be typed
    # into the next prompt.
    # shellcheck disable=SC2064  # $old must expand now, while the subshell still has it
    trap "while IFS= read -rs -t 0.05 -n 64 _ <&3; do :; done; stty $old <&3 2>/dev/null" EXIT
    stty raw -echo <&3 2>/dev/null || return 1
    # shellcheck disable=SC1003  # \033\\ is the ST terminator, not an escaped quote
    printf '\033]52;c;?\033\\' >&3
    # Reply is  ESC ] 52 ; c ; <base64> ST|BEL  — read it field by field.
    IFS= read -rs -t "$to" -d ';' _ <&3 || return 1     # ESC ] 52 ;
    IFS= read -rs -t "$to" -d ';' _ <&3 || return 1     # selection ;
    IFS= read -rs -t "$to" -d $'\033' b64 <&3 || b64=${b64%$'\a'}   # payload, ST- or BEL-terminated
    [[ -n $b64 ]] || return 1
    printf '%s' "$b64" | base64 "$(_clip_b64d_flag)" 2>/dev/null
)

# Read a paste straight off the terminal. This is the answer for terminals that
# implement the OSC 52 write but refuse the read — Windows Terminal, WezTerm —
# where pst can never fetch the laptop's clipboard: instead of asking for it, we
# let the terminal type it at us.
#
# Two things here are not obvious and both were found the hard way:
#   • bash's own `read` builtin CANNOT be used. Reading the same raw terminal,
#     `dd` sees "A \r \n B" and `read -rs -N` sees "A \n \n" — it rewrites CR as
#     LF. A Windows clipboard arrives as CRLF, so every line came out doubled.
#   • the waiting is left to the terminal driver rather than a bash timeout:
#     `min 0 time N` makes a read return after N tenths of a second of silence,
#     which is exactly "the paste has stopped", and a 0-byte read is EOF to cat.
# Output is the raw bytes on stdout; the caller decides whether anything came.
_clip_slurp() (
    local old first=${BASHRC_CLIP_PASTE_WAIT:-15} idle=${BASHRC_CLIP_PASTE_IDLE:-2} t
    t=$(( first * 10 ))                      # termios counts tenths, and caps at 255
    (( t > 255 )) && t=255; (( t < 1 )) && t=1
    exec 3<>/dev/tty 2>/dev/null || return 1
    old=$(stty -g <&3 2>/dev/null) || return 1
    # shellcheck disable=SC2064  # $old must expand now, while the subshell still has it
    trap "stty $old <&3 2>/dev/null" EXIT
    stty raw -echo min 0 time "$t" <&3 2>/dev/null || return 1
    dd bs=4096 count=1 <&3 2>/dev/null       # the first chunk, however long he takes
    stty min 0 time "$idle" <&3 2>/dev/null  # then stop 0.2 s after it goes quiet
    command cat <&3
)

# cpy [-n] [--] [text...]   — stdin, or the arguments, to the clipboard.
cpy() {
    local strip=0 paste=0 f b64 backend bytes rc=0 caught
    while (( $# )); do
        case $1 in
            -h|--help)
                cat <<'HELP'
Copy to the clipboard — the real one, even over SSH (OSC 52).

Usage: cpy [-n] [--] [TEXT...]     no TEXT = read stdin
       cpy -p                      catch a paste from your terminal
       cpy -c                      clear the clipboard

  -n, --no-newline   drop trailing newlines from stdin
  -p, --paste        wait, then store whatever you paste (Ctrl+Shift+V) — this is
                     how you get your laptop's clipboard onto this box when the
                     terminal refuses to be read. Then use pst as normal: for 10
                     minutes pst returns this capture even if you copy something
                     else on the laptop in the meantime.
  -c, --clear        clear the clipboard and the local spool
  --                 end of options (copy text that starts with -)

Examples:
  cat notes.txt | cpy          cpy < notes.txt
  cpy "ssh nico@nas"           docker logs plex 2>&1 | tail -50 | cpy
  ip -4 a | cpy -n
  cpy -p                       then Ctrl+Shift+V, then: pst > thing.txt

Paste it back with pst. See the top of lib/clipboard.sh (bt clipboard) for the
backends and for enabling remote paste in your terminal.
HELP
                return 0 ;;
            -c|--clear)
                f=$(_clip_file)
                command rm -f -- "$f" "$(_clip_mark)"
                # Dropping the spool is not enough: on wayland/x11/macos the real
                # selection is held by the compositor or another process, so pst
                # would happily keep returning the old value after we claimed to
                # have cleared it. Clear the live backend too.
                case $(_clip_backend) in
                    wayland) wl-copy --clear >/dev/null 2>&1 ;;
                    x11)     if command -v xclip >/dev/null 2>&1; then
                                 printf '' | xclip -selection clipboard -i >/dev/null 2>&1
                             else xsel --clipboard --clear >/dev/null 2>&1; fi ;;
                    macos)   printf '' | pbcopy >/dev/null 2>&1 ;;
                    osc52)   _clip_osc52_write '' ;;
                esac
                [[ -t 2 ]] && echo "cpy: clipboard cleared 📋" >&2
                return 0 ;;
            -n|--no-newline) strip=1; shift ;;
            -p|--paste)      paste=1; shift ;;
            --) shift; break ;;
            -*) echo "cpy: unknown option '$1' (cpy -h)" >&2; return 1 ;;
            *)  break ;;
        esac
    done

    # Everything goes through the spool file: it keeps the bytes exact (no
    # command substitution eating trailing newlines), it is what pst falls back
    # to, and it is what gets base64'd for the terminal.
    f=$(_clip_file)
    command mkdir -p -- "${f%/*}" 2>/dev/null
    # Catch the paste BEFORE touching the spool, and straight into a file rather
    # than through $(…) — command substitution eats trailing newlines, and a
    # mistimed paste must not wipe what was already on the clipboard.
    if (( paste )); then
        caught=$(mktemp "${TMPDIR:-/tmp}/cpy.XXXXXX") || return 1
        [[ -t 2 ]] && printf 'cpy: paste now (Ctrl+Shift+V)… ' >&2
        _clip_slurp > "$caught"
        if [[ ! -s $caught ]]; then
            [[ -t 2 ]] && echo "nothing arrived ❌" >&2
            command rm -f -- "$caught"; return 1
        fi
        # A terminal sends CR for every line break and Windows pastes CRLF. The
        # trailing X is a guard: $(…) strips trailing newlines, which would make
        # `cpy -p; pst > file` lose the file's last newline.
        local d; d=$(command cat -- "$caught"; printf X); d=${d%X}
        d=${d//$'\033'\[200~/}; d=${d//$'\033'\[201~/}   # bracketed-paste markers, if any
        d=${d//$'\r\n'/$'\n'}; d=${d//$'\r'/$'\n'}
        printf '%s' "$d" > "$caught"
        [[ -t 2 ]] && echo "caught ✅" >&2
    fi
    ( umask 077; : > "$f"; ) || { echo "cpy: cannot write $f" >&2; return 1; }
    if (( paste )); then command cat -- "$caught" > "$f"; command rm -f -- "$caught"
    elif (( $# )); then printf '%s' "$*" > "$f"
    else command cat > "$f"; fi
    if (( strip )); then local d; d=$(command cat -- "$f"); printf '%s' "$d" > "$f"; fi
    # A caught paste is what pst should hand back next (see _clip_mark); any other
    # copy is also on the terminal's clipboard, so the normal read order applies again.
    if (( paste )); then date +%s > "$(_clip_mark)"; else command rm -f -- "$(_clip_mark)"; fi

    backend=$(_clip_backend)
    (( paste )) && backend="file"    # it came from the clipboard; no point sending it back
    case $backend in
        # >/dev/null 2>&1 is load-bearing: wl-copy and xclip both fork a daemon
        # that keeps serving the selection after the command returns, and that
        # daemon inherits our stdout. Without closing it, `out=$(cpy file)` (or
        # any command substitution around cpy) blocks forever waiting for EOF on
        # a pipe nothing will ever close.
        wayland) wl-copy < "$f" >/dev/null 2>&1 || rc=1 ;;
        x11)     if command -v xclip >/dev/null 2>&1; then xclip -selection clipboard -i "$f" >/dev/null 2>&1 || rc=1
                 else xsel --clipboard --input < "$f" || rc=1; fi ;;
        macos)   pbcopy < "$f" || rc=1 ;;
        file)    ;;
        *)       b64=$(base64 < "$f" | tr -d '\n'); _clip_osc52_write "$b64" || rc=1 ;;
    esac

    if [[ -t 2 ]]; then
        bytes=$(command wc -c < "$f")
        if (( rc )); then echo "cpy: kept locally — pst will still return it 📋" >&2
        else printf 'cpy: %s → clipboard (%s) 📋\n' "$(_size_fmt "$bytes")" "$backend" >&2; fi
    fi
    return $rc
}

# Byte-exact read of whatever the live backend can give us.
_clip_read_raw() {
    case $(_clip_backend) in
        wayland) wl-paste --no-newline ;;
        x11)     if command -v xclip >/dev/null 2>&1; then xclip -selection clipboard -o; else xsel --clipboard --output; fi ;;
        macos)   pbpaste ;;
        file)    return 1 ;;
        *)       _clip_osc52_read ;;
    esac
}

# pst — the clipboard to stdout.
pst() {
    local only_local=0
    case ${1-} in
        -l|--local) only_local=1 ;;
        -h|--help)
            cat <<'HELP'
Paste the clipboard to stdout — the counterpart to cpy.

Usage: pst              print it
       pst > file       write it            pst | jq .
       pst -l           what cpy last stored on THIS host, never the terminal's clipboard

Over SSH pst asks the terminal for its clipboard (OSC 52). Most terminals ship
that read disabled — Windows Terminal and WezTerm will never implement it — and
then pst returns whatever cpy last copied on this host instead.

To get your laptop's clipboard here on one of those: run `cpy -p`, press
Ctrl+Shift+V, and pst returns it from then on. Terminals that CAN be read are
listed at the top of lib/clipboard.sh (bt clipboard).

A `cpy -p` capture wins over the terminal's clipboard for 10 minutes
(BASHRC_CLIP_PASTE_FRESH), so copying the next command on the laptop cannot
replace what you just pasted. Any plain cpy, or cpy -c, ends that early.
HELP
            return 0 ;;
    esac
    local f tmp src t now fresh=${BASHRC_CLIP_PASTE_FRESH:-600}
    f=$(_clip_file)
    tmp=$(mktemp "${TMPDIR:-/tmp}/cpy.XXXXXX") || return 1
    # A fresh `cpy -p` capture beats the terminal (why: _clip_mark).
    if (( ! only_local )) && [[ -s $f && -r $(_clip_mark) ]]; then
        IFS= read -r t < "$(_clip_mark)"; now=$(date +%s)
        [[ $t =~ ^[0-9]+$ ]] && (( now - t < fresh )) && only_local=1
    fi
    if (( only_local )); then
        if [[ ! -s $f ]]; then
            command rm -f -- "$tmp"
            echo "pst: nothing copied with cpy on $HOSTNAME yet 📋" >&2
            return 1
        fi
        src=$f
    elif _clip_read_raw > "$tmp" 2>/dev/null && [[ -s $tmp ]]; then
        src=$tmp
    elif [[ -s $f ]]; then
        src=$f
        # Say why once per shell, then stay quiet — this is the normal SSH case.
        if [[ -t 2 && -z ${_CLIP_FELLBACK-} && $(_clip_backend) == osc52 ]]; then
            _CLIP_FELLBACK=1
            echo "pst: terminal won't be read (normal) — returning what cpy last copied here. For your laptop's clipboard: cpy -p 📋" >&2
        fi
    else
        command rm -f -- "$tmp"
        echo "pst: clipboard empty — nothing copied with cpy on $HOSTNAME yet 📋" >&2
        return 1
    fi
    command cat -- "$src"
    # A terminal wants its prompt on a fresh line; a pipe or a file wants the bytes untouched.
    [[ -t 1 && $(command tail -c1 -- "$src" | command wc -l) -eq 0 ]] && echo
    command rm -f -- "$tmp"
    return 0
}
_cpy_completions() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    [[ $cur == -* ]] && COMPREPLY=($(compgen -W '-h --help -n --no-newline -p --paste -c --clear' -- "$cur"))
}
complete -F _cpy_completions cpy
complete -W '-h --help -l --local' pst
