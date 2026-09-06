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

# bt — edit the profile.  bt | bt aliases | bt pi | bt local | bt config | bt -l
bt() {
    local d=$BASHRC_PROFILE_DIR f
    case ${1-} in
        -h|--help)
            cat <<'HELP'
Edit the bash profile.

Usage: bt [module|local|config|-l]

  bt              edit lib/aliases.sh
  bt <name>       edit lib/<name>.sh or profiles/<name>.sh (e.g. bt system, bt pi)
  bt local        edit ~/.bashrc.local   (secrets, ssh hosts — not in git)
  bt config       edit ~/.config/bashrc-profile/config (profile + toggles)
  bt -l           list modules
Run `reload` afterwards.
HELP
            return 0 ;;
        -l|--list)
            printf 'lib:      '; (builtin cd "$d/lib" && printf '%s ' *.sh); echo
            printf 'profiles: '; (builtin cd "$d/profiles" && printf '%s ' *.sh); echo
            printf 'other:    local config install.sh starship.toml blerc\n'
            return 0 ;;
        '')      "$EDITOR" "$d/lib/aliases.sh" ;;
        local)   "$EDITOR" "$HOME/.bashrc.local" ;;
        config)  "$EDITOR" "$BASHRC_CONFIG_DIR/config" ;;
        *)
            for f in "$d/lib/$1.sh" "$d/profiles/$1.sh" "$d/$1"; do
                [[ -f $f ]] && { "$EDITOR" "$f"; return; }
            done
            echo "bt: no module '$1' (try: bt -l)" >&2; return 1 ;;
    esac
}
_bt_completions() {
    local cur=${COMP_WORDS[COMP_CWORD]} d=$BASHRC_PROFILE_DIR words
    words=$(builtin cd "$d/lib" && printf '%s ' *.sh; builtin cd "$d/profiles" && printf '%s ' *.sh)
    COMPREPLY=($(compgen -W "${words//.sh/} local config install.sh starship.toml blerc -l -h" -- "$cur"))
}
complete -F _bt_completions bt

# bup — update the profile from GitHub and reload.
bup() {
    if [[ ${1-} == -h || ${1-} == --help ]]; then
        echo "bup: git pull the bashrc-profile repo, clear init caches, reload the shell"; return 0
    fi
    git -C "$BASHRC_PROFILE_DIR" pull --ff-only || return
    command rm -f "$BASHRC_CACHE_DIR"/*.bash 2>/dev/null
    source ~/.bashrc && echo "🚀 bash profile updated and reloaded"
}

# prereqs — install every dependency for this machine's profile.
prereqs() { bash "$BASHRC_PROFILE_DIR/install.sh" --deps-only "$@"; }
alias install_prereqs='prereqs'
