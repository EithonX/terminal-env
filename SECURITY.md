# Security

## History and secrets

Atuin's built-in secrets filter is explicitly enabled and additional command-pattern filters are configured. Zsh/Deja use `HIST_IGNORE_SPACE`/`HISTORY_IGNORE`. Prefix a sensitive command with a space to deliberately keep it out of managed history. No heuristic can identify every secret; do not paste long-lived credentials directly into command arguments when an environment file, stdin, or a secret manager is available.

## Downloads

Portable releases are downloaded over TLS from GitHub release assets. When GitHub publishes an asset SHA-256 digest, installation verifies it before replacement. Managed files are staged before atomic replacement where possible. Plugin revisions are release/tag constrained and key plugins are additionally checked against known Git commits.

## Paste and terminal behavior

The shell relies on bracketed paste rather than deliberately executing pasted text. Ghostty paste protection is enabled; Windows Terminal retains its paste warnings. Always inspect AI-generated commands before execution.

## Recovery

The first successful migration records an original pre-install restore point. Updates keep a previous Git revision and rollback re-applies that revision's pinned binaries and configuration. OS packages are not removed automatically because prior ownership cannot be proven safely.

## Reporting

Do not include secrets, private SSH configuration, shell history, tokens, or private hostnames when reporting an issue.
