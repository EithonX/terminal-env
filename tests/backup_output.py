#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BACKUP = ROOT / 'dot_local/bin/executable_terminal-backup'
BASH = shutil.which('bash')
if not BASH:
    raise SystemExit('backup output tests require bash')


def run_backup(home: Path, *args: str, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update({'HOME': str(home), 'TERM': 'xterm-256color', 'COLUMNS': '80'})
    env.pop('NO_COLOR', None)
    if extra_env:
        env.update(extra_env)
    return subprocess.run([BASH, str(BACKUP), *args], env=env, text=True, capture_output=True)


with tempfile.TemporaryDirectory(prefix='terminal-env-backup-') as td:
    base = Path(td)
    home = base / 'home'
    config = home / '.config/terminal-env'
    config.mkdir(parents=True)
    (config / 'settings').write_text('fixture\n')
    history = home / '.local/share/atuin'
    history.mkdir(parents=True)
    (history / 'history.db').write_text('history\n')

    legacy = run_backup(home)
    assert legacy.returncode == 0, legacy.stderr
    legacy_path = Path(legacy.stdout.strip())
    assert legacy_path.is_file()
    assert stat.S_IMODE(legacy_path.stat().st_mode) == 0o600
    with tarfile.open(legacy_path, 'r:gz') as archive:
        names = archive.getnames()
    assert any(name.endswith('.config/terminal-env/settings') for name in names)
    assert not any('.local/share/atuin' in name for name in names)

    human = run_backup(home, '--format=human', '--color=never')
    assert human.returncode == 0, human.stderr
    assert 'Terminal Environment · backup' in human.stdout
    assert '\nCreated\n' in human.stdout
    assert 'configuration' in human.stdout
    assert 'Backup created' in human.stdout
    assert '\x1b[' not in human.stdout

    structured = run_backup(home, '--with-history', '--format=json', '--color=always')
    assert structured.returncode == 0, structured.stderr
    payload = json.loads(structured.stdout)
    assert payload['command'] == 'backup' and payload['status'] == 'created'
    assert payload['with_history'] is True and payload['bytes'] > 0
    structured_path = Path(payload['archive'])
    assert structured_path.is_file()
    with tarfile.open(structured_path, 'r:gz') as archive:
        names = archive.getnames()
    assert any('.local/share/atuin' in name for name in names)
    assert '\x1b[' not in structured.stdout

    plain = run_backup(home, '--format=plain')
    assert plain.returncode == 0, plain.stderr
    fields = plain.stdout.rstrip().split('\t')
    assert fields[0:2] == ['backup', 'created'] and fields[4] == '0'
    assert Path(fields[2]).is_file() and int(fields[3]) > 0

    colored = run_backup(home, '--format=human', '--color=always')
    assert colored.returncode == 0 and '\x1b[' in colored.stdout
    no_color = run_backup(home, '--format=human', extra_env={'NO_COLOR': '1'})
    assert no_color.returncode == 0 and '\x1b[' not in no_color.stdout

    before = len(list((home / '.local/state/terminal-env/backups/manual').glob('manual-*')))
    quiet = run_backup(home, '--quiet')
    after = len(list((home / '.local/state/terminal-env/backups/manual').glob('manual-*')))
    assert quiet.returncode == 0 and quiet.stdout == '' and after == before + 1

    invalid = run_backup(home, '--format=xml')
    assert invalid.returncode == 2
    assert 'Invalid format: xml' in invalid.stderr

with tempfile.TemporaryDirectory(prefix='terminal-env-backup-empty-') as td:
    empty_home = Path(td) / 'home'
    empty_home.mkdir()
    empty = run_backup(empty_home, '--format=json')
    assert empty.returncode == 1 and empty.stdout == ''
    assert 'Nothing to back up.' in empty.stderr

print('backup output: PASS')
