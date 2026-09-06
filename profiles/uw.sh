#!/usr/bin/env bash
# profiles/uw.sh — University of Waterloo CS student servers
# (ubuntu2404-0xx.student.cs.uwaterloo.ca). No root, no apt, no trash-cli.
#
# Everything the profile needs lives in the home directory (install.sh --profile uw
# puts starship, fzf and ble.sh under ~/.local; drop an nvim release into ~/.local
# too). The installer links themes/waterloo-gold.toml — the "Waterloo Gold" theme —
# instead of themes/aurora.toml. The C helpers (ru/run/rut/mkt) come from lib/dev.sh as usual.

_path_prepend "$HOME/bin"

unalias apt ni np ns nu nclean svim 2>/dev/null   # nothing here runs as root
alias rm='rm -iv'                                 # no trash-cli: confirm every delete
