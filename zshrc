#!/usr/bin/env zsh

###############################################################################
# ZSH OPTIONS
###############################################################################
setopt NO_BEEP
setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt AUTO_CD
setopt INTERACTIVE_COMMENTS
setopt NO_FLOW_CONTROL

###############################################################################
# SOURCED FILES & COMPLETIONS
###############################################################################
if command -v fastfetch &>/dev/null; then
	fastfetch
fi

# Source global definitions
if [ -f /etc/zshrc ]; then
	. /etc/zshrc
fi

# Enable zsh completions and bash completion compatibility
autoload -Uz compinit && compinit
if autoload -Uz bashcompinit 2>/dev/null; then
    bashcompinit 2>/dev/null
fi
# Hard fallback: if complete is still not available, define it as a no-op
# so shell_functions doesn't error on bash-style complete calls
(( ${+functions[complete]} )) || complete() { :; }

# Source additional shell functions
if [ -f "$HOME/.shell_functions" ]; then
    . "$HOME/.shell_functions"
fi

###############################################################################
# SHELL OPTIONS & INPUT
###############################################################################

# Case-insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# Ctrl+f to insert 'zi' followed by a newline (zoxide interactive)
bindkey -s '^f' 'zi\n'

###############################################################################
# ENVIRONMENT VARIABLES & EXPORTS
###############################################################################

export TERMINAL=/usr/bin/alacritty

# History
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=10000
export SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS

# XDG directories
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"

# Editor
export EDITOR=nvim
export VISUAL=nvim

# Seeing as other scripts will use it might as well export it
export LINUXTOOLBOXDIR="$HOME/linuxtoolbox"

# Colors for ls and all grep commands such as grep, egrep and zgrep
export CLICOLOR=1
export LS_COLORS='no=00:fi=00:di=00;34:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.avi=01;35:*.fli=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:*.xml=00;31:'
#export GREP_OPTIONS='--color=auto' #deprecated

# Color for manpages in less makes manpages a little easier to read
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

export QT_QPA_PLATFORMTHEME=qt5ct

# Minecraft RCON
export RCON_IP="${RCON_IP:-192.168.2.182}"
export RCON_PORT="${RCON_PORT:-25575}"
export RCON_PASS="${RCON_PASS:-ADF3F9S3Lkvjv39lk39F}"

# PATH
mkdir -p "$HOME/.local/bin"
export PATH=$PATH:"$HOME/.local/bin:$HOME/.cargo/bin:/var/lib/flatpak/exports/bin:/.local/share/flatpak/exports/bin"

###############################################################################
# ALIASES — EDITOR
###############################################################################
alias vim='nvim'
alias vi='nvim'
alias svim='sudo nvim'
alias svi='sudo nvim'
alias snvim='sudo nvim'

###############################################################################
# ALIASES — DOCKER
###############################################################################
alias du='sudo docker compose up -d'
alias dd='sudo docker compose down'
alias dr='sudo docker compose down && sudo docker compose up -d'

###############################################################################
# ALIASES — CONFIG FILES & SHORTCUTS
###############################################################################
alias kt='vim ~/.config/alacritty/keybinds.toml'
alias bt='vim ~/.zshrc'
alias nt='vim ~/.config/nvim/init.lua'
alias notes='vim $HOME/Nextcloud/constant\ notes.txt'
alias reload='source ~/.zshrc && echo "🚀 Zsh config reloaded!"'
alias e='exit'
alias c='clear'

###############################################################################
# ALIASES — SCRIPTS & MOUNTS
###############################################################################
alias mnt='~/Scripts/mnt.sh'
alias umount='~/Scripts/umount.sh'
alias unmount='umount'
alias bk='~/Scripts/backup.sh'
alias backup='bk'

###############################################################################
# ALIASES — SSH
###############################################################################
alias uw='ssh nfalesy@ubuntu2404-010.student.cs.uwaterloo.ca'
alias nas='ssh truenas_admin@192.168.2.182'
alias pi='ssh raspby@192.168.2.181'

