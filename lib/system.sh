#!/usr/bin/env bash
# lib/system.sh — processes, ports, network, status, tmux, Minecraft RCON.

# sys — one-screen system status. Profiles add lines via _sys_extra().
sys() {
    local G='\033[0;32m' B='\033[0;34m' Y='\033[1;33m' R='\033[0;31m' N='\033[0m'
    echo -e "${B}--- $(hostname) ---${N}"

    # CPU: real delta over 0.5 s from /proc/stat
    local _ u1 n1 s1 i1 w1 q1 sq1 u2 n2 s2 i2 w2 q2 sq2
    read -r _ u1 n1 s1 i1 w1 q1 sq1 _ < /proc/stat
    sleep 0.5
    read -r _ u2 n2 s2 i2 w2 q2 sq2 _ < /proc/stat
    local busy=$(( (u2+n2+s2+q2+sq2) - (u1+n1+s1+q1+sq1) ))
    local total=$(( busy + (i2+w2) - (i1+w1) ))
    local cpu10=$(( total > 0 ? busy * 1000 / total : 0 ))   # tenths of a percent
    local col=$G; (( cpu10 > 700 )) && col=$Y; (( cpu10 > 900 )) && col=$R
    printf "${G}CPU:${N}      ${col}%d.%d%%${N}" $(( cpu10 / 10 )) $(( cpu10 % 10 ))
    local l1 l5 l15
    read -r l1 l5 l15 _ < /proc/loadavg
    printf '   load %s %s %s  (%d cores)\n' "$l1" "$l5" "$l15" "$(nproc)"

    # Memory from /proc/meminfo (kB)
    local k v mt=0 ma=0
    while read -r k v _; do
        case $k in MemTotal:) mt=$v ;; MemAvailable:) ma=$v ;; esac
    done < /proc/meminfo
    local used=$(( mt - ma ))
    printf "${G}Memory:${N}   %d.%d / %d.%d GiB (%d%%)\n" \
        $(( used / 1048576 )) $(( used % 1048576 * 10 / 1048576 )) \
        $(( mt / 1048576 ))   $(( mt % 1048576 * 10 / 1048576 )) \
        $(( mt > 0 ? used * 100 / mt : 0 ))

    # Root disk
    printf "${G}Disk /:${N}   %s\n" "$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"

    # Primary interface + IP
    local dev src
    read -r dev src < <(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev")d=$(i+1); if($i=="src")s=$(i+1)}; print d, s}')
    printf "${G}Network:${N}  %s %s\n" "${src:-?}" "${dev:+($dev)}"

    # Temperature: a CPU sensor from hwmon first (coretemp = Intel, k10temp = AMD,
    # cpu_thermal = Pi), thermal_zone0 as the fallback. thermal_zone0 alone is the
    # ACPI/board reading on many x86 boards — it said 16 °C on the NAS while the
    # CPU was at 68 °C.
    local t='' h hn
    for h in /sys/class/hwmon/hwmon*; do
        [[ -r $h/name && -r $h/temp1_input ]] || continue
        read -r hn < "$h/name"
        case $hn in coretemp|k10temp|zenpower|cpu_thermal|cpu-thermal) read -r t < "$h/temp1_input"; break ;; esac
    done
    [[ -z $t && -r /sys/class/thermal/thermal_zone0/temp ]] && read -r t < /sys/class/thermal/thermal_zone0/temp
    if [[ -n $t ]]; then
        col=$G; (( t > 70000 )) && col=$Y; (( t > 80000 )) && col=$R
        printf "${G}Temp:${N}     ${col}%d.%d°C${N}${hn:+  ($hn)}\n" $(( t / 1000 )) $(( t % 1000 / 100 ))
    fi

    # Battery (laptops)
    if [[ -r /sys/class/power_supply/BAT0/capacity ]]; then
        local cap st
        read -r cap < /sys/class/power_supply/BAT0/capacity
        read -r st  < /sys/class/power_supply/BAT0/status
        printf "${Y}Battery:${N}  %s%% (%s)\n" "$cap" "$st"
    fi

    printf "${G}Uptime:${N}   %s\n" "$(uptime -p 2>/dev/null | sed 's/^up //')"

    # Profile hook (Pi: throttling, NAS: pool health)
    declare -F _sys_extra >/dev/null && _sys_extra
    return 0
}

