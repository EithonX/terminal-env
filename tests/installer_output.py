#!/usr/bin/env python3
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')
if not BASH:
    raise SystemExit('installer output tests require bash')


def run_install(root: Path, home: Path, *args: str, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update({
        'HOME': str(home),
        'USER': 'terminal-env-test',
        'TERM': 'xterm-256color',
        'COLUMNS': '80',
    })
    env.pop('NO_COLOR', None)
    env.pop('SUDO_USER', None)
    if extra_env:
        env.update(extra_env)
    return subprocess.run([BASH, str(root / 'install.sh'), *args], env=env, text=True, capture_output=True)


def install_args(*extra: str) -> tuple[str, ...]:
    return ('--profile', 'server', '--dry-run', '--no-shell-change', '--no-font', *extra)


def write_fixture_tool_installer(root: Path) -> None:
    script = root / 'scripts/install-tools-unix.sh'
    script.write_text(r'''#!/usr/bin/env bash
set -Eeuo pipefail
: > "$HOME/.provision-ran"
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/chezmoi" <<'CHEZMOI'
#!/usr/bin/env bash
set -Eeuo pipefail
rm -rf "$HOME/.config/zsh"
mkdir -p "$HOME/.config/zsh" "$HOME/.local/bin"
printf 'changed\n' > "$HOME/.config/zsh/installer-fixture"
for name in terminal terminal-update terminal-rollback terminal-backup terminal-deps terminal-context; do
  cat > "$HOME/.local/bin/$name" <<'HELPER'
#!/usr/bin/env bash
exit 0
HELPER
  chmod +x "$HOME/.local/bin/$name"
done
cat > "$HOME/.local/bin/terminal-doctor" <<'DOCTOR'
#!/usr/bin/env bash
set -Eeuo pipefail
root="$HOME/.local/state/terminal-env/backups/transactions"
if find "$root" -type f -name .complete -print -quit 2>/dev/null | grep -q .; then
  exit 91
fi
[[ ! -f "$HOME/.terminal-env-doctor-fail" ]]
DOCTOR
chmod +x "$HOME/.local/bin/terminal-doctor"
CHEZMOI
chmod +x "$HOME/.local/bin/chezmoi"
''')
    script.chmod(0o755)


with tempfile.TemporaryDirectory(prefix='terminal-env-install-output-') as td:
    base = Path(td)

    home = base / 'dry-home'
    home.mkdir()
    human = run_install(ROOT, home, *install_args('--format=human', '--color=never'))
    assert human.returncode == 0, human.stderr
    assert 'Terminal Environment · install' in human.stdout
    assert '\nPreflight\n' in human.stdout and '\nPlan\n' in human.stdout and '\nFinish\n' in human.stdout
    assert 'Dry run complete · no files were changed' in human.stdout
    assert all(word not in human.stdout for word in ('PASS', 'WARN', 'FAIL', 'SUCCESS'))
    assert '\x1b[' not in human.stdout

    plain = run_install(ROOT, home, *install_args('--format=plain', '--color=always'))
    assert plain.returncode == 0, plain.stderr
    fields = plain.stdout.rstrip('\n').split('\t')
    assert fields[:3] == ['install', 'dry-run', 'server']
    assert fields[3] == platform.system()
    assert len(fields) == 6 and fields[5] == ''
    assert '\x1b[' not in plain.stdout

    structured = run_install(ROOT, home, *install_args('--format=json', '--color=always'))
    assert structured.returncode == 0, structured.stderr
    payload = json.loads(structured.stdout)
    assert payload['command'] == 'install'
    assert payload['status'] == 'dry-run'
    assert payload['profile'] == 'server'
    assert payload['platform'] == platform.system()
    assert payload['dry_run'] is True
    assert payload['transaction_backup'] is None
    assert structured.stdout.count('\n') == 1
    assert '\x1b[' not in structured.stdout
    assert '+' not in structured.stdout

    colored = run_install(ROOT, home, *install_args('--format=human', '--color=always'))
    assert colored.returncode == 0 and '\x1b[' in colored.stdout
    no_color = run_install(ROOT, home, *install_args('--format=human'), extra_env={'NO_COLOR': '1'})
    assert no_color.returncode == 0 and '\x1b[' not in no_color.stdout

    quiet = run_install(ROOT, home, *install_args('--quiet'))
    assert quiet.returncode == 0
    assert quiet.stdout == ''

    invalid = run_install(ROOT, home, *install_args('--format=xml'))
    assert invalid.returncode == 2
    assert 'Invalid format: xml' in invalid.stderr

    fixture_root = base / 'fixture-repo'
    shutil.copytree(ROOT, fixture_root, ignore=shutil.ignore_patterns('.git'))
    write_fixture_tool_installer(fixture_root)

    preflight_home = base / 'preflight-home'
    unmanaged = preflight_home / '.local/share/terminal-env/source'
    unmanaged.mkdir(parents=True)
    (unmanaged / 'foreign').write_text('not managed\n')
    preflight = run_install(
        fixture_root, preflight_home,
        '--profile', 'minimal', '--no-shell-change', '--no-font', '--format=json', '--color=never'
    )
    assert preflight.returncode != 0
    assert 'not managed by Terminal Environment' in preflight.stderr
    assert not (preflight_home / '.provision-ran').exists()

    failed_home = base / 'failed-home'
    sentinel = failed_home / '.config/zsh/sentinel'
    sentinel.parent.mkdir(parents=True)
    sentinel.write_text('before\n')
    (failed_home / '.terminal-env-doctor-fail').write_text('1\n')
    failed = run_install(
        fixture_root, failed_home,
        '--profile', 'minimal', '--no-shell-change', '--no-font', '--format=json', '--color=never'
    )
    assert failed.returncode != 0
    assert failed.stdout == ''
    assert 'Could not install Terminal Environment.' in failed.stderr
    assert 'Managed configuration was restored.' in failed.stderr
    assert sentinel.read_text() == 'before\n'
    assert not (failed_home / '.config/zsh/installer-fixture').exists()
    assert not (failed_home / '.local/share/terminal-env/source').exists()
    complete = list((failed_home / '.local/state/terminal-env/backups/transactions').glob('*/.complete'))
    assert complete == []

    success_home = base / 'success-home'
    success_home.mkdir()
    success = run_install(
        fixture_root, success_home,
        '--profile', 'minimal', '--no-shell-change', '--no-font', '--format=json', '--color=never'
    )
    assert success.returncode == 0, success.stderr
    success_payload = json.loads(success.stdout)
    assert success_payload['status'] == 'installed'
    assert success_payload['dry_run'] is False
    backup = Path(success_payload['transaction_backup'])
    assert backup.is_dir() and (backup / '.complete').is_file()
    assert (success_home / '.config/zsh/installer-fixture').read_text() == 'changed\n'

print('installer output: PASS')