###############################################################################
# ALIASES — MODIFIED CORE COMMANDS
###############################################################################
alias cp='cp -i'
alias mv='mv -i'
alias rm='trash -v'
alias mkdir='mkdir -p'
alias ps='ps auxf'
alias ping='ping -c 10'
alias home='cd ~'
alias cd..='cd ..'
alias bd='cd "$OLDPWD"'
alias rmd='/bin/rm  --recursive --force --verbose '
alias k9='pkill'
alias da='date "+%Y-%m-%d %A %T %Z"'

###############################################################################
# ALIASES — LISTING & FILESYSTEM
###############################################################################
alias ll='ls -AFlsh --color=auto' # long listing format
alias l='ll'
alias tree='tree -CAhF --dirsfirst'
alias treed='tree -CAFd'
alias folders='du -h --max-depth=1'
alias folderssort='find . -maxdepth 1 -type d -print0 | xargs -0 du -sk | sort -rn'
alias mnts='df -hT'

###############################################################################
# ALIASES — PERMISSIONS
###############################################################################
alias mx='chmod a+x'
alias 000='sudo chmod -R 000 '
alias 600='sudo chmod -R 600 '
alias 666='sudo chmod -R 666 '
alias 700='sudo chmod -R 700 '
alias 777='sudo chmod -R 777 '

###############################################################################
# ALIASES — SEARCH & INFO
###############################################################################
# Check if ripgrep is installed
if command -v rg &> /dev/null; then
    # Alias grep to rg if ripgrep is installed
    alias grep='rg'
else
    # Alias grep to /usr/bin/grep with GREP_OPTIONS if ripgrep is not installed
    alias grep="/usr/bin/grep $GREP_OPTIONS"
fi
unset GREP_OPTIONS

# Search command line history
alias h="history | grep "
# Search files in the current folder
alias f="find . | grep "
# Count all files (recursively) in the current folder
alias countfiles="for t in files links directories; do echo \`find . -type \${t:0:1} | wc -l\` \$t; done 2> /dev/null"
# Show open ports
alias ports='netstat -nape --inet'

###############################################################################
# ALIASES — SYSTEM
###############################################################################
alias rebootsafe='sudo shutdown -r now'
alias rebootforce='sudo shutdown -r -n now'
alias linutil='curl -fsSL https://christitus.com/linux | sh'

###############################################################################
# FUNCTIONS — NAVIGATION
###############################################################################

# Automatically do an ls after each cd, z, or zoxide
cd ()
{
	if [ -n "$1" ]; then
		builtin cd "$@" && ll
	else
		builtin cd ~ && ll
	fi
}

# Goes up a specified number of directories  (i.e. up 4)
up() {
	local d=""
	limit=$1
	for ((i = 1; i <= limit; i++)); do
		d=$d/..
	done
	d=$(echo $d | sed 's/^\///')
	if [ -z "$d" ]; then
		d=..
	fi
	cd $d
}

# Copy and go to the directory
cpg() {
	if [ -d "$2" ]; then
		cp "$1" "$2" && cd "$2"
	else
		cp "$1" "$2"
	fi
}

# Move and go to the directory
mvg() {
	if [ -d "$2" ]; then
		mv "$1" "$2" && cd "$2"
	else
		mv "$1" "$2"
	fi
}

# Create and go to the directory
mkdirg() {
	mkdir -p "$1"
	cd "$1"
}

###############################################################################
# FUNCTIONS — FILE OPERATIONS
###############################################################################

extract() {
    case "$1" in
        -h|--help|help|"")
            echo "Usage: extract <file> 📦"
            echo "  Supports: .tar.bz2, .tar.gz, .bz2, .rar, .gz, .tar, .tbz2, .tgz, .zip, .Z, .7z"
            return 0
            ;;
        *)
            if [ -f "$1" ]; then
                case "$1" in
                    *.tar.bz2)   tar xjf "$1"     ;;
                    *.tar.gz)    tar xzf "$1"     ;;
                    *.bz2)       bunzip2 "$1"     ;;
                    *.rar)       unrar x "$1"     ;;
                    *.gz)        gunzip "$1"      ;;
                    *.tar)       tar xf "$1"      ;;
                    *.tbz2)      tar xjf "$1"     ;;
                    *.tgz)       tar xzf "$1"     ;;
                    *.zip)       unzip "$1"       ;;
                    *.Z)         uncompress "$1"  ;;
                    *.7z)        7z x "$1"        ;;
                    *)           echo "'$1' cannot be extracted via extract() ❌" ;;
                esac
            else
                echo "'$1' is not a valid file ❌"
            fi
            ;;
    esac
}

