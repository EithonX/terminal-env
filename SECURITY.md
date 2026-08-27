# Security

## Commands and history

Atuin's secret filter is enabled and additional credential-shaped patterns are excluded. Zsh history honors leading-space exclusion. No heuristic catches every secret: prefer stdin, environment files with proper permissions, or a secret manager over putting credentials directly in command arguments.

## Downloads

Pinned portable tools come from their upstream GitHub release assets over TLS. Asset SHA-256 digests are verified when GitHub publishes them. Zsh plugins are pinned to release refs/commits in `versions.env`.

## Paste behavior

The setup relies on bracketed paste and does not intentionally execute pasted blocks automatically. Ghostty paste protection is enabled; Windows Terminal keeps its built-in paste warnings. Review generated commands before running them.

## Recovery

Installations create a transaction snapshot before managed files are replaced. Failed transactions roll back; the original pre-install restore point is kept until uninstall. System packages are not automatically removed because prior ownership cannot be proven safely.

## Reporting issues

Do not include tokens, shell history, private SSH configuration, credentials, or private hostnames in public issues. For a security vulnerability, use GitHub's private vulnerability reporting feature if it is enabled for the repository.
