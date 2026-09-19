#!/usr/bin/env bash
# profiles/desktop.sh — laptop / desktop with a display (Ubuntu / Debian).

export TERMINAL=/usr/bin/alacritty
export QT_QPA_PLATFORMTHEME=qt5ct
export NOTES_FILE="${NOTES_FILE:-$HOME/Nextcloud/quick-notes.txt}"

alias kt='$EDITOR ~/.config/alacritty/keybinds.toml'
alias notes='$EDITOR "$HOME/Nextcloud/constant notes.txt"'

# Clipboard (cpy / pst) moved to lib/clipboard.sh — every profile has it now, and
# it picks wl-copy/xclip here and OSC 52 over SSH by itself.

# ── vpn — WireGuard wg0 ──────────────────────────────────────────────────────
vpn() {
    case ${1-} in
        -h|--help)
            echo "Usage: vpn        connect wg0"
            echo "       vpn -s     status"
            echo "       vpn -d     disconnect"; return 0 ;;
        -s) sudo wg show ;;
        -d|-r|-p) sudo wg-quick down wg0 ;;
        *)  echo "Connecting… 🔒"
            # userspace flag works around a wg-quick stat bug on Ubuntu ARM
            sudo WG_QUICK_USERSPACE_IMPLEMENTATION=bash wg-quick up wg0 && echo "VPN is up ✅" ;;
    esac
}

# ── note — quick scratchpad (NOTES_FILE) ─────────────────────────────────────
note() {
    case ${1-} in
        -h|--help|'')
            echo "Usage: note <text>  |  note -l (list)  |  note -e (edit)  |  note -c (clear)"
            echo "File: $NOTES_FILE"; return 0 ;;
        -l|--list)  [[ -f $NOTES_FILE ]] && cat -n "$NOTES_FILE" || echo "(no notes yet)" ;;
        -e|--edit)  "$EDITOR" "$NOTES_FILE" ;;
        -c|--clear) local ok; read -rp "Clear all notes? [y/N] " ok
                    [[ $ok =~ ^[Yy]$ ]] && : > "$NOTES_FILE" && echo "Notes cleared." ;;
        *)  command mkdir -p "$(dirname "$NOTES_FILE")"
            echo "[$(date '+%Y-%m-%d %H:%M')] $*" >> "$NOTES_FILE" && echo "Note saved." ;;
    esac
}

# ── apps / install_app — ~/.local/share/applications helpers ─────────────────
apps() {
    case ${1-} in
        -h|--help) echo "Usage: apps        cd to ~/.local/share/applications"
                   echo "       apps -u     update desktop database"; return 0 ;;
        -u) update-desktop-database ~/.local/share/applications && echo "Desktop database updated ✅" ;;
        *)  cd ~/.local/share/applications || return ;;
    esac
}
install_app() {
    local dir="$HOME/.local/share/applications"
    case ${1-} in
        -h|--help|'')
            echo "Usage: install_app <file.desktop>   symlink a .desktop file into $dir"
            echo "       install_app -l [query]        list installed local apps"; return 0 ;;
        -l) command ls "$dir" | command grep '\.desktop$' | sed 's/\.desktop$//' | command grep -i -- "${2:-.}" ;;
        *)  local src; src=$(realpath -- "$1" 2>/dev/null)
            [[ -f $src && $src == *.desktop ]] || { echo "install_app: not a .desktop file" >&2; return 1; }
            ln -sf "$src" "$dir/$(basename "$src")" && echo "✅ Linked $(basename "$src")" ;;
    esac
}

# ── at — Alacritty theme switcher ────────────────────────────────────────────
at() {
    local themes="$HOME/.config/alacritty/themes/themes" active="$HOME/.config/alacritty/themes/themes/active_theme.toml"
    case ${1-} in
        -h|--help) echo "Usage: at            edit alacritty.toml"
                   echo "       at -l [q]     list themes"
                   echo "       at -t <name>  activate a theme"; return 0 ;;
        -l) command ls "$themes" | sed 's/\.toml$//' | command grep -i -- "${2:-.}" ;;
        -t) [[ -n ${2-} ]] || { echo "at: theme name required" >&2; return 1; }
            local target="$themes/${2%.toml}.toml"
            [[ -f $target ]] || { echo "at: theme '$2' not found (at -l)" >&2; return 1; }
            ln -sf "$target" "$active" && echo "✅ Theme: ${2%.toml}" ;;
        *)  "$EDITOR" "$HOME/.config/alacritty/alacritty.toml" ;;
    esac
}

# ── grub — update / edit / install theme ─────────────────────────────────────
grub() {
    local themes=/boot/grub/themes
    case ${1-} in
        -h|--help) echo "Usage: grub            update-grub"
                   echo "       grub -e         edit /etc/default/grub"
                   echo "       grub -t <dir>   install a theme dir and select it"
                   echo "       grub -d         cd to $themes"; return 0 ;;
        -e) sudo "$EDITOR" /etc/default/grub ;;
        -d) cd "$themes" || return ;;
        -t) [[ -d ${2-} ]] || { echo "grub: theme directory required" >&2; return 1; }
            local name; name=$(basename "$2")
            sudo cp -r "$2" "$themes/" &&
            sudo sed -i "s|^#\?GRUB_THEME=.*|GRUB_THEME=\"$themes/$name/theme.txt\"|" /etc/default/grub &&
            echo "✅ Theme $name installed" && sudo update-grub ;;
        *)  sudo update-grub ;;
    esac
}