# Searches for text in all files in the current folder
ftext() {
	# -i case-insensitive
	# -I ignore binary files
	# -H causes filename to be printed
	# -r recursive search
	# -n causes line number to be printed
	# optional: -F treat search term as a literal, not a regular expression
	# optional: -l only print filenames and not the matching lines ex. grep -irl "$1" *
	grep -iIHrn --color=always "$1" . | less -r
}

# Show the size of one or more directories (defaults to current directory)
size() {
    local unit=""
    local targets=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help|-H)
                cat <<'EOF'
Show the size of one or more directories (defaults to current directory).

Usage: size [OPTIONS] [DIRECTORY...]

Options:
  -h, -H, --help       Show this help message
  --size UNIT           Force unit: K (KiB), M (MiB), G (GiB), T (TiB)

Examples:
  size                  Size of current directory, auto units
  size /var/log         Size of /var/log, auto units
  size ollama plex      Size of both directories
  size --size G /var    Size of /var in GiB
EOF
                return 0
                ;;
            --size)
                shift
                unit=$(echo "$1" | tr '[:lower:]' '[:upper:]')
                if [[ ! "$unit" =~ ^[KMGT]$ ]]; then
                    echo "Error: --size requires K, M, G, or T" >&2
                    return 1
                fi
                ;;
            *)
                targets+=("$1")
                ;;
        esac
        shift
    done

    if (( ${#targets[@]} == 0 )); then
        targets=(".")
    fi

    local grand_total=0
    local tmpfile bytes result i idx du_pid
    local spin='|/-\'

    for target in "${targets[@]}"; do
        if [[ ! -d "$target" ]]; then
            echo "Error: '$target' is not a directory" >&2
            continue
        fi

        tmpfile=$(mktemp)

        set +m
        { command du -sb "$target" > "$tmpfile" 2>/dev/null & } 2>/dev/null
        du_pid=$!

        i=0
        while kill -0 "$du_pid" 2>/dev/null; do
            idx=$(( i % ${#spin} ))
            printf "\r  [%s] scanning %s..." "${spin:$idx:1}" "$target"
            (( i++ ))
            sleep 0.1
        done
        printf "\r\033[K"

        wait "$du_pid" 2>/dev/null
        set -m
        bytes=$(awk '{print $1}' "$tmpfile")
        command rm -f "$tmpfile"

        if [[ -z "$bytes" ]]; then
            echo "Error: couldn't read size of '$target'" >&2
            continue
        fi

        (( grand_total += bytes ))

        result=""
        if [[ -n "$unit" ]]; then
            case "$unit" in
                K) result=$(awk "BEGIN {printf \"%.2f KiB\", $bytes / 1024}") ;;
                M) result=$(awk "BEGIN {printf \"%.2f MiB\", $bytes / 1048576}") ;;
                G) result=$(awk "BEGIN {printf \"%.2f GiB\", $bytes / 1073741824}") ;;
                T) result=$(awk "BEGIN {printf \"%.2f TiB\", $bytes / 1099511627776}") ;;
            esac
        else
            if (( bytes >= 1099511627776 )); then
                result=$(awk "BEGIN {printf \"%.2f TiB\", $bytes / 1099511627776}")
            elif (( bytes >= 1073741824 )); then
                result=$(awk "BEGIN {printf \"%.2f GiB\", $bytes / 1073741824}")
            elif (( bytes >= 1048576 )); then
                result=$(awk "BEGIN {printf \"%.2f MiB\", $bytes / 1048576}")
            elif (( bytes >= 1024 )); then
                result=$(awk "BEGIN {printf \"%.2f KiB\", $bytes / 1024}")
            else
                result="${bytes} B"
            fi
        fi

        echo "$result  $target"
    done

    if (( ${#targets[@]} > 1 )); then
        local total=""
        if [[ -n "$unit" ]]; then
            case "$unit" in
                K) total=$(awk "BEGIN {printf \"%.2f KiB\", $grand_total / 1024}") ;;
                M) total=$(awk "BEGIN {printf \"%.2f MiB\", $grand_total / 1048576}") ;;
                G) total=$(awk "BEGIN {printf \"%.2f GiB\", $grand_total / 1073741824}") ;;
                T) total=$(awk "BEGIN {printf \"%.2f TiB\", $grand_total / 1099511627776}") ;;
            esac
        else
            if (( grand_total >= 1099511627776 )); then
                total=$(awk "BEGIN {printf \"%.2f TiB\", $grand_total / 1099511627776}")
            elif (( grand_total >= 1073741824 )); then
                total=$(awk "BEGIN {printf \"%.2f GiB\", $grand_total / 1073741824}")
            elif (( grand_total >= 1048576 )); then
                total=$(awk "BEGIN {printf \"%.2f MiB\", $grand_total / 1048576}")
            elif (( grand_total >= 1024 )); then
                total=$(awk "BEGIN {printf \"%.2f KiB\", $grand_total / 1024}")
            else
                total="${grand_total} B"
            fi
        fi
        echo "---------------------"
        echo "$total  total"
    fi
}


