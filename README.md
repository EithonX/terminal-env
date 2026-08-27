# Terminal Environment

A reproducible cross-platform terminal environment built for predictable AI-generated commands, expert interactive use, restrained presentation, and graceful failure.

## Default experience

**Linux/macOS:** Zsh + Deja + Atuin + native completion/zsh-completions + fzf-tab + zsh-syntax-highlighting + fzf + zoxide + Oh My Posh. Server profiles also install tmux.

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
- `terminal-update`: explicit update path; nothing silently auto-updates in the background.
- `terminal-backup`: local shell/config snapshot.
- `terminal-rollback`: restore the previously applied Git revision and its pinned managed binaries/configuration.

Existing shell configuration is backed up before install. Optional integrations are fail-open: missing Deja means no prediction; missing Atuin means native history; missing fzf means native completion; missing Oh My Posh means a native prompt.

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

Nothing updates during shell startup. `terminal-update` pulls a Git-backed installed source, runs smoke tests before applying it, rebuilds static integrations, applies the new target state, and runs diagnostics. Updates record the prior commit for `terminal-rollback` on both Unix and Windows, and re-provision pinned binaries when rolling back.

The normal Zsh startup path performs no Git operations and no package-manager work. fzf, zoxide, Atuin and Deja integration code is cached/generated during setup where supported.

## Safety model

- Existing managed-path configuration and portable binaries are backed up before first replacement.
- Uninstall restores the original pre-install state by default; OS packages are left alone because their prior ownership cannot be proven.
- Atuin sync and its update checker are off by default.
- Oh My Posh update notices/automatic upgrades are off; repository updates own version changes.
- Deja and native Zsh history honor leading-space history exclusion; additional credential-shaped command filters are configured for both Zsh/Deja and Atuin.
- Ghostty paste protection is enabled; Windows Terminal keeps its own paste-warning behavior.
- Root gets a restrained but visible prompt treatment, while the sudo-toggle key is disabled for root.
- Optional components fail open instead of preventing a shell from starting.

## Rendering

The visual system is deliberately restrained: graphite-black surface, neutral text, ice-blue primary focus, violet repository/reference context, amber attention, green executable/success state and controlled rose failure. Runtime/tool glyphs are Nerd Font icons, not emoji. The active prompt is a two-line structural frame; executed commands collapse to a muted dot instead of reusing the active prompt marker. Persistent decorative information is avoided; runtime segments appear contextually, command duration appears only after two seconds, and success status stays silent.

The workstation font is Monaspice Neon Nerd Font. Windows Terminal is configured through an additive fragment and a backed-up default-profile edit. Ghostty uses native shell integration, prompt navigation, clipboard protections and the same palette.
The shared prompt is adaptive rather than identical-looking everywhere: local workstations omit machine identity, SSH sessions add only the remote hostname, and root is conveyed by the active prompt accent instead of a permanent `root@host` banner.

## Development

Run:

```sh
./tests/smoke.sh
./install.sh --dry-run --profile server --no-shell-change --no-font
```

CI parses Unix shell files on Ubuntu/macOS and validates the Windows installer with PowerShell on Windows. The repository intentionally contains no secrets, machine-specific SSH hosts, shell history, GPG material, or user identity configuration. Optional per-machine overrides live in `~/.config/terminal-env/local.zsh` or `local.ps1` and are not managed.
