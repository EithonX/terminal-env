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

Clone the repository, then run the installer from the clone.

### Windows 10/11

Open PowerShell 7:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\install.ps1 -Profile workstation
```

Requires WinGet. The installer creates a **Terminal Environment** Windows Terminal profile that runs `pwsh.exe` (PowerShell 7).

### macOS

Homebrew is required once for system packages:

```sh
bash ./install.sh
```

The workstation profile uses the system Zsh and installs Ghostty through Homebrew.

### Ubuntu / Debian

```sh
bash ./install.sh
```

SSH/headless Linux selects the `server` profile automatically. Desktop Linux selects `workstation`. Do **not** run the installer with `sudo`; it requests sudo only when system packages need it.

## Daily keys

| Key | Action |
|---|---|
| `→` | Accept the full inline suggestion |
| `Ctrl+→` | Accept the next suggested word |
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

PowerShell uses the same commands with `-Check` instead of `--check`.

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