###############################################################################
# FUNCTIONS — NETWORKING & VPN
###############################################################################

# IP address lookup
alias whatismyip="whatsmyip"
function whatsmyip () {
    # Internal IP Lookup.
    if command -v ip &> /dev/null; then
        echo -n "Internal IP: "
        ip addr show wlan0 | grep "inet " | awk '{print $2}' | cut -d/ -f1
    else
        echo -n "Internal IP: "
        ifconfig wlan0 | grep "inet " | awk '{print $2}'
    fi

    # External IP Lookup
    echo -n "External IP: "
    curl -4 ifconfig.me
}

# Public IP lookup (simple, just the external IP)
pubip() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: pubip"
        echo "  Prints your public IPv4 address."
        return 0
    fi
    curl -s -4 ifconfig.me/ip
    echo
}

vpn() {
    case "$1" in
        -h|--help|help)
            echo "Usage: vpn [option]"
            echo "  (no args)  Connect to VPN 🔒"
            echo "  -s         Show status (wg show) 📊"
            echo "  -d|-r|-p   Disconnect VPN 🛑"
            echo "  -h|--help  Show this help message 💡"
            ;;
        -s)
            sudo wg show
            ;;
        -d|-r|-p)
            sudo wg-quick down wg0
            ;;
        *)
            echo "Connecting... 🔒"
            # This flag bypasses the 'stat' permission bug in Ubuntu ARM
            sudo WG_QUICK_USERSPACE_IMPLEMENTATION=bash wg-quick up wg0
            echo "VPN is up! ✅"
            ;;
    esac
}

###############################################################################
# FUNCTIONS — CLIPBOARD
###############################################################################

# Clipboard copy — argument or stdin
cpy() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: cpy [text] or echo 'text' | cpy"
        echo "  Copies text to clipboard via xclip."
        return 0
    fi
    if [[ -n "$1" ]]; then
        printf '%s' "$*" | xclip -selection clipboard
    else
        xclip -selection clipboard
    fi
}

# Clipboard paste
pst() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: pst"
        echo "  Pastes clipboard contents to stdout."
        return 0
    fi
    xclip -selection clipboard -o
}

###############################################################################
# FUNCTIONS — SYSTEM & APPLICATIONS
###############################################################################

sys() {
    # Colors
    local G='\033[0;32m' # Green
    local B='\033[0;34m' # Blue
    local Y='\033[1;33m' # Yellow
    local R='\033[0;31m' # Red
    local NC='\033[0m'   # No Color

    echo -e "${B}--- System Status ---${NC}"

    # 1. CPU Utilization % (Calculating delta over 0.5s)
    local cpu_util=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}')
    sleep 0.5
    local cpu_util2=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}')
    local cpu_final=$(echo "$cpu_util2" | awk '{printf "%.1f", $1}')

    # Color the CPU output based on intensity
    local cpu_color=$G
    (( $(echo "$cpu_final > 70" | bc -l) )) && cpu_color=$Y
    (( $(echo "$cpu_final > 90" | bc -l) )) && cpu_color=$R

    echo -e "${G}CPU Usage:${NC}  ${cpu_color}${cpu_final}%${NC}"

    # 2. RAM Usage
    local mem=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    echo -e "${G}Memory:${NC}     $mem"

    # 3. Disk Usage (Root Partition)
    local disk=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    echo -e "${G}Disk (/):${NC}   $disk"

    # 4. Network (Local IP)
    local ip=$(hostname -I | awk '{print $1}')
    echo -e "${G}Local IP:${NC}   $ip"

    # 5. Battery (For your Yoga Slim 7)
    if [ -d /sys/class/power_supply/BAT0 ]; then
        local bat=$(cat /sys/class/power_supply/BAT0/capacity)
        local status=$(cat /sys/class/power_supply/BAT0/status)
        echo -e "${Y}Battery:${NC}    $bat% ($status)"
    fi
}