# psg <pattern>... — search processes (header + coloured matches + count).
psg() {
    case ${1-} in
        -h|--help|'')
            echo "Usage: psg <pattern> [pattern...]   — search running processes"; return 0 ;;
    esac
    local p out n total=0
    for p in "$@"; do
        echo -e "\033[0;34m--- $p ---\033[0m"
        out=$(command ps aux | command grep -v ' grep ' | command grep -i --color=always -- "$p")
        n=$( [[ -n $out ]] && wc -l <<< "$out" || echo 0 )
        command ps aux | head -1
        [[ -n $out ]] && echo "$out"
        echo -e "\033[0;32m$n match(es)\033[0m"; echo
        (( total += n ))
    done
    (( $# > 1 )) && echo -e "\033[0;34mTotal: $total match(es)\033[0m"
    return 0
}

# port [PORT...] — what's listening (all, or on specific ports).
port() {
    case ${1-} in
        -h|--help)
            echo "Usage: port            list everything listening"
            echo "       port 80 443    only these ports"; return 0 ;;
        ''|-a|--all)
            echo -e "\033[0;34m--- Listening ---\033[0m"
            sudo ss -tulnp; return ;;
    esac
    local p
    for p in "$@"; do
        [[ $p =~ ^[0-9]+$ ]] || { echo "port: '$p' is not a port number" >&2; continue; }
        echo -e "\033[0;34m--- Port $p ---\033[0m"
        sudo ss -tulnp "sport = :$p"; echo
    done
}

# killport <port>... — kill whatever listens on a port (TCP or UDP).
killport() {
    case ${1-} in
        -h|--help|'') echo "Usage: killport <port> [port...]"; return 0 ;;
    esac
    local p pid name
    for p in "$@"; do
        [[ $p =~ ^[0-9]+$ ]] || { echo "killport: '$p' is not a port number" >&2; continue; }
        pid=$(sudo ss -tulnpH "sport = :$p" 2>/dev/null | command grep -oP 'pid=\K[0-9]+' | head -1)
        if [[ -z $pid ]]; then echo "No process on port $p"; continue; fi
        name=$(command ps -p "$pid" -o comm= 2>/dev/null)
        sudo kill "$pid" && echo "Killed $name (PID $pid) on port $p"
    done
}

# topp [-c|-m] [count] — top processes by CPU (default) or memory.
topp() {
    local sort='-%cpu' label=CPU count=10
    case ${1-} in
        -h|--help) echo "Usage: topp [-c|--cpu | -m|--mem] [count]"; return 0 ;;
        -m|--mem) sort='-%mem' label=memory; shift ;;
        -c|--cpu) shift ;;
    esac
    [[ ${1-} =~ ^[0-9]+$ ]] && count=$1
    echo -e "\033[0;34m--- Top $count by $label ---\033[0m"
    command ps aux --sort="$sort" | head -n $(( count + 1 ))
}
_topp_completions() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    [[ $cur == -* ]] && COMPREPLY=($(compgen -W '-h --help -c --cpu -m --mem' -- "$cur"))
}
complete -F _topp_completions topp

