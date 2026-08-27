# Terminal Environment

A reproducible cross-platform terminal environment built for predictable AI-generated commands, expert interactive use, restrained presentation, and graceful failure.

## Default experience

**Linux/macOS:** Zsh + a context-aware zsh-autosuggestions strategy + Atuin + native completion/zsh-completions + fzf-tab + zsh-syntax-highlighting + fzf + zoxide + Oh My Posh. Server profiles also install tmux.

**Windows:** PowerShell 7 + PSReadLine history prediction + Atuin + fzf + zoxide + the same Oh My Posh theme.

Oh My Posh streaming is enabled at 100 ms. Upstream automatically restarts the renderer and falls back to classic rendering after repeated failures, so the default gets the speed benefit without making prompt rendering a single point of failure.

The default prompt is intentionally single-line and transcript-friendly: current path and Git context stay visible on the same line as the command, which keeps SSH copy/paste, AI troubleshooting, and long scrollback cleaner than a decorative multi-line prompt.

## Install

```sh
./install.sh
```

```powershell
.\install.ps1
```

The default profile is inferred: headless/SSH Linux becomes `server`; desktop Linux/macOS/Windows becomes `workstation`. Override with `--profile server|workstation|minimal` or PowerShell `-Profile`.

Useful flags: `--dry-run`, `--no-shell-change`, `--no-font` and PowerShell equivalents.

## Behavioral contract

- Right: accept complete prediction.
- Ctrl+Right: accept next predicted word.
- Up/Down: deterministic prefix-aware native history traversal.
- Ctrl+R: Atuin deep history; native history remains the fallback.
- Tab: actual shell completion; fzf-tab is presentation only.
- Shift+Tab: previous completion candidate.
- Ctrl+T: fuzzy file insertion when fzf is present.
- Alt+C: fuzzy directory navigation when fzf is present.
- Esc Esc: sudo toggle only for non-root Unix users with sudo.
- Core commands are never replaced by lookalikes: `ls` and `grep` receive color-only interactive aliases, while `l`/`la`/`ll`/`lt` explicitly opt into eza; `cat`, `rm`, `cp`, `mv`, and other core commands retain their native behavior.
- Multiline paste is left in the editable buffer; this setup never intentionally auto-executes pasted commands.

## Operations

- `terminal-doctor`: diagnostics and degraded-mode visibility.
- `terminal-update`: update our GitHub-backed source/config only; `--check` reports availability without applying.
- `terminal-deps`: inspect or sync the external versions pinned by the currently installed source.
- `terminal-backup`: local shell/config snapshot.
- `terminal-rollback`: restore the previously applied Git source/config revision. If its dependency manifest differs, it explicitly asks for `terminal-deps sync`.

Existing shell configuration is backed up before install. Optional integrations are fail-open: missing zsh-autosuggestions means no ghost prediction; missing Atuin means native history; missing fzf means native completion; missing Oh My Posh means a native prompt.

## Repository model

chezmoi owns configuration rendering. The installer owns provisioning and migration. Plugin load files are generated statically during setup/update so opening a shell does not run a plugin manager or perform network access.

Secrets, history databases, SSH host definitions, GPG material, and local machine state are intentionally outside this repository.

## Profiles

| Profile | Intended use | Default additions |
|---|---|---|
| `server` | SSH/VPS/headless Linux | Zsh intelligence stack + tmux; no font/GUI terminal |
| `workstation` | Windows/macOS/Linux desktop | Native terminal renderer + font + full interactive stack |
| `minimal` | Recovery/lightweight Unix environment | Core shell/config only; optional integrations simply stay absent |

The installers choose the profile automatically and are intentionally non-interactive. Explicit flags exist for automation and exceptional machines, not because setup requires a configuration questionnaire.

## Update and rollback

Nothing updates during shell startup. Source and dependency updates are deliberately separate:

- `terminal-update --check` fetches metadata and reports whether the configured Git upstream has new commits.
- `terminal-update` fast-forwards the installed Git source, runs smoke tests, applies only our managed configuration, and records the previous commit for rollback. It does **not** run apt/Homebrew/WinGet or upgrade portable tools.
- If the update changed `versions.env`, a `deps-pending` state is recorded and the command tells you to run `terminal-deps sync`. This prevents external dependency changes from being silently mixed into a repo/config update.
- `terminal-deps status` shows the installed/pinned dependency state. `terminal-deps sync` explicitly reconciles external tools/plugins to the versions declared by the current repo without fetching a newer repo revision.

For automatic GitHub updates, perform the initial install from a normal Git clone. The installer preserves its `.git` metadata and upstream remote inside the managed source, so every later `terminal-update` follows that repository/branch. Archive installs stay intentionally non-updateable until reinstalled once from a clone.

The normal Zsh startup path performs no Git operations and no package-manager work. fzf, zoxide and Atuin integration code is cached/generated during setup where supported.

## Safety model

- Existing managed-path configuration and portable binaries are backed up before first replacement.
- Uninstall restores the original pre-install state by default; OS packages are left alone because their prior ownership cannot be proven.
- Atuin sync and its update checker are off by default.
- Oh My Posh update notices/automatic upgrades are off; repository updates own version changes.
- Native Zsh history honors leading-space history exclusion; zsh-autosuggestions reads that filtered history, while Atuin has its own additional credential-shaped filters.
- Ghostty paste protection is enabled; Windows Terminal keeps its own paste-warning behavior.
- Root gets a restrained but visible prompt treatment, while the sudo-toggle key is disabled for root.
- Optional components fail open instead of preventing a shell from starting.

## Rendering

The visual system is deliberately restrained: graphite-black surface, neutral text, ice-blue primary focus, violet repository/reference context, amber attention, green executable/success state and controlled rose failure. Runtime/tool glyphs are Nerd Font icons, not emoji. The prompt is a compact single-line transcript-friendly form so copied SSH output keeps ordinary terminal context instead of decorative transient markers. Persistent decorative information is avoided and success state stays silent.

The workstation font is Monaspice Neon Nerd Font. Windows Terminal is configured through an additive fragment and a backed-up default-profile edit. Ghostty uses native shell integration, prompt navigation, clipboard protections and the same palette.
The shared prompt is adaptive rather than identical-looking everywhere: local workstations omit machine identity, SSH sessions add only the remote hostname, and root is conveyed by the active prompt accent instead of a permanent `root@host` banner.

## Development

Run:

```sh
./tests/smoke.sh
./install.sh --dry-run --profile server --no-shell-change --no-font
```

CI parses Unix shell files on Ubuntu/macOS and validates the Windows installer with PowerShell on Windows. The repository intentionally contains no secrets, machine-specific SSH hosts, shell history, GPG material, or user identity configuration. Optional per-machine overrides live in `~/.config/terminal-env/local.zsh` or `local.ps1` and are not managed.