apps() {
    case "$1" in
        -h|--help|help)
            echo "Usage: apps [option] 📂"
            echo "  (no args)  Change directory to local applications 🏠"
            echo "  -u         Update desktop database 🔄"
            echo "  -h|--help  Show this help message 💡"
            ;;
        -u)
            update-desktop-database ~/.local/share/applications
            echo "Updated your applications! ✅"
            ;;
        *)
            cd ~/.local/share/applications || echo "Directory not found! ❌"
            ;;
    esac
}

install_app() {
    local APPS_DIR="$HOME/.local/share/applications"

    case "$1" in
        -h|--help|help|"")
            echo "Usage: install_app [option/path] 🚀"
            echo "  <path>      Link a .desktop file to your local applications 🔗"
            echo "  -l [query]  List installed local apps (optional: filter by name) 📋"
            echo "  -h|--help   Show this help message 💡"
            return 0
            ;;
        -l)
            echo "Installed local applications in $APPS_DIR: 📂"
            if [[ -n "$2" ]]; then
                ls "$APPS_DIR" | grep -i "$2" | grep ".desktop" | sed 's/.desktop//'
            else
                ls "$APPS_DIR" | grep ".desktop" | sed 's/.desktop//'
            fi
            return 0
            ;;
        *)
            local src
            src=$(realpath "$1" 2>/dev/null)
            local dest="$APPS_DIR/$(basename "$src")"

            if [[ -f "$src" && "$src" == *.desktop ]]; then
                ln -sf "$src" "$dest"
                echo "✅ Linked $src to $dest"
                # Optional: trigger the update-desktop-database if you have it
                # update-desktop-database "$APPS_DIR" &>/dev/null
            else
                echo "❌ Error: File not found or not a .desktop file."
                echo "Check the path and try again. 🧐"
                return 1
            fi
            ;;
    esac
}

###############################################################################
# FUNCTIONS — ALACRITTY THEME MANAGER
###############################################################################

at() {
    local THEME_DIR="$HOME/.config/alacritty/themes/themes"
    local ACTIVE_LINK="$THEME_DIR/active_theme.toml"
    local CONFIG_FILE="$HOME/.config/alacritty/alacritty.toml"

    case "$1" in
        -h|--help|help)
            echo "Usage: at [option] 🎨"
            echo "  (no args)          Open Alacritty config in Vim 📝"
            echo "  -t <theme>         Set active theme via symlink 🔗"
            echo "  -l [query]         List themes (optional: filter by name) 📋"
            echo "  -h|--help          Show this help message 💡"
            return 0
            ;;
        -l)
            echo "Available themes in $THEME_DIR: 📂"
            if [[ -n "$2" ]]; then
                ls "$THEME_DIR" | grep -i "$2" | grep ".toml" | sed 's/.toml//'
            else
                ls "$THEME_DIR" | grep ".toml" | sed 's/.toml//'
            fi
            return 0
            ;;
        -t)
            if [[ -z "$2" ]]; then
                echo "❓ Usage: at -t <theme_name>"
                return 1
            fi

            local TARGET="$THEME_DIR/$2"
            [[ "$TARGET" != *.toml ]] && TARGET="${TARGET}.toml"

            if [[ -f "$TARGET" ]]; then
                ln -sf "$TARGET" "$ACTIVE_LINK"
                echo "✅ Theme set to: $(basename "$TARGET" .toml)"
            else
                echo "❌ Error: Theme '$2' not found."
                echo "Run 'at -l' to see all available themes."
                return 1
            fi
            ;;
        *)
            vim "$CONFIG_FILE"
            ;;
    esac
}

