# Architecture

Terminal Environment is designed around failure isolation. The operating-system package manager owns system prerequisites; pinned standalone binaries own interactive intelligence; chezmoi owns rendered configuration; the login shell never performs package or network work.

## Invariants

1. Core commands keep their native semantics.
2. Optional intelligence fails open: Deja, Atuin, fzf, Oh My Posh, and enhanced completions may disappear without preventing a usable shell.
3. Native shell history remains available beneath enhanced history.
4. Install and update actions create recoverable state before replacing managed files.
5. Updates are explicit and Git-backed; shell startup never self-updates.
6. Secrets and history databases never belong in the repository.
7. Platform-specific shells/renderers are allowed when they improve the native experience; interaction meaning stays consistent.
8. Machine-local customization is an escape hatch, not a setup requirement. Defaults are the product.

## Ownership

- `install.sh` / `install.ps1`: provisioning, migration, backups, initial application.
- `chezmoi`: deterministic target-state rendering.
- `versions.env`: pinned portable dependency versions and plugin revisions.
- `terminal-update`: controlled Git fast-forward + validation + re-provision.
- `terminal-rollback`: Git revision rollback + pinned component reconciliation.
- `terminal-doctor`: runtime diagnostics and degraded-mode visibility.
- Zsh/PowerShell profiles: interactive behavior only.

## Profiles

`server` avoids workstation font/GUI dependencies and adds tmux. `workstation` enables the full renderer/font experience. `minimal` installs only enough foundation for a safe shell and deliberately leaves optional intelligence absent.

## Visual system

The default visual language is deliberately restrained: graphite surfaces, cool blue as the primary focus color, violet for references/links, green for executable/success state, amber for attention, and rose for failure. The prompt uses a structural two-line frame for the active command and a muted dot for transient historical prompts, so current input is visually distinct from scrollback. Standard `ls` remains the native command but receives color in interactive shells; `l`, `la`, `ll`, and `lt` use eza for richer icon-aware views.
