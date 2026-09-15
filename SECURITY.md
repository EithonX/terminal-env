# Security

## Commands and history

Atuin's secret filter is enabled and additional credential-shaped patterns are excluded. Zsh history honors leading-space exclusion. No heuristic catches every secret: prefer stdin, environment files with proper permissions, or a secret manager over putting credentials directly in command arguments.

## Downloads

Pinned portable tools come from deterministic upstream GitHub release URLs over TLS. Versions are pinned in `versions.env`. The installer also attempts to retrieve GitHub's published asset digest and verifies SHA-256 when release metadata is available; a metadata/API quota failure does not block the deterministic HTTPS download. `GITHUB_TOKEN` or `GH_TOKEN` can be supplied for authenticated metadata requests. Zsh plugins are pinned to release refs/commits in `versions.env`.

## Network bootstrap

The convenience install commands execute `bootstrap.ps1` or `bootstrap.sh` from this repository's `master` branch over HTTPS. The bootstrap is deliberately small: it acquires Git when necessary, clones the repository, verifies that the requested ref is an updateable branch, and delegates to the normal transactional installer. It does not permanently lower PowerShell execution policy.

Executing a mutable branch bootstrap means trusting the current repository contents. `TERMINAL_ENV_REPO` intentionally permits a fork or mirror and transfers the same trust to that repository. Users who need review-before-execution should inspect the bootstrap or clone the repository before running the installer.

## Paste behavior

The setup relies on bracketed paste and does not intentionally execute pasted blocks automatically. Ghostty paste protection is enabled; Windows Terminal keeps its built-in paste warnings. Review generated commands before running them.

## Recovery

Installations create a transaction snapshot before managed files are replaced. Failed transactions roll back; the original pre-install restore point is kept until uninstall. System packages are not automatically removed because prior ownership cannot be proven safely.

## Reporting issues

Do not include tokens, shell history, private SSH configuration, credentials, or private hostnames in public issues. For a security vulnerability, use GitHub's private vulnerability reporting feature if it is enabled for the repository.