###############################################################################
# FUNCTIONS — GRUB MANAGEMENT
###############################################################################

grub() {
  local THEME_DIR="/boot/grub/themes"

  # Help Menu Logic
  if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
    echo "🛠️  GRUB Management Utility"
    echo "Usage:"
    echo "  grub          - Update GRUB configuration"
    echo "  grub -e       - Edit /etc/default/grub with vim"
    echo "  grub -t [dir] - Copy theme to $THEME_DIR and update config"
    echo "  grub -d       - Change directory to $THEME_DIR"
    echo "  grub -h       - Show this help menu"
    return 0
  fi

  # Flag Logic
  if [[ "$1" == "-e" ]]; then
    sudo vim /etc/default/grub

  elif [[ "$1" == "-d" ]]; then
    cd "$THEME_DIR" || echo "❌ Directory not found"

  elif [[ "$1" == "-t" ]]; then
    if [[ -z "$2" ]]; then
      echo "❌ Brother you forgot the directory.... try again"
      return 1
    fi

    local folder_name=$(basename "$2")
    sudo cp -r "$2" "$THEME_DIR/"

    # Update the GRUB_THEME line in config
    sudo sed -i "s|^#\?GRUB_THEME=.*|GRUB_THEME=\"$THEME_DIR/$folder_name/theme.txt\"|" /etc/default/grub

    echo "✅ Theme $folder_name installed."
    sudo update-grub

  else
    sudo update-grub
  fi
}

###############################################################################
# FUNCTIONS — MINECRAFT RCON
###############################################################################

rcon() {
    local G='\033[0;32m'
    local R='\033[0;31m'
    local NC='\033[0m'

    case "$1" in
        -h|--help|help)
            echo "Usage: rcon <command> [args...]"
            echo "  Sends a command to a Minecraft server via RCON (mcrcon)."
            echo ""
            echo "  Environment variables (with defaults):"
            echo "    RCON_IP   - Server IP   (default: 192.168.2.182)"
            echo "    RCON_PORT - Server port  (default: 25575)"
            echo "    RCON_PASS - RCON password"
            echo ""
            echo "  Examples:"
            echo "    rcon list"
            echo "    rcon say Hello everyone!"
            echo "    rcon whitelist add Steve"
            echo "    rc tp Player1 Player2"
            return 0
            ;;
    esac

    if [[ $# -eq 0 ]]; then
        echo -e "${R}Error: Please provide a command. Example: rc list${NC}" >&2
        return 1
    fi

    if ! command -v mcrcon &>/dev/null; then
        echo -e "${R}Error: mcrcon not found. Install it with your package manager.${NC}" >&2
        return 1
    fi

    if [[ -z "$RCON_PASS" ]]; then
        echo -e "${R}Error: RCON_PASS environment variable not set.${NC}" >&2
        return 1
    fi

    local result
    result=$(mcrcon -H "${RCON_IP}" -P "${RCON_PORT}" -p "${RCON_PASS}" -w 5 "$*" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo -e "${G}RCON Success${NC}"
        [[ -n "$result" ]] && echo "$result"
    else
        echo -e "${R}RCON Failed (Exit: $exit_code)${NC}" >&2
        [[ -n "$result" ]] && echo "$result"
        return 1
    fi
}
alias rc='rcon'


###############################################################################
# FUNCTIONS — CLOUDFLARE TUNNEL
###############################################################################

cloud() {
  # 1. Open config for manual edits
  sudo vim /etc/cloudflared/config.yml

  # 2. Add the DNS route for the new subdomain
  # Syntax: cloudflared tunnel route dns <tunnel-name/ID> <hostname>
  cloudflared tunnel route dns rpi-adguard "$1.nicolasfalesy.com"

  # 3. Restart the service to apply config.yml changes
  sudo systemctl restart cloudflared

  echo "🚀 Route created and cloudflared restarted for $1.nicolasfalesy.com"
}

###############################################################################
# COMMAND STATUS INDICATORS
###############################################################################

# Red error message when a command is not found
command_not_found_handler() {
    printf '\033[0;31m%s\033[0m\n' "command not found: $1" >&2
    return 127
}

###############################################################################
# PROMPT & SHELL INIT (must be last)
###############################################################################
command -v starship &>/dev/null && eval "$(starship init zsh)"
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"
