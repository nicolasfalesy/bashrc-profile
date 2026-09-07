#!/usr/bin/env bash
# profiles/pi.sh — Raspberry Pi (Raspberry Pi OS / Debian, headless, docker host).

# wt — live temperature + throttle flags (vcgencmd from raspi-utils).
alias wt='watch -n 1 "vcgencmd measure_temp && vcgencmd get_throttled"'

# temp — CPU temperature and a decoded get_throttled bitfield.
temp() {
    local t raw
    if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
        read -r t < /sys/class/thermal/thermal_zone0/temp
        printf 'CPU temp: %d.%d°C\n' $(( t / 1000 )) $(( t % 1000 / 100 ))
    fi
    hash vcgencmd 2>/dev/null || return 0
    raw=$(vcgencmd get_throttled 2>/dev/null); raw=${raw#throttled=}
    [[ -n $raw ]] || return 0
    local v=$(( raw ))
    if (( v == 0 )); then echo "Throttling: none (0x0) ✅"; return 0; fi
    printf 'Throttling: %s\n' "$raw"
    (( v & (1<<0)  )) && echo "  ⚠️  under-voltage NOW"
    (( v & (1<<1)  )) && echo "  ⚠️  ARM frequency capped NOW"
    (( v & (1<<2)  )) && echo "  ⚠️  throttled NOW"
    (( v & (1<<3)  )) && echo "  ⚠️  soft temperature limit active NOW"
    (( v & (1<<16) )) && echo "  •  under-voltage has occurred since boot"
    (( v & (1<<17) )) && echo "  •  ARM frequency cap has occurred since boot"
    (( v & (1<<18) )) && echo "  •  throttling has occurred since boot"
    (( v & (1<<19) )) && echo "  •  soft temperature limit has occurred since boot"
    return 0
}

# Extra lines for `sys`.
_sys_extra() {
    hash vcgencmd 2>/dev/null || return 0
    local raw; raw=$(vcgencmd get_throttled 2>/dev/null); raw=${raw#throttled=}
    if [[ $raw == 0x0 ]]; then printf '\033[0;32mThrottle:\033[0m none\n'
    else printf '\033[0;32mThrottle:\033[0m \033[1;33m%s\033[0m (run temp to decode)\n' "$raw"; fi
}

# cloud <subdomain> — add a Cloudflare tunnel DNS route and restart cloudflared.
# CF_TUNNEL and CF_DOMAIN come from ~/.bashrc.local.
cloud() {
    case ${1-} in
        -h|--help|'')
            cat <<'HELP'
Publish a new subdomain through the Cloudflare tunnel on this Pi.

Usage: cloud <subdomain>          e.g. cloud grafana → grafana.$CF_DOMAIN

Steps: opens /etc/cloudflared/config.yml for you to add the ingress rule,
adds the DNS route (cloudflared tunnel route dns $CF_TUNNEL <host>),
then restarts the cloudflared service.
Needs CF_TUNNEL and CF_DOMAIN in ~/.bashrc.local (bt local).
HELP
            return 0 ;;
    esac
    hash cloudflared 2>/dev/null || { echo "cloud: cloudflared not installed" >&2; return 1; }
    [[ -n ${CF_TUNNEL-} && -n ${CF_DOMAIN-} ]] || { echo "cloud: set CF_TUNNEL and CF_DOMAIN in ~/.bashrc.local" >&2; return 1; }
    local host="$1.$CF_DOMAIN"
    sudo "$EDITOR" /etc/cloudflared/config.yml
    cloudflared tunnel route dns "$CF_TUNNEL" "$host" || return
    sudo systemctl restart cloudflared && echo "🚀 $host routed through tunnel '$CF_TUNNEL'; cloudflared restarted"
}
