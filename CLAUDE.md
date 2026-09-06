# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

A modular bash profile (`~/.bashrc` → `bashrc` → `lib/*.sh` → `profiles/<machine>.sh`
→ `~/.bashrc.local` → `lib/prompt.sh`) plus `install.sh`, which detects the machine
(pi / nas / desktop / server), installs that profile's dependencies and links the files.
Read `docs/ARCHITECTURE.md` first; `docs/FEATURES.md` is the command reference;
`docs/AUDIT.md` records what was removed/renamed and why.

## Rules of the road

- **Load order matters.** `lib/core.sh` first, `lib/prompt.sh` last. Aliases must be
  defined before any function body that uses them is *parsed*; that is why `ll` is a
  function, not an alias, and why functions call `command ls` / `command grep` / `command du`.
- **Never shadow coreutils with unrelated commands.** `du`, `dd`, `ps` were shadowed
  before and broke other aliases (see AUDIT.md). Docker Compose aliases are `dc*`.
- **No secrets, hostnames or passwords in tracked files.** They go in
  `~/.bashrc.local` (template: `bashrc.local.example`). Profiles read them from
  environment variables (`RCON_PASS`, `CF_TUNNEL`, `ZPOOL`, …).
- **Guard tool-dependent aliases** with `hash <tool> 2>/dev/null` so every file is safe
  on every machine (the NAS has no apt, trash-cli or nvim).
- **New dependency ⇒ update `install.sh`** (`CORE_PKGS` / `PI_PKGS` / `DESKTOP_PKGS` /
  `DEV_PKGS`, or a `install_*_local` fallback) and `docs/FEATURES.md`.
- **Keep startup fast.** No subprocesses at load time in the common path. Use
  `hash`/`BASH_CMDS` instead of `$(command -v …)`, cache `X init` output via
  `_bashrc_cached_init`, and lazy-load large modules with `_bashrc_lazy`.
- Every function takes `-h`/`--help`. Add a `_<name>_completions` + `complete -F` when
  it has options.

## Testing

```bash
bash -n bashrc lib/*.sh profiles/*.sh install.sh
shellcheck -s bash -e SC1090,SC1091,SC2016,SC2207,SC2034,SC2139 bashrc lib/*.sh profiles/*.sh install.sh

# start a real interactive shell with a given profile, without touching ~/.bashrc
BASHRC_PROFILE=nas bash --rcfile ./bashrc -i
BASHRC_TIMING=1 BASHRC_PROFILE=pi bash --rcfile ./bashrc -ic exit   # startup time

bash install.sh --dry-run --profile pi
```

Interactive-only shells: `bash -c` never loads the profile (by design), so test with `-i`.
