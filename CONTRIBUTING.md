# Contributing

Keep changes small, predictable, and portable.

Before opening a pull request:

CI runs ShellCheck 0.11 separately from the platform matrix so lint results are consistent across Ubuntu and macOS.

```sh
bash ./tests/smoke.sh
bash ./install.sh --dry-run --profile server --no-shell-change --no-font
```

On Windows:

```powershell
.\tests\smoke.ps1
.\install.ps1 -DryRun -Profile workstation -NoFont -NoTerminalConfig
```

A shell feature should fail open, should not change the meaning of standard commands, and should not add network/package work to shell startup.

Platform-specific behavior is fine when it provides a better native experience; keep the interaction contract consistent where practical.
