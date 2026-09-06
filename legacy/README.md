# legacy/

The single-file configs that predate the modular layout. Kept for reference only;
nothing sources them and `install.sh` never installs them.

| File | Was | Replaced by |
|------|-----|-------------|
| `uw_bashrc` | bashrc for the UW student servers | `profiles/uw.sh` + `themes/waterloo-gold.toml` (`install.sh --profile uw`) |
| `zshrc` | zsh config used on TrueNAS while its login shell was zsh (this is the last live copy, 6 Sep 2026; zsh and its plugins were removed from the box that day) | the NAS now runs bash: `profiles/nas.sh` (`install.sh --profile nas`) |

The old `shell_functions` file is gone: its C toolchain is `lib/dev.sh`, the rest is
spread over `lib/*.sh` (see `docs/AUDIT.md` for what was dropped and why).
