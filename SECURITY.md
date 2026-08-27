# Security

## History and secrets

Atuin's built-in secrets filter is explicitly enabled and additional command-pattern filters are configured. Zsh history uses `HIST_IGNORE_SPACE`/`HISTORY_IGNORE`; zsh-autosuggestions consumes that filtered history and does not maintain a second command database. Prefix a sensitive command with a space to deliberately keep it out of managed history. No heuristic can identify every secret; do not paste long-lived credentials directly into command arguments when an environment file, stdin, or a secret manager is available.

## Downloads

Portable releases are downloaded over TLS from GitHub release assets. When GitHub publishes an asset SHA-256 digest, installation verifies it before replacement. Managed files are staged before atomic replacement where possible. Plugin revisions are release/tag constrained and key plugins are additionally checked against known Git commits.

## Paste and terminal behavior

The shell relies on bracketed paste rather than deliberately executing pasted text. Ghostty paste protection is enabled; Windows Terminal retains its paste warnings. Always inspect AI-generated commands before execution.

## Recovery

The first successful migration records an original pre-install restore point. Updates keep a previous Git revision and rollback re-applies that revision's pinned binaries and configuration. OS packages are not removed automatically because prior ownership cannot be proven safely.

## Reporting

Do not include secrets, private SSH configuration, shell history, tokens, or private hostnames when reporting an issue.

## Font and backup ownership

A filename resembling a Terminal Environment dependency is not sufficient proof of ownership. Font garbage collection is restricted to the `.terminal-env-<version>` namespace created by this project; pre-existing font files are never removed automatically. Windows font registration uses current-user scope and does not require elevation.

Transaction pruning occurs only after a successful install has produced a complete replacement snapshot. The original pre-install restore point and explicit `terminal-backup` archives are excluded from automatic pruning. A failed transaction is retained when rollback cannot be proven successful so recovery evidence is not destroyed.
