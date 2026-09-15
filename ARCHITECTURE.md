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

- `bootstrap.sh` / `bootstrap.ps1` — minimal network bootstrap: obtain Git if necessary, clone an updateable branch, and delegate.
- `install.sh` / `install.ps1` — authoritative install/migration path, backups, system prerequisites, and transactional recovery.
- `chezmoi` — renders managed configuration.
- `terminal` — preferred maintenance dispatcher; delegates to the command implementations below.
- `terminal update` / `terminal-update` — fast-forward Git source + validate + apply configuration.
- `terminal deps` / `terminal-deps` — reconcile external tools/plugins to `versions.env`.
- `terminal rollback` / `terminal-rollback` — return to the previous applied Git revision.
- `terminal doctor` / `terminal-doctor` — diagnose the installed environment.
- `terminal context` / `terminal-context` — resolve repository-bounded project toolchain context and provenance.

## Bootstrap boundary

The one-command bootstrap is intentionally small. It does not render configuration, install pinned portable tools itself, or maintain separate state. It obtains only the prerequisite needed to fetch the repository, clones an updateable branch into a temporary directory, and invokes the normal installer. The installer copies that Git metadata into the managed source, so later updates use the same `origin` and branch through `terminal update`.

A failed bootstrap removes its temporary checkout. Once the main installer begins, its normal transaction/rollback rules apply.

The full installer is staged as `Preflight → Plan → Apply → Verify → Finish`. Preflight rejects local source collisions and unsupported platform prerequisites before provisioning begins. Apply remains transactional. Verify runs the installed doctor with the managed tool directory active on `PATH`; non-minimal profiles also require the pinned dependency status to be synchronized. Only after verification succeeds is the transaction marked complete and eligible for normal retention pruning. A verification failure remains inside the active transaction and restores the previous managed state.

## Project context

Prompt runtime metadata comes from Terminal Environment's resolver rather than generic language-file detection. The resolver walks from the current directory to the Git worktree root and no farther. Outside a repository it inspects only the current directory.

For Node, Python, Go, and Rust, selectors, compatibility constraints, and the active executable are separate facts. Every reported selector or constraint retains its source path. Same-family declarations use the nearest source; incompatible strong selectors from different supported sources become an explicit conflict. Active runtime checks run only when project metadata makes that toolchain relevant. Selector and constraint compatibility are evaluated only for syntax the resolver understands; unsupported selection or range syntax is reported as unknown rather than guessed.

Prompt evaluation is local-only. Runtime probes disable mise network and auto-install behavior; Go probing also forces the local toolchain and Rust probing disables rustup auto-install. Shell integrations cache prompt context briefly; `terminal context` always performs a fresh diagnostic resolution and can emit plain or JSON data for inspection.

## Maintenance output

Maintenance commands share small platform-native renderers rather than embedding independent color and spacing rules in each command. Unix commands use `.local/lib/terminal-env/output.sh`; PowerShell commands use `.config/terminal-env/powershell/output.ps1`. Both implement the same semantic roles, narrow-terminal row behavior, control-character sanitization, and color policy.

The preferred maintenance surface is the thin `terminal` dispatcher. It delegates to the existing command implementations rather than reimplementing their state machines: `terminal doctor`, `terminal update`, `terminal deps`, `terminal context`, `terminal backup`, and `terminal rollback`. Legacy `terminal-*` entry points remain installed as compatibility shims. `terminal deps check` aliases dependency status, and `terminal version` reports installed source identity instead of claiming an independent semantic version that the project does not currently publish.

Doctor established the reference grammar. Dependencies, update, backup, rollback, and the full installer use the same semantic roles and output contracts where their data model warrants them. Human output is optimized for exceptions and no-op states, plain output is stable line-oriented data, and JSON contains the complete machine-readable result. Project-context plain output uses tab-separated record types so provenance remains scriptable without parsing the human layout. In automatic color mode, redirected output, `NO_COLOR`, and `TERM=dumb` disable ANSI styling. Expected command results stay on stdout; update/apply/install progress, diagnostics, and option/usage failures use stderr. `terminal backup` deliberately retains the historical backup contract of printing only the archive path unless an explicit format is requested.

Source updates and rollbacks are fail-closed around managed Git state. `terminal update` accepts only a fast-forward from the active revision, validates the incoming source before accepting it, and restores the prior source/configuration on an apply failure. `terminal rollback` validates the recorded commit, refuses dirty source state, requires confirmation (or `--yes` for automation), and restores the previously active revision/configuration if the target cannot be validated or applied. Dependency pin changes never trigger hidden package work; they set `deps-pending` for an explicit `terminal deps sync`.

## Interaction model

On Zsh, inline suggestions combine history with the native completion engine. Tab remains explicit completion through fzf-tab; Ctrl+R belongs to Atuin. On Windows, PSReadLine owns inline prediction and Atuin owns deep history search.

Windows Terminal receives an additive fragment rather than a replacement settings file. The custom profile launches `pwsh.exe`, and the redundant auto-generated PowerShell 7 profiles are hidden through fragment updates while the legacy Windows PowerShell profile is left available for compatibility.

## Storage

The original pre-install restore point is retained until uninstall. Uninstall validates that restore point before mutation, shows the destructive plan, and restores it by default; removing managed files without restoration requires the explicit `--no-restore` override. On Windows the restore point also carries the previous PowerShell profile hook, Windows Terminal state, and managed-font registry provenance. The newest three successful automatic transaction snapshots are retained. Manual backups are never auto-pruned. Temporary release/font archives are deleted after provisioning.

Workstation font installation keeps only Regular, Bold, Italic, and Bold Italic Monaspice Neon Nerd Font faces. Server profiles install no fonts because the SSH client renders them.
