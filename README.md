# Terminal Environment

A fast, opinionated terminal setup for Windows, macOS, and Ubuntu/Debian.

Good defaults, native shells, useful history, real completion, and no giant shell framework.

## What you get

- **Windows:** PowerShell 7 + PSReadLine + Atuin + Windows Terminal.
- **Linux/macOS:** Zsh + smart history/completion suggestions + Atuin + fzf-tab.
- **Everywhere:** Oh My Posh, fzf, zoxide, a restrained theme, diagnostics, rollback, and Git-backed updates.
- Core commands stay core commands. `ls` is still `ls`; `rm` is still `rm`.
- Shell startup does not pull Git, install packages, or phone home.
- Optional pieces fail open. A missing prompt or fuzzy finder should never brick your shell.

## Install

One command. The bootstrap acquires only the prerequisites needed to fetch the repository, then hands off to the normal transactional installer.

### Windows 10/11

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/EithonX/terminal-env/master/bootstrap.ps1 | iex
```

Windows 10 workstation installs require version 2004 (build 19041) or newer because of Windows Terminal. Windows 11 Arm64 is supported through x64 application emulation. The bootstrap can repair WinGet when necessary, installs Git only when missing, then the main installer provisions PowerShell 7, Windows Terminal, pinned tools, fonts, configuration, backups, and recovery state. It does not permanently change execution policy.

VS Code renders its integrated terminal separately from Windows Terminal. If prompt icons are missing there, set `terminal.integrated.fontFamily` to `'MonaspiceNe Nerd Font', monospace`.

### macOS

```sh
curl -fsSL https://raw.githubusercontent.com/EithonX/terminal-env/master/bootstrap.sh | bash
```

If Homebrew is missing, the bootstrap obtains it through Homebrew's official installer, then installs Git when needed and continues with the normal workstation installation.

### Ubuntu / Debian

```sh
curl -fsSL https://raw.githubusercontent.com/EithonX/terminal-env/master/bootstrap.sh | bash
```

SSH/headless Linux selects the `server` profile automatically. Desktop Linux selects `workstation`. Do **not** run the bootstrap or installer with `sudo`; they request elevation only for system packages.

Set `TERMINAL_ENV_PROFILE`, `TERMINAL_ENV_BRANCH`, or `TERMINAL_ENV_REPO` before the bootstrap when you need a non-default profile, branch, fork, or mirror. The local bootstrap scripts also accept normal installer options.

### Inspect first

If you do not want to execute a network-fetched bootstrap directly, download it for inspection or clone the repository and run `install.ps1` / `install.sh` locally.

## Daily keys

| Key | Action |
|---|---|
| `←` / `→` | Move the cursor; at end-of-line `→` accepts the full inline suggestion |
| `Ctrl+←` / `Ctrl+→` | Move by word; at end-of-line `Ctrl+→` accepts the next suggested word |
| `↑` / `↓` | Prefix-aware shell history |
| `Ctrl+R` | Atuin history search |
| `Tab` | Completion through fzf-tab on Zsh |
| `Ctrl+T` | Fuzzy file insertion |
| `Alt+C` | Fuzzy directory navigation |

Zsh inline suggestions use both command history and the real Zsh completion system, so unseen files, folders, Git refs, flags, and service names can be suggested when their completer exposes them.

## Updates

Repository changes and dependency changes are deliberately separate:

```sh
terminal-update --check
terminal-update
terminal-deps status
terminal-deps sync
```

The same long options work on Unix and PowerShell. Native PowerShell forms such as `-Check` remain accepted.

`terminal-update` fast-forwards the installed Git source and applies config only. `terminal-deps sync` reconciles third-party tools to the versions pinned in `versions.env`.

## Profiles

- `workstation` — full interactive setup and fonts.
- `server` — SSH/VPS setup with tmux; no local font install.
- `minimal` — small recovery-friendly shell foundation.

## Platforms

- **Windows 10/11:** WinGet + PowerShell 7 + Windows Terminal.
- **macOS:** Homebrew; Ghostty is installed as a cask.
- **Ubuntu/Debian:** `apt`. Ghostty is optional and only installed when the distro provides it; the shell works in any terminal.

Run `terminal-doctor` after installation if anything looks wrong.

## Project notes

- [Architecture](ARCHITECTURE.md)
- [Security](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

MIT licensed.
