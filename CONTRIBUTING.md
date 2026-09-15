# Contributing

Keep changes small, predictable, portable, and consistent with the product's existing command contracts.

## Quality gate

Before opening a pull request on macOS or Linux:

```sh
bash ./tests/smoke.sh
python3 ./tests/docs_quality.py
bash ./install.sh --dry-run --profile server --no-shell-change --no-font
```

On Windows:

```powershell
.\tests\smoke.ps1
.\install.ps1 -DryRun -Profile workstation -NoFont -NoTerminalConfig
```

CI runs ShellCheck 0.11 separately from the platform matrix so lint results stay consistent across Ubuntu and macOS.

## Constraints

- Optional interactive shell enhancements should fail open; a broken prompt, history UI, or fuzzy finder must not brick the shell.
- Install, update, dependency reconciliation, rollback, and uninstall paths should fail closed before unsafe or ambiguous mutation.
- Standard commands keep their standard meaning. Rich alternatives are explicit.
- Shell startup must not perform package installation or network work.
- Cross-platform implementations may be native to their shell, but human and machine-facing command contracts should remain aligned.
- Tests should exercise behavior, parsers, fixtures, and output contracts rather than freeze incidental source spelling.
