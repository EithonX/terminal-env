# Architecture

Terminal Environment keeps shell behavior, package installation, and updates separate on purpose.

## Rules

1. **Native shells win.** PowerShell 7 on Windows; Zsh on macOS/Linux.
2. **Core commands are not replaced.** Rich alternatives are explicit (`ll`, `lt`, `bat`, `rg`, etc.).
3. **Interactive extras fail open.** A broken Atuin/fzf/prompt integration must still leave a usable shell.
4. **No network work during shell startup.** Installation and updates are explicit actions.
5. **The repo is the configuration source; `versions.env` is the dependency contract.**
6. **Machine-local secrets and history never belong in Git.**

## Ownership

- `install.sh` / `install.ps1` — first install, migration, backups, system prerequisites.
- `chezmoi` — renders managed configuration.
- `terminal-update` — fast-forward Git source + validate + apply configuration.
- `terminal-deps` — reconcile external tools/plugins to `versions.env`.
- `terminal-rollback` — return to the previous applied Git revision.
- `terminal-doctor` — diagnose the installed environment.

## Interaction model

On Zsh, inline suggestions combine history with the native completion engine. Tab remains explicit completion through fzf-tab; Ctrl+R belongs to Atuin. On Windows, PSReadLine owns inline prediction and Atuin owns deep history search.

Windows Terminal receives an additive fragment rather than a replacement settings file. The custom profile launches `pwsh.exe`, and the redundant auto-generated PowerShell 7 profiles are hidden through fragment updates while the legacy Windows PowerShell profile is left available for compatibility.

## Storage

The original pre-install restore point is retained until uninstall. The newest three successful automatic transaction snapshots are retained. Manual backups are never auto-pruned. Temporary release/font archives are deleted after provisioning.

Workstation font installation keeps only Regular, Bold, Italic, and Bold Italic Monaspice Neon Nerd Font faces. Server profiles install no fonts because the SSH client renders them.
