#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
UPDATE = ROOT / 'dot_local/bin/executable_terminal-update'
BASH = shutil.which('bash')
GIT = shutil.which('git')
if not BASH or not GIT:
    raise SystemExit('update output tests require bash and git')


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


def run_update(home: Path, fakebin: Path, *args: str, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
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
    return run(BASH, str(UPDATE), *args, env=env)


def make_commit(author: Path, message: str, version: str, smoke_ok: bool = True) -> str:
    (author / 'versions.env').write_text(f'FZF_VERSION={version}\n')
    (author / 'revision.txt').write_text(message + '\n')
    smoke = author / 'tests/smoke.sh'
    write_exe(smoke, "printf 'smoke progress\\n'\n" + ('exit 0\n' if smoke_ok else 'exit 9\n'))
    plugin = author / 'scripts/build-zsh-plugins.sh'
    write_exe(plugin, "printf 'plugin progress\\n'\nexit 0\n")
    git(author, 'add', '.')
    git(author, 'commit', '-m', message)
    git(author, 'push', 'origin', 'master')
    return git(author, 'rev-parse', 'HEAD')


with tempfile.TemporaryDirectory(prefix='terminal-env-update-') as td:
    base = Path(td)
    remote = base / 'remote.git'
    author = base / 'author'
    home = base / 'home'
    source = home / '.local/share/terminal-env/source'
    state = home / '.local/state/terminal-env'
    fakebin = base / 'bin'
    fakebin.mkdir(parents=True)
    state.mkdir(parents=True)
    (state / 'profile').write_text('server\n')
    (home / '.config/terminal-env').mkdir(parents=True)

    git(base, 'init', '--bare', str(remote))
    git(base, 'init', '-b', 'master', str(author))
    git(author, 'config', 'user.name', 'Terminal Environment Test')
    git(author, 'config', 'user.email', 'terminal-env@example.invalid')
    git(author, 'remote', 'add', 'origin', str(remote))
    first = make_commit(author, 'first', '0.74.4')
    source.parent.mkdir(parents=True)
    git(base, 'clone', '--branch', 'master', str(remote), str(source))

    write_exe(fakebin / 'chezmoi', "printf 'chezmoi progress\\n'\nexit 0\n")
    write_exe(fakebin / 'terminal-doctor', "[[ \" $* \" == *' --quick '* && \" $* \" == *' --quiet '* ]] || exit 7\nexit 0\n")

    current = run_update(home, fakebin, '--format=json', '--color=always')
    assert current.returncode == 0, current.stderr
    payload = json.loads(current.stdout)
    assert payload == {
        'command': 'update', 'action': 'update', 'status': 'up-to-date',
        'remote': 'origin', 'branch': 'master', 'current': first, 'latest': first,
        'commit_count': 0, 'dependencies_changed': False,
    }
    assert '\x1b[' not in current.stdout

    second = make_commit(author, 'second', '0.74.4')
    available = run_update(home, fakebin, '--check', '--color=never')
    assert available.returncode == 0, available.stderr
    assert 'Terminal Environment · update' in available.stdout
    assert 'Update available · 1 commit(s)' in available.stdout
    assert first[:12] in available.stdout and second[:12] in available.stdout
    assert git(source, 'rev-parse', 'HEAD') == first

    plain = run_update(home, fakebin, '--check', '--format=plain', '--color=always')
    assert plain.returncode == 0, plain.stderr
    fields = plain.stdout.rstrip().split('\t')
    assert fields == ['update', 'available', first, second, '1', 'origin', 'master', '0']
    assert '\x1b[' not in plain.stdout

    applied = run_update(home, fakebin, '--color=never')
    assert applied.returncode == 0, applied.stderr
    assert 'Updated' in applied.stdout and f'{first[:12]} → {second[:12]}' in applied.stdout
    assert 'Updated · ' + second[:12] in applied.stdout
    assert 'smoke progress' in applied.stderr
    assert 'chezmoi progress' in applied.stderr
    assert 'plugin progress' in applied.stderr
    assert git(source, 'rev-parse', 'HEAD') == second
    assert (state / 'previous-commit').read_text().strip() == first
    assert not (state / 'deps-pending').exists()

    third = make_commit(author, 'third', '0.75.0')
    dep_check = run_update(home, fakebin, '--check', '--format=json')
    dep_payload = json.loads(dep_check.stdout)
    assert dep_payload['status'] == 'available'
    assert dep_payload['latest'] == third
    assert dep_payload['dependencies_changed'] is True

    dep_apply = run_update(home, fakebin, '--format=json')
    assert dep_apply.returncode == 0, dep_apply.stderr
    dep_payload = json.loads(dep_apply.stdout)
    assert dep_payload['status'] == 'updated' and dep_payload['dependencies_changed'] is True
    assert dep_payload['current'] == second and dep_payload['latest'] == third
    assert dep_apply.stdout.count('\n') == 1
    assert 'smoke progress' not in dep_apply.stdout and 'chezmoi progress' not in dep_apply.stdout
    assert (state / 'deps-pending').read_text().strip() == third

    fourth = make_commit(author, 'broken', '0.75.0', smoke_ok=False)
    failed = run_update(home, fakebin, '--format=json')
    assert failed.returncode != 0
    assert failed.stdout == ''
    assert 'Could not update Terminal Environment.' in failed.stderr
    assert 'previous source revision and managed configuration are being restored' in failed.stderr
    assert git(source, 'rev-parse', 'HEAD') == third
    assert fourth != third

    # A dirty managed source must fail closed before fetching or mutating it.
    (source / 'local-change').write_text('dirty\n')
    dirty = run_update(home, fakebin, '--format=json')
    assert dirty.returncode == 2
    assert dirty.stdout == ''
    assert 'local changes' in dirty.stderr
    (source / 'local-change').unlink()

    quiet = run_update(home, fakebin, '--check', '--quiet')
    assert quiet.returncode == 0
    assert quiet.stdout == ''

    colored = run_update(home, fakebin, '--check', '--color=always')
    assert colored.returncode == 0 and '\x1b[' in colored.stdout
    no_color = run_update(home, fakebin, '--check', extra_env={'NO_COLOR': '1'})
    assert no_color.returncode == 0 and '\x1b[' not in no_color.stdout

    invalid = run_update(home, fakebin, '--format=xml')
    assert invalid.returncode == 2
    assert 'Invalid format: xml' in invalid.stderr

print('update output: PASS')
