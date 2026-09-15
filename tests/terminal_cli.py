#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')
GIT = shutil.which('git')
if not BASH or not GIT:
    raise SystemExit('terminal CLI tests require bash and git')


def run(command: Path, home: Path, *args: str, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update({'HOME': str(home), 'TERM': 'dumb', 'NO_COLOR': '1'})
    if extra_env:
        env.update(extra_env)
    return subprocess.run([str(command), *args], env=env, text=True, capture_output=True)


help_contracts = {
    'doctor': ('Usage: terminal doctor [options]', 'terminal-doctor [options]'),
    'update': ('Usage: terminal update [options]', 'terminal-update [options]'),
    'deps': ('Usage: terminal deps [status|sync] [options]', 'terminal-deps [status|sync] [options]'),
    'context': ('Usage: terminal context [options]', 'terminal-context [options]'),
    'backup': ('Usage: terminal backup [options]', 'terminal-backup [options]'),
    'rollback': ('Usage: terminal rollback [options]', 'terminal-rollback [options]'),
}
for name, (primary, compatibility) in help_contracts.items():
    result = subprocess.run(
        [BASH, str(ROOT / f'dot_local/bin/executable_terminal-{name}'), '--help'],
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.startswith(primary + '\n')
    assert compatibility in result.stdout


with tempfile.TemporaryDirectory(prefix='terminal-env-cli-') as td:
    base = Path(td)
    home = base / 'home'
    bin_dir = home / '.local/bin'
    lib_dir = home / '.local/lib/terminal-env'
    bin_dir.mkdir(parents=True)
    lib_dir.mkdir(parents=True)
    command = bin_dir / 'terminal'
    shutil.copy2(ROOT / 'dot_local/bin/executable_terminal', command)
    command.chmod(0o755)
    shutil.copy2(ROOT / 'dot_local/lib/terminal-env/output.sh', lib_dir / 'output.sh')

    log = base / 'delegated.log'
    for name in ('doctor', 'update', 'deps', 'context', 'backup', 'rollback'):
        helper = bin_dir / f'terminal-{name}'
        helper.write_text(f'''#!/usr/bin/env bash\nprintf '%s\\n' "{name}|$*" > "$TERMINAL_TEST_LOG"\nexit "${{TERMINAL_TEST_EXIT:-0}}"\n''')
        helper.chmod(0o755)

    env = {'TERMINAL_TEST_LOG': str(log)}
    help_result = run(command, home, '--help', extra_env=env)
    assert help_result.returncode == 0
    assert help_result.stdout.startswith('Terminal Environment\n\nUsage\n')
    for token in ('doctor', 'update', 'deps', 'context', 'backup', 'rollback', 'version'):
        assert token in help_result.stdout
    assert 'PASS' not in help_result.stdout and '🚀' not in help_result.stdout

    delegated = run(command, home, 'doctor', '--quick', '--format', 'plain', extra_env=env)
    assert delegated.returncode == 0
    assert log.read_text().strip() == 'doctor|--quick --format plain'

    failed = run(command, home, 'update', '--check', extra_env={**env, 'TERMINAL_TEST_EXIT': '7'})
    assert failed.returncode == 7
    assert log.read_text().strip() == 'update|--check'

    deps_default = run(command, home, 'deps', extra_env=env)
    assert deps_default.returncode == 0
    assert log.read_text().strip() == 'deps|status'
    deps_check = run(command, home, 'deps', 'check', '--format=json', extra_env=env)
    assert deps_check.returncode == 0
    assert log.read_text().strip() == 'deps|status --format=json'
    deps_sync = run(command, home, 'deps', 'sync', '--dry-run', extra_env=env)
    assert deps_sync.returncode == 0
    assert log.read_text().strip() == 'deps|sync --dry-run'

    context = run(command, home, 'context', '--format', 'json', extra_env=env)
    assert context.returncode == 0
    assert log.read_text().strip() == 'context|--format json'

    unknown = run(command, home, 'wat', extra_env=env)
    assert unknown.returncode == 2
    assert 'Unknown command: wat' in unknown.stderr

    source = home / '.local/share/terminal-env/source'
    source.mkdir(parents=True)
    subprocess.run([GIT, 'init', '-q'], cwd=source, check=True)
    subprocess.run([GIT, 'config', 'user.email', 'terminal-test@example.invalid'], cwd=source, check=True)
    subprocess.run([GIT, 'config', 'user.name', 'Terminal Test'], cwd=source, check=True)
    (source / 'README').write_text('fixture\n')
    subprocess.run([GIT, 'add', 'README'], cwd=source, check=True)
    subprocess.run([GIT, 'commit', '-qm', 'fixture'], cwd=source, check=True)
    revision = subprocess.check_output([GIT, 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
    branch = subprocess.check_output([GIT, 'symbolic-ref', '--short', 'HEAD'], cwd=source, text=True).strip()
    state = home / '.local/state/terminal-env'
    state.mkdir(parents=True)
    (state / 'profile').write_text('server\n')

    version_json = run(command, home, 'version', '--format=json', '--color=never', extra_env=env)
    assert version_json.returncode == 0
    payload = json.loads(version_json.stdout)
    assert payload == {
        'command': 'version',
        'source_kind': 'git',
        'revision': revision,
        'branch': branch,
        'profile': 'server',
    }
    assert '\x1b[' not in version_json.stdout

    version_human = run(command, home, 'version', '--color=never', extra_env=env)
    assert version_human.returncode == 0
    assert 'Terminal Environment · version' in version_human.stdout
    assert revision[:12] in version_human.stdout
    assert '\x1b[' not in version_human.stdout

    compact = run(command, home, '--version', extra_env=env)
    assert compact.returncode == 0
    assert compact.stdout.strip() == f'Terminal Environment source {revision[:12]}'

    quiet = run(command, home, 'version', '--quiet', extra_env=env)
    assert quiet.returncode == 0 and quiet.stdout == ''

print('terminal CLI: PASS')
