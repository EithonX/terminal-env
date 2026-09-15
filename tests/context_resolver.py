#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RESOLVER = ROOT / 'dot_local/bin/executable_terminal-context'
BASH = shutil.which('bash')
GIT = shutil.which('git')
AWK = shutil.which('awk')
GREP = shutil.which('grep')
JQ = shutil.which('jq')
REAL_NODE = shutil.which('node')

if not BASH or not GIT or not AWK or not GREP or not JQ:
    raise SystemExit('context resolver tests require bash, git, awk, grep and jq')


def write_exe(path: Path, body: str) -> None:
    path.write_text('#!/usr/bin/env bash\nset -u\n' + body)
    path.chmod(0o755)


def init_repo(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    subprocess.run([GIT, '-C', str(path), 'init', '-q'], check=True)
    subprocess.run([GIT, '-C', str(path), 'config', 'user.email', 'terminal-env@example.invalid'], check=True)
    subprocess.run([GIT, '-C', str(path), 'config', 'user.name', 'Terminal Env Test'], check=True)
    (path / '.seed').write_text('fixture\n')
    subprocess.run([GIT, '-C', str(path), 'add', '.'], check=True)
    subprocess.run([GIT, '-C', str(path), 'commit', '-qm', 'fixture'], check=True)


def load_context(cwd: Path, env: dict[str, str]) -> dict:
    run_env = os.environ.copy()
    run_env.update(env)
    out = subprocess.check_output(
        [BASH, str(RESOLVER), '--format', 'json', '--cwd', str(cwd)],
        env=run_env,
        text=True,
    )
    return json.loads(out)


def load_human(cwd: Path, env: dict[str, str]) -> str:
    run_env = os.environ.copy()
    run_env.update(env)
    return subprocess.check_output(
        [BASH, str(RESOLVER), '--format', 'human', '--cwd', str(cwd)],
        env=run_env,
        text=True,
    )


def load_plain(cwd: Path, env: dict[str, str]) -> str:
    run_env = os.environ.copy()
    run_env.update(env)
    return subprocess.check_output(
        [BASH, str(RESOLVER), '--format', 'plain', '--cwd', str(cwd)],
        env=run_env,
        text=True,
    )


def fake_environment(base: Path) -> tuple[dict[str, str], Path]:
    fake = base / 'fakebin'
    fake.mkdir()
    log = base / 'tool-invocations.log'
    write_exe(fake / 'node', '''
printf 'node %s offline=%s auto=%s notfound=%s\\n' "${1:-}" "${MISE_OFFLINE:-unset}" "${MISE_AUTO_INSTALL:-unset}" "${MISE_NOT_FOUND_AUTO_INSTALL:-unset}" >> "${TERMINAL_ENV_TEST_LOG}"
if [[ ${1:-} == -e && -n ${REAL_NODE:-} ]]; then exec "$REAL_NODE" "$@"; fi
printf 'v%s\\n' "${FAKE_NODE_VERSION:-22.14.0}"
''')
    write_exe(fake / 'python', '''
printf 'python %s\\n' "${1:-}" >> "${TERMINAL_ENV_TEST_LOG}"
printf 'Python %s\\n' "${FAKE_PYTHON_VERSION:-3.12.7}"
''')
    shutil.copy2(fake / 'python', fake / 'python3')
    (fake / 'python3').chmod(0o755)
    write_exe(fake / 'go', '''
printf 'go %s toolchain=%s offline=%s\\n' "${1:-}" "${GOTOOLCHAIN:-unset}" "${MISE_OFFLINE:-unset}" >> "${TERMINAL_ENV_TEST_LOG}"
printf 'go version go%s test/test\\n' "${FAKE_GO_VERSION:-1.23.4}"
''')
    write_exe(fake / 'rustc', '''
printf 'rustc %s auto=%s\\n' "${1:-}" "${RUSTUP_AUTO_INSTALL:-unset}" >> "${TERMINAL_ENV_TEST_LOG}"
printf 'rustc %s (fixture 2026-01-01)\\n' "${FAKE_RUST_VERSION:-1.85.1}"
''')
    env = {
        'PATH': str(fake) + os.pathsep + os.environ['PATH'],
        'TERMINAL_ENV_TEST_LOG': str(log),
        'FAKE_NODE_VERSION': '22.14.0',
        'FAKE_PYTHON_VERSION': '3.12.7',
        'FAKE_GO_VERSION': '1.23.4',
        'FAKE_RUST_VERSION': '1.85.1',
        'GOTOOLCHAIN': 'local',
    }
    if REAL_NODE:
        env['REAL_NODE'] = REAL_NODE
    return env, log


def clean_log(log: Path) -> None:
    log.unlink(missing_ok=True)


def physical(path: Path) -> str:
    return str(path.resolve())


with tempfile.TemporaryDirectory(prefix='terminal-env-context-') as td:
    base = Path(td)
    env, log = fake_environment(base)

    repo = base / 'quiet'
    init_repo(repo)
    (repo / 'src').mkdir()
    for name in ('index.js', 'tool.py', 'main.go', 'lib.rs'):
        (repo / 'src' / name).write_text('// source only\n')
    clean_log(log)
    ctx = load_context(repo / 'src', env)
    assert ctx['toolchains'] == {}, ctx
    assert ctx['prompt'] == {'text': '', 'state': 'normal'}
    assert not log.exists(), 'source files alone must not execute language runtimes'

    outside = base / '.nvmrc'
    outside.write_text('99\n')
    ctx = load_context(repo / 'src', env)
    assert 'node' not in ctx['toolchains'], 'discovery escaped the repository boundary'

    mono = base / 'mono'
    init_repo(mono)
    (mono / '.nvmrc').write_text('22\n')
    nested = mono / 'services' / 'legacy'
    nested.mkdir(parents=True)
    (nested / '.nvmrc').write_text('20\n')
    env['FAKE_NODE_VERSION'] = '20.11.1'
    ctx = load_context(nested, env)
    node = ctx['toolchains']['node']
    assert node['selector']['value'] == '20'
    assert node['selectors'][0]['source'] == physical(nested / '.nvmrc')
    assert node['prompt'] == 'node 20'
    node_log = log.read_text()
    assert 'offline=true' in node_log and 'auto=false' in node_log and 'notfound=false' in node_log, 'runtime probing must disable mise network/auto-install behavior'
    plain = load_plain(nested, env)
    assert f'context\troot\t{physical(mono)}' in plain
    assert f'toolchain\tnode\tselector\t20\tnvmrc\t{physical(nested / ".nvmrc")}' in plain
    assert 'toolchain\tnode\tactive\t20.11.1\tpath\t' in plain
    assert 'toolchain\tnode\tconflict\tfalse\t\t' in plain
    assert 'prompt\ttext\tnode 20' in plain
    assert 'Project context' not in plain

    (nested / '.node-version').write_text('22\n')
    ctx = load_context(nested, env)
    node = ctx['toolchains']['node']
    assert node['conflict'] is True
    assert node['selector'] is None
    assert node['prompt'] == 'node !'
    assert {x['kind'] for x in node['selectors']} == {'nvmrc', 'node-version'}

    (nested / '.node-version').unlink()
    env['FAKE_NODE_VERSION'] = '24.7.0'
    ctx = load_context(nested, env)
    node = ctx['toolchains']['node']
    assert node['mismatch'] is True
    assert node['prompt'] == 'node 24 ≠ 20'
    assert node['active']['version'] == '24.7.0'

    (nested / '.nvmrc').write_text('lts/*\n')
    ctx = load_context(nested, env)
    node = ctx['toolchains']['node']
    assert node['selector_status'] == 'unknown'
    assert node['mismatch'] is False
    assert node['prompt'] == 'node lts/*'
    (nested / '.nvmrc').write_text('20\n')

    missing_tools = base / 'missing-tools'
    missing_tools.mkdir()
    for name, target in [('git', GIT), ('awk', AWK), ('grep', GREP), ('jq', JQ)]:
        os.symlink(target, missing_tools / name)
    missing_env = env.copy()
    missing_env['PATH'] = str(missing_tools)
    ctx = load_context(nested, missing_env)
    node = ctx['toolchains']['node']
    assert node['missing'] is True
    assert node['active'] is None
    assert node['prompt'] == 'node 20 · missing'

    pkg = base / 'package'
    init_repo(pkg)
    (pkg / 'package.json').write_text(json.dumps({'engines': {'node': '>=22'}}))
    env['FAKE_NODE_VERSION'] = '24.7.0'
    ctx = load_context(pkg, env)
    node = ctx['toolchains']['node']
    assert node['selector'] is None
    assert node['constraint']['kind'] == 'package-engines'
    assert node['constraint_status'] == 'satisfied'
    assert node['prompt'] == 'node ≥22'

    (pkg / 'package.json').write_text(json.dumps({'engines': {'node': '>=22 <24'}}))
    ctx = load_context(pkg, env)
    node = ctx['toolchains']['node']
    assert node['constraint_status'] == 'unknown'
    assert node['mismatch'] is False
    assert node['prompt'] == 'node ≥22 <24'

    (pkg / 'package.json').write_text(json.dumps({'engines': {'node': '22'}}))
    ctx = load_context(pkg, env)
    node = ctx['toolchains']['node']
    assert node['constraint_status'] == 'mismatch'
    assert node['prompt'] == 'node 24 < 22.x'

    (pkg / 'package.json').write_text(json.dumps({'devEngines': {'runtime': 'invalid'}, 'engines': {'node': '>=22'}}))
    ctx = load_context(pkg, env)
    node = ctx['toolchains']['node']
    assert node['selector'] is None
    assert node['constraint']['kind'] == 'package-engines', 'malformed devEngines must not hide valid engines metadata'

    (pkg / 'package.json').write_text(json.dumps({'devEngines': {'runtime': {'name': 'node', 'version': '22'}}}))
    ctx = load_context(pkg, env)
    node = ctx['toolchains']['node']
    assert node['selector']['kind'] == 'package-devEngines'
    assert node['selector']['source'] == physical(pkg / 'package.json')
    assert node['mismatch'] is True

    missing_pkg = base / 'package-missing-node'
    init_repo(missing_pkg)
    (missing_pkg / 'package.json').write_text(json.dumps({'devEngines': {'runtime': {'name': 'node', 'version': '22'}}}))
    ctx = load_context(missing_pkg, missing_env)
    node = ctx['toolchains']['node']
    assert node['selector']['value'] == '22'
    assert node['missing'] is True
    assert node['prompt'] == 'node 22 · missing'

    (pkg / 'package.json').write_text(json.dumps({'name': 'not-a-selector'}))
    clean_log(log)
    ctx = load_context(pkg, env)
    assert 'node' not in ctx['toolchains']
    assert not log.exists(), 'package.json without runtime metadata must not execute node'

    unsafe = base / 'unsafe-metadata'
    init_repo(unsafe)
    (unsafe / '.nvmrc').write_bytes(b'22\x1b]0;unsafe\x07\n')
    clean_log(log)
    ctx = load_context(unsafe, env)
    assert 'node' not in ctx['toolchains'], 'control characters in selectors must be rejected'
    assert not log.exists(), 'rejected selectors must not execute a runtime'
    (unsafe / '.nvmrc').write_text('22\n')
    (unsafe / 'package.json').write_text(json.dumps({'engines': {'node': '>=22\u001b[31m'}}))
    env['FAKE_NODE_VERSION'] = '22.14.0'
    ctx = load_context(unsafe, env)
    node = ctx['toolchains']['node']
    assert node['selector']['value'] == '22'
    assert node['constraint'] is None, 'control characters in constraints must be rejected'
    assert '\x1b' not in ctx['prompt']['text']

    unsafe_path = base / 'unsafe-path-\x1b[31m'
    init_repo(unsafe_path)
    human = load_human(unsafe_path, env)
    assert '\x1b' not in human, 'human output must neutralize terminal control characters in paths'
    plain = load_plain(unsafe_path, env)
    assert '\x1b' not in plain, 'plain output must neutralize terminal control characters in paths'

    pyrepo = base / 'python'
    init_repo(pyrepo)
    (pyrepo / 'pyproject.toml').write_text('[project]\nname = "fixture"\nrequires-python = ">=3.12" # inline comment\n')
    env['FAKE_PYTHON_VERSION'] = '3.11.9'
    ctx = load_context(pyrepo, env)
    py = ctx['toolchains']['python']
    assert py['constraint']['kind'] == 'pyproject-requires-python'
    assert py['mismatch'] is True
    assert py['prompt'] == 'py 3.11 < ≥3.12'

    (pyrepo / '.python-version').write_text('3.11\n')
    env['FAKE_PYTHON_VERSION'] = '3.11.9'
    ctx = load_context(pyrepo, env)
    py = ctx['toolchains']['python']
    assert py['selector']['value'] == '3.11'
    assert py['mismatch'] is True
    assert py['prompt'] == 'py 3.11 < ≥3.12'

    (pyrepo / '.python-version').write_text('3.12 3.11\n')
    env['FAKE_PYTHON_VERSION'] = '3.12.8'
    ctx = load_context(pyrepo, env)
    py = ctx['toolchains']['python']
    assert py['selector']['value'] == '3.12'
    assert py['prompt'] == 'py 3.12'

    venvrepo = base / 'venv'
    init_repo(venvrepo)
    venv_python = venvrepo / '.venv' / 'bin' / 'python'
    venv_python.parent.mkdir(parents=True)
    write_exe(venv_python, "printf 'Python 3.13.2\\n'\n")
    venv_env = env.copy()
    venv_env['VIRTUAL_ENV'] = str(venvrepo / '.venv')
    venv_env['PATH'] = str(venv_python.parent) + os.pathsep + env['PATH']
    ctx = load_context(venvrepo, venv_env)
    py = ctx['toolchains']['python']
    assert py['selectors'][0]['kind'] == 'virtualenv'
    assert py['active']['path'] == str(venv_python)

    gorepo = base / 'go'
    init_repo(gorepo)
    (gorepo / 'go.mod').write_text('module example.test/fixture\n\ngo 1.23\ntoolchain go1.24.1\n')
    env['FAKE_GO_VERSION'] = '1.23.4'
    env['GOTOOLCHAIN'] = 'local'
    ctx = load_context(gorepo, env)
    go = ctx['toolchains']['go']
    assert go['selector']['value'] == 'go1.24.1'
    assert go['constraint']['value'] == '1.23'
    assert go['mismatch'] is True
    assert go['prompt'] == 'go 1.23.4 ≠ 1.24.1'

    env['FAKE_GO_VERSION'] = '1.25.0'
    ctx = load_context(gorepo, env)
    go = ctx['toolchains']['go']
    assert go['mismatch'] is False, 'a newer local Go satisfies a toolchain suggestion'
    assert go['prompt'] == 'go 1.24.1'

    workspace = gorepo / 'workspace'
    workspace.mkdir()
    (gorepo / 'go.work').write_text('go 1.24\ntoolchain go1.24.2\n')
    (workspace / 'go.mod').write_text('module example.test/inner\ngo 1.20\n')
    env['FAKE_GO_VERSION'] = '1.24.3'
    ctx = load_context(workspace, env)
    go = ctx['toolchains']['go']
    assert go['constraint']['source'] == physical(gorepo / 'go.work')
    assert go['constraint']['value'] == '1.24'
    assert go['selector']['value'] == 'go1.24.2'

    env['FAKE_GO_VERSION'] = '1.22.0'
    env['GOTOOLCHAIN'] = 'auto'
    ctx = load_context(gorepo, env)
    go = ctx['toolchains']['go']
    assert go['active'] is None
    assert go['missing'] is False
    assert go['note'] and 'automatic toolchain selection' in go['note']
    assert go['prompt'] == 'go 1.24.2 · active?'
    assert go['state'] == 'warning'

    rustrepo = base / 'rust'
    init_repo(rustrepo)
    (rustrepo / 'rust-toolchain.toml').write_text('[toolchain]\nchannel = "1.85"\n')
    (rustrepo / 'Cargo.toml').write_text('[package]\nname = "fixture"\nversion = "0.1.0"\nrust-version = "1.80"\n')
    env['FAKE_RUST_VERSION'] = '1.84.0'
    clean_log(log)
    ctx = load_context(rustrepo, env)
    rust = ctx['toolchains']['rust']
    assert rust['mismatch'] is True
    assert rust['prompt'] == 'rust 1.84 ≠ 1.85'
    assert 'auto=0' in log.read_text(), 'rustc probing must disable rustup auto-install'

    (rustrepo / 'rust-toolchain').write_text('1.84\n')
    env['FAKE_RUST_VERSION'] = '1.84.1'
    ctx = load_context(rustrepo, env)
    rust = ctx['toolchains']['rust']
    assert rust['selector']['value'] == '1.84', 'rust-toolchain must win the documented same-directory tie'

    versions = base / 'versions'
    init_repo(versions)
    (versions / '.tool-versions').write_text('nodejs 22\npython 3.12\ngolang 1.23\nrust 1.85\n')
    (versions / 'mise.toml').write_text('[tools]\nnode = "22.1"\npython = "3.12.4"\n')
    env.update(FAKE_NODE_VERSION='22.1.5', FAKE_PYTHON_VERSION='3.12.4', FAKE_GO_VERSION='1.23.6', FAKE_RUST_VERSION='1.85.1', GOTOOLCHAIN='local')
    ctx = load_context(versions, env)
    assert ctx['toolchains']['node']['conflict'] is False
    assert ctx['toolchains']['python']['conflict'] is False
    assert ctx['toolchains']['go']['selector']['value'] == '1.23'
    assert ctx['toolchains']['rust']['selector']['value'] == '1.85'

    mise_repo = base / 'mise-nearest'
    init_repo(mise_repo)
    (mise_repo / '.mise.toml').write_text('[tools]\nnode = "22"\n')
    mise_nested = mise_repo / 'apps' / 'legacy'
    mise_nested.mkdir(parents=True)
    (mise_nested / '.mise.toml').write_text('[tools]\nnode = "20" # nearest override\n')
    env['FAKE_NODE_VERSION'] = '20.12.0'
    ctx = load_context(mise_nested, env)
    node = ctx['toolchains']['node']
    assert node['conflict'] is False
    assert node['selector']['value'] == '20'
    assert node['selector']['source'] == physical(mise_nested / '.mise.toml')

    (mise_nested / 'mise.toml').write_text('[tools]\nnode = "22"\n')
    ctx = load_context(mise_nested, env)
    node = ctx['toolchains']['node']
    assert node['conflict'] is True
    assert node['selector'] is None

    detached = base / 'detached'
    init_repo(detached)
    subprocess.run([GIT, '-C', str(detached), 'checkout', '--detach', '-q'], check=True)
    ctx = load_context(detached, env)
    assert ctx['repository']['detached'] is True
    assert ctx['repository']['branch'] is None
    assert ctx['repository']['commit']

    link = base / 'linked-repo'
    init_repo(link)
    (link / 'sub').mkdir()
    symlink = base / 'repo-link'
    try:
        symlink.symlink_to(link, target_is_directory=True)
        ctx = load_context(symlink / 'sub', env)
        assert ctx['root'] == str(link.resolve())
    except (OSError, NotImplementedError):
        pass

    worktree_source = base / 'worktree-source'
    init_repo(worktree_source)
    (worktree_source / '.nvmrc').write_text('22\n')
    subprocess.run([GIT, '-C', str(worktree_source), 'add', '.nvmrc'], check=True)
    subprocess.run([GIT, '-C', str(worktree_source), 'commit', '-qm', 'selector'], check=True)
    worktree = base / 'worktree'
    subprocess.run([GIT, '-C', str(worktree_source), 'worktree', 'add', '-q', '-b', 'fixture-worktree', str(worktree)], check=True)
    env['FAKE_NODE_VERSION'] = '22.3.0'
    ctx = load_context(worktree, env)
    assert ctx['root'] == str(worktree.resolve())
    assert ctx['toolchains']['node']['selector']['value'] == '22'

    nongit_parent = base / 'nongit-parent'
    child = nongit_parent / 'child'
    child.mkdir(parents=True)
    (nongit_parent / '.node-version').write_text('99\n')
    ctx = load_context(child, env)
    assert ctx['repository']['name'] is None
    assert 'node' not in ctx['toolchains'], 'non-repository discovery must stay in the current directory'

print('context resolver: PASS')
