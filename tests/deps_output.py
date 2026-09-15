#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DEPS = ROOT / 'dot_local/bin/executable_terminal-deps'
BASH = shutil.which('bash')
if not BASH:
    raise SystemExit('dependency output tests require bash')


def write_exe(path: Path, body: str) -> None:
    path.write_text('#!/usr/bin/env bash\n' + body)
    path.chmod(0o755)


def run_deps(home: Path, fakebin: Path, *args: str, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
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
    return subprocess.run([BASH, str(DEPS), *args], env=env, text=True, capture_output=True)


with tempfile.TemporaryDirectory(prefix='terminal-env-deps-') as td:
    base = Path(td)
    home = base / 'home'
    fakebin = base / 'bin'
    fakebin.mkdir(parents=True)
    source = home / '.local/share/terminal-env/source'
    state = home / '.local/state/terminal-env'
    source.mkdir(parents=True)
    state.mkdir(parents=True)
    shutil.copy2(ROOT / 'versions.env', source / 'versions.env')
    (state / 'profile').write_text('server\n')

    versions = {
        'oh-my-posh': '31.3.0',
        'atuin': '18.22.0',
        'fzf': '0.74.4',
        'zoxide': '0.10.0',
        'chezmoi': '2.72.2',
    }
    for name, version in versions.items():
        write_exe(fakebin / name, f"if [[ ${{1:-}} == --version ]]; then printf '%s\\n' '{version}'; fi\nexit 0\n")

    git_body = r'''
if [[ ${1:-} == -C ]]; then
  path=$2; shift 2
  name=${path##*/}
  if [[ ${1:-} == rev-parse && ${2:-} == HEAD ]]; then
    case "$name" in
      zsh-autosuggestions) printf 'e52ee8ca55aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' ;;
      zsh-completions) printf '28c5bdcaf81bb89e56d0df8267d822c3b8aed9e0\n' ;;
      fzf-tab) printf 'd7e0234614dbe5369fdd760907d12c0e05a4dccc\n' ;;
      *) exit 1 ;;
    esac
    exit 0
  fi
  if [[ ${1:-} == describe && ${2:-} == --tags && ${3:-} == --exact-match ]]; then
    [[ $name == zsh-syntax-highlighting ]] || exit 1
    printf '0.8.0\n'
    exit 0
  fi
fi
exit 1
'''
    write_exe(fakebin / 'git', git_body)

    healthy = run_deps(home, fakebin, 'status', '--color=never')
    assert healthy.returncode == 0, healthy.stderr
    assert 'Terminal Environment · dependencies' in healthy.stdout
    assert 'Up to date · 9 dependencies' in healthy.stdout
    assert 'OK' not in healthy.stdout and 'MISMATCH' not in healthy.stdout

    verbose = run_deps(home, fakebin, 'status', '--verbose', '--color=never')
    assert verbose.returncode == 0, verbose.stderr
    assert '\nTools\n' in verbose.stdout and '\nPlugins\n' in verbose.stdout
    assert 'Oh My Posh' in verbose.stdout and 'zsh-autosuggestions' in verbose.stdout

    plain = run_deps(home, fakebin, 'status', '--format=plain', '--color=always')
    assert plain.returncode == 0, plain.stderr
    assert plain.stdout.startswith('meta\tprofile\tserver\n')
    assert 'dependency\tmatch\tfzf\tTools\tfzf\t0.74.4\t0.74.4\t' in plain.stdout
    assert '\x1b[' not in plain.stdout

    structured = run_deps(home, fakebin, 'status', '--format', 'json')
    assert structured.returncode == 0, structured.stderr
    payload = json.loads(structured.stdout)
    assert payload['command'] == 'dependencies' and payload['action'] == 'status'
    assert payload['summary'] == {'dependencies': 9, 'mismatch': 0, 'pending': False}
    assert len(payload['dependencies']) == 9

    write_exe(fakebin / 'fzf', "if [[ ${1:-} == --version ]]; then printf '0.73.0\\n'; fi\nexit 0\n")
    mismatch = run_deps(home, fakebin, 'status', '--color=never')
    assert mismatch.returncode == 1
    assert 'Attention' in mismatch.stdout
    assert 'warning · installed 0.73.0 · pinned 0.74.4' in mismatch.stdout
    assert 'MISMATCH' not in mismatch.stdout

    colored = run_deps(home, fakebin, 'status', '--color=always')
    assert colored.returncode == 1 and '\x1b[' in colored.stdout
    no_color = run_deps(home, fakebin, 'status', extra_env={'NO_COLOR': '1'})
    assert no_color.returncode == 1 and '\x1b[' not in no_color.stdout

    (state / 'deps-pending').write_text('fixture\n')
    pending = run_deps(home, fakebin, 'status', '--format=json')
    pending_payload = json.loads(pending.stdout)
    assert pending.returncode == 1
    assert pending_payload['summary']['pending'] is True
    (state / 'deps-pending').unlink()

    quiet = run_deps(home, fakebin, 'status', '--quiet')
    assert quiet.returncode == 1 and quiet.stdout == ''

    (state / 'profile').write_text('minimal\n')
    minimal = run_deps(home, fakebin, 'status', '--color=never')
    assert minimal.returncode == 0
    assert 'Minimal profile · optional managed dependencies are intentionally omitted' in minimal.stdout
    (state / 'profile').write_text('server\n')

    scripts = source / 'scripts'
    scripts.mkdir()
    (scripts / 'install-tools-unix.sh').write_text("#!/usr/bin/env bash\nprintf 'tool progress\\n'\n")
    (scripts / 'build-zsh-plugins.sh').write_text("#!/usr/bin/env bash\nprintf 'plugin progress\\n'\n")
    sync = run_deps(home, fakebin, 'sync', '--dry-run', '--format=json')
    assert sync.returncode == 0, sync.stderr
    sync_payload = json.loads(sync.stdout)
    assert sync_payload == {
        'command': 'dependencies', 'action': 'sync', 'profile': 'server',
        'dry_run': True, 'status': 'dry-run'
    }
    assert 'tool progress' in sync.stderr and 'plugin progress' in sync.stderr
    assert 'progress' not in sync.stdout

    invalid = run_deps(home, fakebin, 'status', '--dry-run')
    assert invalid.returncode == 2
    assert '--dry-run is only valid with sync.' in invalid.stderr

print('dependency output: PASS')
