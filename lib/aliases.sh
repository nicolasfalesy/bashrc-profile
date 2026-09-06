#!/usr/bin/env bash
# lib/aliases.sh — one-liners. Anything with logic belongs in a function module.
# Aliases that need a tool are only defined when that tool exists, so the same
# file is safe on the Pi, the NAS and a desktop.

# `sudo ` with a trailing space lets the *next* word expand as an alias too
# (sudo ni foo → sudo nala install foo).
alias sudo='sudo '

# ── Editor ───────────────────────────────────────────────────────────────────
if hash nvim 2>/dev/null; then
    alias vim='nvim' vi='nvim'
fi
alias svim='sudo $EDITOR'                     # edit as root
alias nt='$EDITOR ~/.config/nvim/init.lua'    # neovim config

# ── Package management (Debian family; skipped where apt is unusable, e.g. TrueNAS)
if hash nala 2>/dev/null; then
    alias apt='sudo nala'
    alias ni='sudo nala install'
    alias np='sudo nala purge'
    alias ns='nala search'
    alias nu='sudo nala full-upgrade -y'          # update lists + upgrade everything
    alias nclean='sudo nala autoremove -y && sudo nala clean'
elif hash apt-get 2>/dev/null; then
    alias ni='sudo apt install'
    alias np='sudo apt purge'
    alias ns='apt search'
    alias nu='sudo apt update && sudo apt full-upgrade -y'
    alias nclean='sudo apt autoremove -y && sudo apt clean'
fi

# ── Safer / friendlier core commands ─────────────────────────────────────────
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -p'
if hash trash 2>/dev/null; then
    alias rm='trash -v'                           # to the trash can (trash-list / trash-restore)
else
    alias rm='rm -I'                              # one prompt for >3 files or -r
fi
alias rmd='command rm -rfv'                       # the real rm: recursive, forced, verbose
alias ping='ping -c 10'
alias mx='chmod a+x'
alias ..='cd ..'
alias ...='cd ../..'
alias cd..='cd ..'
alias e='exit'
alias c='clear'
alias h='history | grep'                          # h docker  → search history
alias ports='sudo ss -tulnp'                      # everything listening (tcp+udp)
alias openports='ports'

# ── Listing & disk ───────────────────────────────────────────────────────────
# `ll` itself is a function (lib/navigation.sh) so other functions can call it.
alias l='ll'
alias lt='ll -tr'                                 # by time, newest last
if hash tree 2>/dev/null; then
    alias tree='tree -CAhF --dirsfirst'
fi
alias folders='command du -h --max-depth=1 2>/dev/null | sort -h'   # sizes of subdirs, sorted
alias mnts='df -hT -x tmpfs -x devtmpfs -x overlay -x squashfs'     # real mounts only

# ── Git ──────────────────────────────────────────────────────────────────────
alias gs='git status'
alias ga='git add'
alias gaa='git add -A'
alias gc='git commit'
alias gcm='git commit -m'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gds='git diff --staged'
alias gb='git branch'
alias gco='git checkout'
alias gsw='git switch'
alias glog='git log --oneline --graph --decorate -20'
alias gst='git stash'
alias gstp='git stash pop'
alias gcl='git clone'

# ── systemd ──────────────────────────────────────────────────────────────────
if hash systemctl 2>/dev/null; then
    alias sc='systemctl'
    alias scs='systemctl status'
    alias scf='systemctl --failed'
    alias scstart='sudo systemctl start'
    alias scstop='sudo systemctl stop'
    alias screstart='sudo systemctl restart'
    alias scenable='sudo systemctl enable --now'
    alias scdisable='sudo systemctl disable --now'
    alias sclog='journalctl -eu'                  # sclog nginx  → jump to end of unit log
    alias sclogf='journalctl -fu'                 # follow
fi

# ── Docker Compose (run from the directory holding the compose file) ─────────
# Renamed from du/dd/dr: `du` and `dd` shadowed the coreutils and silently broke
# `folders`. `dr` is kept as an alias of dcr for muscle memory.
# shellcheck disable=SC2139  # $_dk is meant to expand now: the aliases bake in `sudo` or not
if hash docker 2>/dev/null; then
    if [[ -w /var/run/docker.sock ]]; then _dk='docker'; else _dk='sudo docker'; fi
    alias dcu="$_dk compose up -d"
    alias dcd="$_dk compose down"
    alias dcr="$_dk compose down && $_dk compose up -d"
    alias dr='dcr'
    alias dcl="$_dk compose logs -f --tail=100"
    alias dcp="$_dk compose pull"
    alias dps="$_dk ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
    alias dprune="$_dk system prune -f"
    unset _dk
fi

# ── This profile ─────────────────────────────────────────────────────────────
alias reload='source ~/.bashrc && echo "🚀 bash profile reloaded"'
if hash fastfetch 2>/dev/null; then alias fetch='fastfetch'; fi

# bt — edit the profile.  bt | bt aliases | bt pi | bt local | bt config | bt readme | bt -l
# When the editor exits and the file changed: bash files are syntax-checked
# (bash -n) and, if they parse, ~/.bashrc is re-sourced in this shell — no
# separate `reload` needed. A file that does not parse is NOT reloaded.
bt() {
    local d=$BASHRC_PROFILE_DIR f
    case ${1-} in
        -h|--help)
            cat <<'HELP'
