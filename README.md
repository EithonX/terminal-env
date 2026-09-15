# Terminal Environment

A managed terminal environment for Windows, macOS, and Ubuntu/Debian.

PowerShell 7 or Zsh, with managed tools, history, completion, diagnostics, updates, and recovery.

## Install

The bootstrap acquires only the prerequisites needed to fetch the repository, then hands off to the transactional installer.

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

The full installer follows `Preflight → Plan → Apply → Verify → Finish`. Local conflicts and unsupported prerequisites fail during preflight before package provisioning. The transaction is marked complete only after the managed configuration passes doctor verification; non-minimal installs also verify the pinned dependency state. A verification failure restores the managed files captured before the install.

Unix installs support `--format human|plain|json`, `--color auto|always|never`, `--quiet`, and `--verbose`. The PowerShell installer exposes the corresponding `-Format`, `-Color`, `-Quiet`, and `-Verbose` parameters. `--dry-run` / `-DryRun` stays read-only, and JSON result output is kept separate from child-tool progress.

## What you get

- **Windows:** PowerShell 7 + PSReadLine + Atuin + Windows Terminal.
- **Linux/macOS:** Zsh + smart history/completion suggestions + Atuin + fzf-tab.
- **Everywhere:** Oh My Posh, fzf, zoxide, a restrained theme, diagnostics, rollback, and Git-backed updates.
- Core commands stay core commands. `ls` is still `ls`; `rm` is still `rm`.
- Shell startup does not pull Git, install packages, or phone home.
- Optional pieces fail open. A missing prompt or fuzzy finder should never brick your shell.

## Everyday commands

```sh
terminal doctor
terminal update --check
terminal deps status
terminal context
terminal backup
terminal rollback --dry-run
```

`terminal --help` is the primary command surface. The existing `terminal-doctor`, `terminal-update`, `terminal-deps`, `terminal-context`, `terminal-backup`, and `terminal-rollback` names remain compatibility shims. `terminal deps check` is an alias of `terminal deps status`. `terminal version` reports the installed source revision when the managed source is Git-backed rather than inventing a separate release version.

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
terminal update --check
terminal update
terminal deps status
terminal deps sync
```

The same long options work on Unix and PowerShell. Native PowerShell forms such as `-Check` remain accepted.

`terminal update` fast-forwards the installed Git source and applies config only. It refuses non-fast-forward source movement and local modifications, and restores the previously applied revision/configuration if validation or apply fails. `terminal update --format plain|json` keeps result data separate from Git/validation progress. `terminal deps sync` reconciles third-party tools to the versions pinned in `versions.env`.

`terminal deps status` is exception-oriented like doctor: a healthy environment collapses to one line, while mismatches expand into `Attention`. Use `--verbose`, `--format plain`, or `--format json` when you need the complete dependency comparison.

## Project context

Runtime information appears in the prompt only when the project provides authoritative version or compatibility metadata. Discovery stops at the Git repository boundary; outside Git it stays in the current directory. Conflicting selectors are reported instead of silently choosing one.

Inspect the resolved values and their sources with:

```sh
terminal context
terminal context --format json
```

Node, Python, Go, and Rust context distinguish project selectors and compatibility constraints from the executable that is active on `PATH`. Prompt resolution is local-only and does not download or install toolchains.

## Diagnostics

`terminal doctor` is exception-oriented by default: a healthy run collapses to a short summary, while warnings and failures expand into an `Attention` section. Use `--verbose` when you want every successful check.

```sh
terminal doctor
terminal doctor --verbose
terminal doctor --format plain
terminal doctor --format json
```

Human output uses color only on an interactive terminal by default and respects `NO_COLOR` and `TERM=dumb`. `--color auto|always|never` makes the choice explicit. Plain and JSON output never contain ANSI styling.

## Backups and recovery

```sh
terminal backup
terminal backup --with-history
terminal rollback --dry-run
terminal rollback
```

`terminal backup` keeps its original script-friendly contract: without `--format`, stdout is only the created archive path. Use `--format human|plain|json` for an explicit presentation contract. Manual backups are stored separately from installer transaction snapshots and are never auto-pruned.

Rollback shows the current and target revisions before mutation and asks for confirmation. Noninteractive rollback requires `--yes`; `--dry-run` only shows the plan. A failed rollback attempts to restore the revision/configuration that was active before the command started. If the target changes `versions.env`, the source rollback completes but marks dependencies for a separate `terminal deps sync`.

Uninstall is intentionally kept outside the everyday `terminal` command tree. Run it from the managed source so the recovery script remains available even if managed shell commands are damaged.

macOS / Linux:

```sh
~/.local/share/terminal-env/source/uninstall.sh --dry-run
~/.local/share/terminal-env/source/uninstall.sh
```

Windows:

```powershell
pwsh -File "$HOME\.local\share\terminal-env\source\uninstall.ps1" --dry-run
pwsh -File "$HOME\.local\share\terminal-env\source\uninstall.ps1"
```

Uninstall shows its plan before mutation and requires confirmation. Redirected/noninteractive use requires `--yes`. The original pre-install snapshot is restored by default; if that restore point is missing or intentionally unwanted, `--no-restore` is an explicit destructive override. System packages and history databases are preserved.

## Profiles

- `workstation` — full interactive setup and fonts.
- `server` — SSH/VPS setup with tmux; no local font install.
- `minimal` — small recovery-friendly shell foundation.

## Platforms

- **Windows 10/11:** WinGet + PowerShell 7 + Windows Terminal.
- **macOS:** Homebrew; Ghostty is installed as a cask.
- **Ubuntu/Debian:** `apt`. Ghostty is optional and only installed when the distro provides it; the shell works in any terminal.

Run `terminal doctor` after installation if anything looks wrong.

## Documentation

- [Architecture](ARCHITECTURE.md)
- [Security](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

MIT licensed.
