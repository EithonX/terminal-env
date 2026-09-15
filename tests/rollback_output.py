#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ROLLBACK = ROOT / 'dot_local/bin/executable_terminal-rollback'
BASH = shutil.which('bash')
GIT = shutil.which('git')
if not BASH or not GIT:
    raise SystemExit('rollback output tests require bash and git')


def run(*args: str, cwd: Path | None = None, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True, check=False)


def git(cwd: Path, *args: str) -> str:
    result = run(GIT, *args, cwd=cwd)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout.strip()


def write_exe(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('#!/usr/bin/env bash\n' + body)
    path.chmod(0o755)


def commit(source: Path, message: str, version: str, smoke_ok: bool = True) -> str:
    (source / 'versions.env').write_text(f'FZF_VERSION={version}\n')
    (source / 'revision.txt').write_text(message + '\n')
    write_exe(source / 'tests/smoke.sh', "printf 'smoke progress\\n'\n" + ('exit 0\n' if smoke_ok else 'exit 9\n'))
    write_exe(source / 'scripts/build-zsh-plugins.sh', "printf 'plugin progress\\n'\nexit 0\n")
    git(source, 'add', '.')
    git(source, 'commit', '-m', message)
    return git(source, 'rev-parse', 'HEAD')


def run_rollback(home: Path, fakebin: Path, *args: str, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update({
        'HOME': str(home),
        'PATH': str(fakebin) + os.pathsep + env['PATH'],
        'TERM': 'xterm-256color',
        'COLUMNS': '80',
    })
    env.pop('NO_COLOR', None)
    if extra_env:
        env.update(extra_env)
    return run(BASH, str(ROLLBACK), *args, env=env)


with tempfile.TemporaryDirectory(prefix='terminal-env-rollback-') as td:
    base = Path(td)
    home = base / 'home'
    source = home / '.local/share/terminal-env/source'
    state = home / '.local/state/terminal-env'
    fakebin = base / 'bin'
    source.mkdir(parents=True)
    state.mkdir(parents=True)
    fakebin.mkdir()
    (home / '.config/terminal-env').mkdir(parents=True)
    (state / 'profile').write_text('server\n')

    git(source, 'init', '-b', 'master')
    git(source, 'config', 'user.name', 'Terminal Environment Test')
    git(source, 'config', 'user.email', 'terminal-env@example.invalid')
    first = commit(source, 'first', '0.74.4')
    second = commit(source, 'second', '0.74.4')
    (state / 'previous-commit').write_text(first + '\n')

    write_exe(fakebin / 'chezmoi', "printf 'chezmoi progress\\n'\nexit 0\n")
    write_exe(fakebin / 'terminal-doctor', "[[ \" $* \" == *' --quick '* && \" $* \" == *' --quiet '* ]] || exit 7\nexit 0\n")

    planned = run_rollback(home, fakebin, '--dry-run', '--format=json', '--color=always')
    assert planned.returncode == 0, planned.stderr
    payload = json.loads(planned.stdout)
    assert payload == {
        'command': 'rollback', 'status': 'planned', 'current': second,
        'target': first, 'dependencies_changed': False,
    }
    assert git(source, 'rev-parse', 'HEAD') == second
    assert '\x1b[' not in planned.stdout

    confirmation = run_rollback(home, fakebin, '--format=json')
    assert confirmation.returncode == 2
    assert confirmation.stdout == ''
    assert 'requires --yes for plain or JSON output' in confirmation.stderr
    assert git(source, 'rev-parse', 'HEAD') == second

    applied = run_rollback(home, fakebin, '--yes', '--format=json')
    assert applied.returncode == 0, applied.stderr
    payload = json.loads(applied.stdout)
    assert payload['status'] == 'rolled-back' and payload['target'] == first
    assert git(source, 'rev-parse', 'HEAD') == first
    assert (state / 'previous-commit').read_text().strip() == second
    assert 'smoke progress' in applied.stderr and 'chezmoi progress' in applied.stderr
    assert 'progress' not in applied.stdout

    returned = run_rollback(home, fakebin, '--yes', '--color=never')
    assert returned.returncode == 0, returned.stderr
    assert 'Terminal Environment · rollback' in returned.stdout
    assert 'Rolled back · ' + second[:12] in returned.stdout
    assert git(source, 'rev-parse', 'HEAD') == second
    assert (state / 'previous-commit').read_text().strip() == first

    third = commit(source, 'third', '0.75.0')
    (state / 'previous-commit').write_text(second + '\n')
    deps = run_rollback(home, fakebin, '--yes', '--format=json')
    assert deps.returncode == 0, deps.stderr
    payload = json.loads(deps.stdout)
    assert payload['current'] == third and payload['target'] == second
    assert payload['dependencies_changed'] is True
    assert (state / 'deps-pending').read_text().strip() == second
    assert git(source, 'rev-parse', 'HEAD') == second

    broken = commit(source, 'broken-target', '0.74.4', smoke_ok=False)
    current = commit(source, 'current-good', '0.74.4', smoke_ok=True)
    (state / 'previous-commit').write_text(broken + '\n')
    failed = run_rollback(home, fakebin, '--yes', '--format=json')
    assert failed.returncode != 0
    assert failed.stdout == ''
    assert 'Could not complete rollback.' in failed.stderr
    assert 'previously active source revision and managed configuration are being restored' in failed.stderr
    assert git(source, 'rev-parse', 'HEAD') == current
    assert (state / 'previous-commit').read_text().strip() == broken

    (source / 'dirty').write_text('dirty\n')
    dirty = run_rollback(home, fakebin, '--yes', '--format=json')
    assert dirty.returncode == 2 and dirty.stdout == ''
    assert 'local changes' in dirty.stderr
    (source / 'dirty').unlink()

    (state / 'previous-commit').write_text('not-a-revision\n')
    invalid_state = run_rollback(home, fakebin, '--yes', '--format=json')
    assert invalid_state.returncode == 2 and invalid_state.stdout == ''
    assert 'revision is invalid' in invalid_state.stderr
    (state / 'previous-commit').write_text(broken + '\n')

    quiet_plan = run_rollback(home, fakebin, '--dry-run', '--quiet')
    assert quiet_plan.returncode == 0 and quiet_plan.stdout == ''

    colored = run_rollback(home, fakebin, '--dry-run', '--color=always')
    assert colored.returncode == 0 and '\x1b[' in colored.stdout
    no_color = run_rollback(home, fakebin, '--dry-run', extra_env={'NO_COLOR': '1'})
    assert no_color.returncode == 0 and '\x1b[' not in no_color.stdout

print('rollback output: PASS')