Edit the bash profile.

Usage: bt [module|local|config|readme|<doc>|-l]

  bt              edit lib/aliases.sh
  bt <name>       edit lib/<name>.sh or profiles/<name>.sh   (bt system, bt pi)
  bt local        edit ~/.bashrc.local   (secrets, ssh hosts — not in git)
  bt config       edit ~/.config/bashrc-profile/config       (profile + toggles)
  bt readme       edit README.md;  bt features|setup|architecture|audit → docs/*.md
  bt theme        edit the starship theme this machine links (themes/aurora.toml or waterloo-gold)
  bt aurora | bt waterloo-gold | bt blerc | bt install.sh | bt tests/smoke.sh
  bt -l           list what you can edit

Bash files are syntax-checked and the profile reloaded when the editor exits.
Related: bgit (git in the repo from anywhere), bup (pull + reload), prereqs (deps).
HELP
            return 0 ;;
        -l|--list)
            printf 'lib:      '; (builtin cd "$d/lib" && printf '%s ' *.sh); echo
            printf 'profiles: '; (builtin cd "$d/profiles" && printf '%s ' *.sh); echo
            printf 'docs:     readme '; (builtin cd "$d/docs" && for f in *.md; do printf '%s ' "${f%.md}"; done | tr '[:upper:]' '[:lower:]'); echo
            printf 'themes:   theme '; (builtin cd "$d/themes" && for f in *.toml; do printf '%s ' "${f%.toml}"; done); echo
            printf 'other:    local config install.sh blerc tests/smoke.sh\n'
            return 0 ;;
        '')      f="$d/lib/aliases.sh" ;;
        local)   f="$HOME/.bashrc.local" ;;
        config)  f="$BASHRC_CONFIG_DIR/config" ;;
        readme)  f="$d/README.md" ;;
        theme)   f=$(readlink -f "$HOME/.config/starship.toml") ;;
        *)
            for f in "$d/lib/$1.sh" "$d/profiles/$1.sh" "$d/themes/$1.toml" "$d/docs/${1^^}.md" "$d/$1"; do
                [[ -f $f ]] && break
            done
            [[ -f $f ]] || { echo "bt: no module '$1' (try: bt -l)" >&2; return 1; } ;;
    esac
    # Content checksum, not mtime: a save within the same second as the open
    # would otherwise look unchanged.
    local before after
    before=$(cksum < "$f" 2>/dev/null)
    $EDITOR "$f" || return                                    # unquoted: EDITOR="code --wait" is fine
    after=$(cksum < "$f" 2>/dev/null)
    [[ $after != "$before" ]] || return 0                     # nothing changed
    case $f in
        */install.sh|*/tests/*)
            bash -n "$f" && echo "✓ $f parses" ;;
        *.sh|*/bashrc|*/.bashrc.local|*/config)
            if bash -n "$f"; then
                source ~/.bashrc && echo "🚀 ${f##*/} reloaded"
            else
                echo "bt: $f has a syntax error — not reloaded" >&2; return 1
            fi ;;
        *.toml) echo "✓ saved — starship re-reads its config at the next prompt" ;;
        *)      echo "✓ saved $f" ;;
    esac
}
_bt_completions() {
    local cur=${COMP_WORDS[COMP_CWORD]} d=$BASHRC_PROFILE_DIR words
    words=$(builtin cd "$d/lib" && printf '%s ' *.sh; builtin cd "$d/profiles" && printf '%s ' *.sh
            builtin cd "$d/docs" && printf '%s ' *.md; builtin cd "$d/themes" && printf '%s ' *.toml)
    words=${words//.sh/}; words=${words//.md/}; words=${words//.toml/}; words=${words,,}
    COMPREPLY=($(compgen -W "$words readme theme local config install.sh blerc tests/smoke.sh -l -h" -- "$cur"))
}
complete -F _bt_completions bt

# bup — update the profile from GitHub and reload.
# install.sh --update = git pull --ff-only, relink, add toggles introduced since
# this machine's config was written, clear the init caches, verify. Then re-source.
bup() {
    if [[ ${1-} == -h || ${1-} == --help ]]; then
        echo "bup: install.sh --update (git pull, relink, refresh config, clear caches) then reload"; return 0
    fi
    bash "$BASHRC_PROFILE_DIR/install.sh" --update || return
    source ~/.bashrc && echo "🚀 bash profile updated and reloaded"
}

# bgit — git inside the profile repo, from any directory.
#   bgit status · bgit diff · bgit add -A · bgit commit -m "…" · bgit push · bgit log --oneline
alias bgit='git -C "$BASHRC_PROFILE_DIR"'

# prereqs — install every dependency for this machine's profile.
#   prereqs --with-dev        add the C toolchain
#   prereqs --upgrade         refresh the user-local tools (ble.sh nightly, starship, fzf, zoxide)
prereqs() { bash "$BASHRC_PROFILE_DIR/install.sh" --deps-only "$@"; }
alias install_prereqs='prereqs'
