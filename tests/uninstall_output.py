#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')
if not BASH:
    raise SystemExit('uninstall output tests require bash')


def run_uninstall(home: Path, *args: str, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update({
        'HOME': str(home),
        'USER': 'terminal-env-test',
        'TERM': 'xterm-256color',
        'COLUMNS': '80',
        'TERMINAL_ENV_STATE': str(home / '.local/state/terminal-env'),
    })
    env.pop('NO_COLOR', None)
    if extra_env:
        env.update(extra_env)
    return subprocess.run([BASH, str(ROOT / 'uninstall.sh'), *args], env=env, text=True, capture_output=True)


def make_restore_point(home: Path) -> Path:
    state = home / '.local/state/terminal-env'
    backup = state / 'backups/transactions/install-original'
    original = backup / '.config/terminal-env/original.txt'
    original.parent.mkdir(parents=True)
    original.write_text('before\n')
    state.mkdir(parents=True, exist_ok=True)
    (state / 'original-backup').write_text(str(backup) + '\n')
    return backup


with tempfile.TemporaryDirectory(prefix='terminal-env-uninstall-output-') as td:
    base = Path(td)

    missing_home = base / 'missing-home'
    managed = missing_home / '.config/terminal-env/managed.txt'
    managed.parent.mkdir(parents=True)
    managed.write_text('keep\n')
    missing = run_uninstall(missing_home, '--yes', '--format=json')
    assert missing.returncode == 2
    assert 'No pre-install restore point is recorded' in missing.stderr
    assert managed.read_text() == 'keep\n'

    broken_home = base / 'broken-home'
    broken_managed = broken_home / '.config/terminal-env/managed.txt'
    broken_managed.parent.mkdir(parents=True)
    broken_managed.write_text('keep\n')
    state = broken_home / '.local/state/terminal-env'
    state.mkdir(parents=True)
    (state / 'original-backup').write_text(str(broken_home / 'missing-backup') + '\n')
    broken = run_uninstall(broken_home, '--yes', '--format=json')
    assert broken.returncode == 2
    assert 'recorded pre-install restore point is missing' in broken.stderr
    assert broken_managed.read_text() == 'keep\n'

    dry_home = base / 'dry-home'
    dry_managed = dry_home / '.config/terminal-env/managed.txt'
    dry_managed.parent.mkdir(parents=True)
    dry_managed.write_text('managed\n')
    dry = run_uninstall(dry_home, '--no-restore', '--dry-run', '--format=json', '--color=always')
    assert dry.returncode == 0, dry.stderr
    payload = json.loads(dry.stdout)
    assert payload == {
        'command': 'uninstall',
        'status': 'planned',
        'restore_requested': False,
        'restore_available': False,
        'restored': False,
        'backup': '',
        'packages_preserved': True,
        'history_preserved': True,
    }
    assert dry_managed.read_text() == 'managed\n'
    assert '\x1b[' not in dry.stdout

    human = run_uninstall(dry_home, '--no-restore', '--dry-run', '--format=human', '--color=never')
    assert human.returncode == 0, human.stderr
    assert 'Terminal Environment · uninstall' in human.stdout
    assert '\nPlan\n' in human.stdout
    assert 'Packages/history' in human.stdout
    assert 'Dry run complete · no changes applied' in human.stdout
    assert '\x1b[' not in human.stdout

    colored = run_uninstall(dry_home, '--no-restore', '--dry-run', '--format=human', '--color=always')
    assert colored.returncode == 0 and '\x1b[' in colored.stdout
    no_color = run_uninstall(dry_home, '--no-restore', '--dry-run', '--format=human', extra_env={'NO_COLOR': '1'})
    assert no_color.returncode == 0 and '\x1b[' not in no_color.stdout

    confirm_home = base / 'confirm-home'
    confirm_managed = confirm_home / '.config/terminal-env/managed.txt'
    confirm_managed.parent.mkdir(parents=True)
    confirm_managed.write_text('keep\n')
    make_restore_point(confirm_home)
    confirm = run_uninstall(confirm_home, '--no-input', '--format=human')
    assert confirm.returncode == 2
    assert 'requires --yes' in confirm.stderr
    assert confirm_managed.read_text() == 'keep\n'
    machine_confirm = run_uninstall(confirm_home, '--format=json')
    assert machine_confirm.returncode == 2
    assert 'requires --yes' in machine_confirm.stderr
    assert machine_confirm.stdout == ''
    assert confirm_managed.read_text() == 'keep\n'

    failure_home = base / 'failure-home'
    failure_backup = make_restore_point(failure_home)
    failure_managed = failure_home / '.config/terminal-env/managed.txt'
    failure_managed.parent.mkdir(parents=True, exist_ok=True)
    failure_managed.write_text('managed\n')
    fake_bin = base / 'fake-bin'
    fake_bin.mkdir()
    real_tar = shutil.which('tar')
    assert real_tar
    fake_tar = fake_bin / 'tar'
    fake_tar.write_text(
        '#!/usr/bin/env bash\n'
        'set -Eeuo pipefail\n'
        'if [[ " $* " == *" -cf /dev/null "* ]]; then exec "' + real_tar + '" "$@"; fi\n'
        'if [[ " $* " == *" -cf - "* ]]; then exit 33; fi\n'
        'exec "' + real_tar + '" "$@"\n'
    )
    fake_tar.chmod(0o755)
    failed = run_uninstall(
        failure_home, '--yes', '--format=json',
        extra_env={'PATH': str(fake_bin) + os.pathsep + os.environ['PATH']},
    )
    assert failed.returncode != 0
    assert failed.stdout == ''
    assert 'restoring the managed state that was active before the command' in failed.stderr
    assert failure_managed.read_text() == 'managed\n'
    assert (failure_home / '.local/state/terminal-env/original-backup').read_text().strip() == str(failure_backup)

    restore_home = base / 'restore-home'
    backup = make_restore_point(restore_home)
    current = restore_home / '.config/terminal-env/managed.txt'
    current.parent.mkdir(parents=True, exist_ok=True)
    current.write_text('managed\n')
    source = restore_home / '.local/share/terminal-env/source'
    source.mkdir(parents=True)
    (source / 'marker').write_text('source\n')
    history = restore_home / '.local/share/atuin/history.db'
    history.parent.mkdir(parents=True)
    history.write_text('history\n')
    manual = restore_home / '.local/state/terminal-env/backups/manual/manual-keep.tar.gz'
    manual.parent.mkdir(parents=True, exist_ok=True)
    manual.write_text('backup\n')
    restored = run_uninstall(restore_home, '--yes', '--format=json', '--color=always')
    assert restored.returncode == 0, restored.stderr
    restored_payload = json.loads(restored.stdout)
    assert restored_payload['status'] == 'uninstalled'
    assert restored_payload['restore_requested'] is True
    assert restored_payload['restore_available'] is True
    assert restored_payload['restored'] is True
    assert restored_payload['backup'] == str(backup)
    assert (restore_home / '.config/terminal-env/original.txt').read_text() == 'before\n'
    assert not current.exists()
    assert not source.exists()
    assert history.read_text() == 'history\n'
    assert manual.read_text() == 'backup\n'
    assert not (restore_home / '.local/state/terminal-env/original-backup').exists()
    assert '\x1b[' not in restored.stdout

    remove_home = base / 'remove-home'
    remove_managed = remove_home / '.config/terminal-env/managed.txt'
    remove_managed.parent.mkdir(parents=True)
    remove_managed.write_text('managed\n')
    remove_history = remove_home / '.local/share/atuin/history.db'
    remove_history.parent.mkdir(parents=True)
    remove_history.write_text('history\n')
    remove_manual = remove_home / '.local/state/terminal-env/backups/manual/manual-keep.tar.gz'
    remove_manual.parent.mkdir(parents=True)
    remove_manual.write_text('backup\n')
    removed = run_uninstall(remove_home, '--no-restore', '--yes', '--format=plain')
    assert removed.returncode == 0, removed.stderr
    assert removed.stdout == 'uninstall\tuninstalled\t0\t0\t\n'
    assert not remove_managed.exists()
    assert remove_history.read_text() == 'history\n'
    assert remove_manual.read_text() == 'backup\n'

    quiet_home = base / 'quiet-home'
    quiet_managed = quiet_home / '.config/terminal-env/managed.txt'
    quiet_managed.parent.mkdir(parents=True)
    quiet_managed.write_text('managed\n')
    quiet = run_uninstall(quiet_home, '--no-restore', '--yes', '--quiet')
    assert quiet.returncode == 0, quiet.stderr
    assert quiet.stdout == ''
    assert not quiet_managed.exists()

print('uninstall output: PASS')