# myip — local IP (on the default-route interface) + public IP.
myip() {
    local dev src
    read -r dev src < <(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev")d=$(i+1); if($i=="src")s=$(i+1)}; print d, s}')
    printf 'Internal IP: %s %s\n' "${src:-unknown}" "${dev:+($dev)}"
    printf 'External IP: '; curl -s -4 --max-time 5 https://ifconfig.me/ip || echo "unavailable"; echo
}
alias whatsmyip='myip'
alias whatismyip='myip'
pubip() { curl -s -4 --max-time 5 https://ifconfig.me/ip; echo; }

# weather [-s] [location] — wttr.in report (WEATHER_LOCATION sets the default).
weather() {
    local short=0
    case ${1-} in
        -h|--help)
            echo "Usage: weather [-s] [location]   — default location: \$WEATHER_LOCATION"; return 0 ;;
        -s) short=1; shift ;;
    esac
    local loc=${1:-${WEATHER_LOCATION:-}}
    loc=${loc// /+}
    if (( short )); then curl -s --max-time 10 "wttr.in/${loc}?format=3"
    else curl -s --max-time 10 "wttr.in/${loc}" | head -40; fi
}

# t — tmux session manager.  t dev | t -l | t -p dev | t -k
t() {
    command -v tmux >/dev/null 2>&1 || { echo "t: tmux is not installed (run prereqs)" >&2; return 1; }
    case ${1-} in
        -h|--help|'')
            cat <<'HELP'
tmux session manager.

Usage: t <name>        create or attach to a session
       t -a <name>     attach only
       t -p <name>     kill (purge) a session
       t -l            list sessions
       t -k            kill the server (all sessions)
HELP
            return 0 ;;
        -l) tmux list-sessions 2>/dev/null || echo "No tmux sessions." ;;
        -k) tmux kill-server 2>/dev/null && echo "All sessions killed." || echo "No tmux server running." ;;
        -a) [[ -n ${2-} ]] || { echo "t: session name required" >&2; return 1; }
            tmux attach-session -t "$2" ;;
        -p) [[ -n ${2-} ]] || { echo "t: session name required" >&2; return 1; }
            tmux kill-session -t "$2" && echo "Killed session '$2'" ;;
        -n) shift ;&
        *)  if tmux has-session -t "$1" 2>/dev/null; then tmux attach-session -t "$1"
            else tmux new-session -s "$1"; fi ;;
    esac
}
_t_completions() {
    local cur=${COMP_WORDS[COMP_CWORD]} sessions
    sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)
    if [[ $cur == -* ]]; then COMPREPLY=($(compgen -W '-h -l -k -a -p -n' -- "$cur"))
    else COMPREPLY=($(compgen -W "$sessions" -- "$cur")); fi
}
complete -F _t_completions t

# rcon <command...> — send a command to a Minecraft server (mcrcon).
# RCON_IP / RCON_PORT / RCON_PASS come from ~/.bashrc.local.
rcon() {
    local G='\033[0;32m' R='\033[0;31m' N='\033[0m'
    case ${1-} in
        -h|--help|'')
            cat <<'HELP'
Send a command to a Minecraft server via RCON.

Usage: rcon <command> [args...]      (alias: rc)
Needs RCON_IP, RCON_PORT, RCON_PASS in ~/.bashrc.local and mcrcon installed
(install.sh --with-mcrcon).

Examples: rcon list | rcon say Hello | rcon whitelist add Steve
HELP
            return 0 ;;
    esac
    command -v mcrcon >/dev/null 2>&1 || { echo -e "${R}rcon: mcrcon not found — run: install.sh --with-mcrcon${N}" >&2; return 1; }
    [[ -n ${RCON_PASS-} ]] || { echo -e "${R}rcon: RCON_PASS is not set (bt local)${N}" >&2; return 1; }
    local out rc
    out=$(mcrcon -H "${RCON_IP:-127.0.0.1}" -P "${RCON_PORT:-25575}" -p "$RCON_PASS" -w 5 "$*" 2>&1); rc=$?
    if (( rc == 0 )); then echo -e "${G}RCON ok${N}"; [[ -n $out ]] && echo "$out"
    else echo -e "${R}RCON failed (exit $rc)${N}" >&2; [[ -n $out ]] && echo "$out"; return 1; fi
}
alias rc='rcon'
_rcon_completions() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    COMPREPLY=($(compgen -W 'advancement ban ban-ip banlist clear clone damage data datapack
        debug defaultgamemode deop difficulty effect enchant execute experience fill fillbiome
        forceload function gamemode gamerule give help item jfr kick kill list locate loot me msg
        op pardon pardon-ip particle perf place playsound publish random recipe reload return ride
        run say schedule scoreboard seed setblock setidletimeout setworldspawn spawnpoint spectate
        spreadplayers stop stopsound summon tag team teleport tell tellraw tick time title tm tp
        trigger weather whitelist worldborder xp' -- "$cur"))
}
complete -F _rcon_completions rcon rc
