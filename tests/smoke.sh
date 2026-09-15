#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_only=0; [[ ${1:-} == --source-only ]] && source_only=1
fail=0
bad(){ echo "FAIL: $*" >&2; fail=1; }
check(){ "$@" || bad "$*"; }
check bash -n "$ROOT/bootstrap.sh" "$ROOT/install.sh" "$ROOT/uninstall.sh"
while IFS= read -r -d '' f; do check bash -n "$f"; done < <(find "$ROOT/scripts" "$ROOT/dot_local/bin" "$ROOT/dot_local/lib" -type f -print0)
check bash "$ROOT/bootstrap.sh" --help >/dev/null
if bash "$ROOT/bootstrap.sh" --terminal-env-invalid-option >/dev/null 2>&1; then bad 'bootstrap.sh accepts unknown options'; fi
bash "$ROOT/bootstrap.sh" --format json --color never --quiet --help >/dev/null 2>&1 || bad 'bootstrap.sh rejects installer output options'
if bash "$ROOT/bootstrap.sh" --format xml >/dev/null 2>&1; then bad 'bootstrap.sh accepts invalid output format'; fi
if bash "$ROOT/bootstrap.sh" --branch ../bad >/dev/null 2>&1; then bad 'bootstrap.sh accepts unsafe branch names'; fi
cli_home=$(mktemp -d)
trap 'rm -rf "$cli_home"' EXIT
mkdir -p "$cli_home/.local/share/terminal-env/source"
cp "$ROOT/versions.env" "$cli_home/.local/share/terminal-env/source/versions.env"
for cmd in terminal-backup terminal-context terminal-deps terminal-doctor terminal-rollback terminal-update; do
  HOME="$cli_home" bash "$ROOT/dot_local/bin/executable_$cmd" --help >/dev/null 2>&1 || bad "$cmd --help"
  if HOME="$cli_home" bash "$ROOT/dot_local/bin/executable_$cmd" --terminal-env-invalid-option >/dev/null 2>&1; then bad "$cmd accepts unknown options"; fi
done
HOME="$cli_home" bash "$ROOT/dot_local/bin/executable_terminal" --help >/dev/null 2>&1 || bad 'terminal --help'
if HOME="$cli_home" bash "$ROOT/dot_local/bin/executable_terminal" terminal-env-invalid-command >/dev/null 2>&1; then bad 'terminal accepts unknown commands'; fi

# Regression coverage for helpers that run under `set -u`. Keep dependent
# assignments out of a single `local` statement: Bash expands the RHS before
# the sibling local assignment is visible.
(
  set -Eeuo pipefail
  source "$ROOT/scripts/lib/common.sh"
  t=$(mktemp -d)
  trap 'rm -rf "$t"' EXIT
  printf 'ok\n' > "$t/source"
  atomic_install_file "$t/source" "$t/dest" 0600
  [[ $(cat "$t/dest") == ok ]]
  mkdir -p "$t/archive/bin"
  printf '#!/bin/sh\nexit 0\n' > "$t/archive/bin/probe"
  chmod +x "$t/archive/bin/probe"
  tar -czf "$t/probe.tar.gz" -C "$t/archive" .
  install_archive_binary "$t/probe.tar.gz" probe "$t/probe"
  [[ -x "$t/probe" ]]
) || bad 'nounset-safe install helpers'

( HOME=$(mktemp -d) DRY_RUN=1 bash "$ROOT/scripts/build-zsh-plugins.sh" >/dev/null ) || bad 'nounset-safe plugin provisioning'
python3 -m json.tool "$ROOT/dot_config/oh-my-posh/terminal.omp.json" >/dev/null || bad 'Oh My Posh JSON'
python3 -m json.tool "$ROOT/dot_config/windows-terminal/terminal-env.json" >/dev/null || bad 'Windows Terminal JSON'
python3 "$ROOT/tests/visual_foundation.py" >/dev/null || bad 'visual foundation invariants'
python3 "$ROOT/tests/output_contract.py" >/dev/null || bad 'shared output contract'
python3 "$ROOT/tests/context_resolver.py" >/dev/null || bad 'context resolver behavior'
python3 "$ROOT/tests/doctor_output.py" >/dev/null || bad 'doctor output behavior'
python3 "$ROOT/tests/deps_output.py" >/dev/null || bad 'dependency output behavior'
python3 "$ROOT/tests/update_output.py" >/dev/null || bad 'update output behavior'
python3 "$ROOT/tests/backup_output.py" >/dev/null || bad 'backup output behavior'
python3 "$ROOT/tests/rollback_output.py" >/dev/null || bad 'rollback output behavior'
python3 "$ROOT/tests/installer_output.py" >/dev/null || bad 'installer output behavior'
python3 "$ROOT/tests/uninstall_output.py" >/dev/null || bad 'uninstall output behavior'
python3 "$ROOT/tests/terminal_cli.py" >/dev/null || bad 'unified terminal CLI behavior'
python3 "$ROOT/tests/docs_quality.py" >/dev/null || bad 'documentation quality'
ROOT_FOR_PY="$ROOT" python3 - <<'PY' || bad 'configuration invariants'
import json, os, pathlib, re
r=pathlib.Path(os.environ['ROOT_FOR_PY'])
t=json.loads((r/'dot_config/oh-my-posh/terminal.omp.json').read_text())
assert t.get('streaming') == 100
assert t.get('shell_integration') is True
v=(r/'versions.env').read_text()
assert 'OH_MY_POSH_VERSION=31.3.0' in v
alltext='\n'.join(p.read_text(errors='ignore') for p in r.rglob('*') if p.is_file() and '.git' not in p.parts)
assert 'ZSH_AUTOSUGGESTIONS_REF=v0.7.1' in v
assert 'DEJA_VERSION=' not in v
assert ('ANTIDOTE'+'_VERSION=') not in v
# chezmoi executable_ is a regular-file attribute, not a directory attribute.
# Helpers must live under dot_local/bin/executable_<name>.
assert not (r/'executable_dot_local').exists()
unified = r/'dot_local/bin/executable_terminal'
assert unified.is_file() and unified.read_text().startswith('#!/usr/bin/env bash')
helpers = sorted((r/'dot_local/bin').glob('executable_terminal-*'))
assert [p.name for p in helpers] == [
    'executable_terminal-backup',
    'executable_terminal-context',
    'executable_terminal-deps',
    'executable_terminal-doctor',
    'executable_terminal-rollback',
    'executable_terminal-update',
]
for p in helpers:
    assert p.read_text().startswith('#!/usr/bin/env bash')
ignore=(r/'.chezmoiignore.tmpl').read_text()
assert '.local/bin/terminal\n.local/bin/terminal-*' in ignore
# Prompt should stay compact, transcript-friendly and one-line.
assert 'transient_prompt' not in t
blob = json.dumps(t, ensure_ascii=False)
prompt_blob = json.dumps([b for b in t.get('blocks', []) if b.get('type') == 'prompt'], ensure_ascii=False)
assert '❯' in blob
assert '│' in blob
assert 'ROOT' not in prompt_blob and 'ADMIN' not in prompt_blob
assert '{{ if .Root }}#{{ else }}❯{{ end }}' in prompt_blob
assert 'if .Root' in t.get('console_title_template', '')
assert '╭─' not in blob
assert '╰─' not in blob
# Native ls may gain color but must never be replaced by eza.
tools=(r/'dot_config/zsh/conf.d/40-tools.zsh').read_text()
assert "alias ls='ls --color=auto'" in tools
assert "alias ls='eza" not in tools
# Atuin ships with a matching custom theme.
atuin=(r/'dot_config/atuin/config.toml').read_text()
assert 'name = \"terminal-env\"' in atuin
assert (r/'dot_config/atuin/themes/terminal-env.toml').is_file()
wt=json.loads((r/'dot_config/windows-terminal/terminal-env.json').read_text())
updates={p.get('updates'):p for p in wt.get('profiles',[]) if isinstance(p,dict) and p.get('updates')}
assert updates['{574e775e-4f2a-5b96-ac1e-a2962a402336}']['hidden'] is True
assert updates['{5fb123f1-af88-5b5c-8953-d14a8def1978}']['hidden'] is True
keys=(r/'dot_config/zsh/conf.d/70-keybindings.zsh').read_text()
for seq,widget in (("^[[C","forward-char"),("^[OC","forward-char"),("^[[D","backward-char"),("^[OD","backward-char"),("^[[1;5C","forward-word"),("^[[1;5D","backward-word")):
    assert f"bindkey '{seq}' {widget}" in keys
prompt=(r/'dot_config/zsh/conf.d/90-prompt.zsh').read_text()
assert 'EUID == 0' in prompt and 'ROOT' not in prompt and '%F{#e07880}#%f' in prompt
psprofile=(r/'dot_config/terminal-env/powershell/profile.ps1').read_text()
assert 'RightArrow -Function ForwardChar' in psprofile
assert 'Ctrl+RightArrow -Function ForwardWord' in psprofile
assert 'RightArrow -Function AcceptSuggestion' not in psprofile
assert 'Ctrl+RightArrow -Function AcceptNextSuggestionWord' not in psprofile
unix_tools=(r/'scripts/install-tools-unix.sh').read_text()
assert 'already installed' in unix_tools
assert 'installed_version=' in unix_tools
win_install=(r/'install.ps1').read_text()
assert 'GITHUB_TOKEN' in win_install and 'GH_TOKEN' in win_install
assert 'already installed' in win_install
pred=(r/'dot_config/zsh/conf.d/60-prediction.zsh').read_text()
assert 'ZSH_AUTOSUGGEST_STRATEGY=(terminal_env_autosuggest)' in pred
assert '_zsh_autosuggest_strategy_completion' in pred
assert '_zsh_autosuggest_strategy_history' in pred
update=(r/'dot_local/bin/executable_terminal-update').read_text()
assert 'install-tools-unix.sh' not in update
assert 'SYNC_PLUGINS=0' in update
assert (r/'dot_local/bin/executable_terminal-deps').is_file()
install_unix=(r/'scripts/install-tools-unix.sh').read_text()
assert 'local pkgs=(zsh ' not in install_unix
assert 'optional+=(shellcheck' not in install_unix
assert 'Monaspace.tar.xz' in install_unix
assert 'Monaspace.zip' not in install_unix
assert 'already installed' in install_unix and 'installed_version=' in install_unix
assert 'install_chezmoi' in install_unix and 'twpayne/chezmoi' in install_unix
common=(r/'scripts/lib/common.sh').read_text()
assert 'https://github.com/$repo/releases/download/$tag/$asset' in common
assert 'GITHUB_TOKEN' in common and 'GH_TOKEN' in common
bootstrap_sh=(r/'bootstrap.sh').read_text()
assert 'https://github.com/EithonX/terminal-env.git' in bootstrap_sh
assert 'TERMINAL_ENV_REPO' in bootstrap_sh
assert 'git clone --quiet --depth 1 --single-branch --branch' in bootstrap_sh
assert 'Homebrew/install/HEAD/install.sh' in bootstrap_sh
assert 'brew --version' in bootstrap_sh and 'apt-get' in bootstrap_sh
for face in ('Regular','Bold','Italic','BoldItalic'):
    assert face in install_unix
installer=(r/'install.sh').read_text()
assert 'Do not run Terminal Environment with sudo' in installer
assert 'backups/transactions/install-' in installer
assert 'prune_transaction_backups 3' in installer
manual=(r/'dot_local/bin/executable_terminal-backup').read_text()
assert 'backups/manual' in manual
ps=(r/'install.ps1').read_text()
assert 'Monaspace.tar.xz' in ps and 'Monaspace.zip' not in ps
assert 'Prune-TransactionBackups 3' in ps
assert 'already installed' in ps
assert 'Repair-WinGetPackageManager -Force -Latest' in ps
assert 'https://github.com/$Repo/releases/download/$Tag/$Name' in ps
bootstrap_ps=(r/'bootstrap.ps1').read_text()
assert 'Repair-WinGetPackageManager -Force -Latest' in bootstrap_ps
assert "'-ExecutionPolicy','Bypass'" in bootstrap_ps
assert 'clone --quiet --depth 1 --single-branch --branch' in bootstrap_ps
readme=(r/'README.md').read_text()
assert 'irm https://raw.githubusercontent.com/EithonX/terminal-env/master/bootstrap.ps1 | iex' in readme
assert 'curl -fsSL https://raw.githubusercontent.com/EithonX/terminal-env/master/bootstrap.sh | bash' in readme
assert "--proto '=https'" not in readme and '/bin/bash -c "$(curl' not in readme
workflow=(r/'.github/workflows/ci.yml').read_text()
assert 'ludeeus/action-shellcheck@00cae500b08a931fb5698e11e79bfbd38e612a38e' in workflow
assert 'version: v0.11.0' in workflow
assert 'severity: warning' in workflow
assert 'macos-latest' in workflow and workflow.count('ubuntu-latest') >= 2
for f in ('scripts/lib/common.sh','scripts/install-tools-unix.sh','uninstall.sh','dot_local/bin/executable_terminal-doctor'):
    assert '-maxdepth' not in (r/f).read_text(), f'{f} uses GNU-only find -maxdepth'
PY
# Windows state writes must never rely on Set-Content positional binding.
ROOT_FOR_PY="$ROOT" python3 - <<'PY2' || bad 'PowerShell Set-Content safety'
import os
from pathlib import Path
r=Path(os.environ['ROOT_FOR_PY'])
for p in r.rglob('*.ps1'):
    if 'tests' in p.parts:
        continue
    for no,line in enumerate(p.read_text(errors='ignore').splitlines(), 1):
        stripped=line.lstrip()
        if stripped.startswith('#') or 'Set-Content' not in line:
            continue
        if '-LiteralPath' not in line and '-Path' not in line:
            raise SystemExit(f'{p}:{no}: Set-Content path is positional')
        if '-Value' not in line:
            raise SystemExit(f'{p}:{no}: Set-Content value is positional')
PY2
# Doctor must use a bounded Atuin search; `atuin history list` has no --limit flag.
if grep -RIn -- 'atuin history list --limit' "$ROOT/dot_local" "$ROOT/dot_config/terminal-env/powershell" >/dev/null 2>&1; then
  bad 'invalid Atuin doctor command'
fi
if command -v zsh >/dev/null 2>&1; then
  while IFS= read -r -d '' f; do check zsh -n "$f"; done < <(find "$ROOT/dot_config/zsh" -type f -name '*.zsh' -print0)
  ROOT_FOR_ZSH="$ROOT" zsh -dfc '
    source "$ROOT_FOR_ZSH/dot_config/zsh/conf.d/60-prediction.zsh"
    _zsh_autosuggest_strategy_history() { typeset -g suggestion="H:$1" }
    _zsh_autosuggest_strategy_completion() { typeset -g suggestion="C:$1" }
    _zsh_autosuggest_strategy_terminal_env_autosuggest "dock"
    [[ $suggestion == "H:dock" ]] || exit 11
    _zsh_autosuggest_strategy_terminal_env_autosuggest "cat PRO"
    [[ $suggestion == "C:cat PRO" ]] || exit 12
    _zsh_autosuggest_strategy_completion() { typeset -g suggestion="" }
    _zsh_autosuggest_strategy_terminal_env_autosuggest "docker compose x"
    [[ $suggestion == "H:docker compose x" ]] || exit 13
    _zsh_autosuggest_strategy_terminal_env_autosuggest $'"'"'echo a\necho b'"'"'
    [[ $suggestion == H:* ]] || exit 14
  ' || bad 'context-aware autosuggestion strategy'
  ROOT_FOR_ZSH="$ROOT" zsh -dfc '
    export XDG_CACHE_HOME=$(mktemp -d)
    trap "rm -rf $XDG_CACHE_HOME" EXIT
    export TERM=xterm-256color
    unset NO_COLOR FZF_DEFAULT_OPTS
    source "$ROOT_FOR_ZSH/dot_config/zsh/conf.d/40-tools.zsh"
    [[ $FZF_DEFAULT_OPTS == *--style=minimal* ]] || exit 21
    [[ $FZF_DEFAULT_OPTS != *--border=rounded* ]] || exit 22
    [[ $FZF_DEFAULT_OPTS == *--color=bg+:#151b22* ]] || exit 23
  ' || bad 'fzf visual defaults'
  ROOT_FOR_ZSH="$ROOT" zsh -dfc '
    export XDG_CACHE_HOME=$(mktemp -d)
    trap "rm -rf $XDG_CACHE_HOME" EXIT
    export TERM=xterm-256color NO_COLOR=1
    unset FZF_DEFAULT_OPTS
    source "$ROOT_FOR_ZSH/dot_config/zsh/conf.d/40-tools.zsh"
    [[ $FZF_DEFAULT_OPTS == *--no-color* ]] || exit 24
    [[ $FZF_DEFAULT_OPTS != *--color=* ]] || exit 25
    export LS_COLORS=sentinel
    source "$ROOT_FOR_ZSH/dot_config/zsh/conf.d/25-colors.zsh"
    [[ -z ${LS_COLORS+x} ]] || exit 26
  ' || bad 'NO_COLOR shell behavior'
  ROOT_FOR_ZSH="$ROOT" zsh -dfc '
    export XDG_CACHE_HOME=$(mktemp -d)
    trap "rm -rf $XDG_CACHE_HOME" EXIT
    export TERM=xterm-256color
    unset NO_COLOR
    typeset -gA ZSH_HIGHLIGHT_STYLES
    source "$ROOT_FOR_ZSH/dot_config/zsh/conf.d/99-highlighting.zsh"
    [[ ${ZSH_HIGHLIGHT_STYLES[command]} == "fg=#7cc4e4,bold" ]] || exit 27
    [[ ${ZSH_HIGHLIGHT_STYLES[single-quoted-argument]} == "fg=#e6ebf0" ]] || exit 28
    [[ ${ZSH_HIGHLIGHT_STYLES[redirection]} == "fg=#707c88" ]] || exit 29
  ' || bad 'tonal Zsh highlighting'
  ROOT_FOR_ZSH="$ROOT" zsh -dfc '
    export TERM=dumb NO_COLOR=1 SSH_CONNECTION=fixture
    source "$ROOT_FOR_ZSH/dot_config/zsh/conf.d/90-prompt.zsh"
    [[ $PROMPT != *"%F{"* ]] || exit 30
    [[ $PROMPT == *"%m  %~ │ "* ]] || exit 31
  ' || bad 'plain fallback prompt'
  ROOT_FOR_ZSH="$ROOT" zsh -dfc '
    export HOME=$(mktemp -d) TERM=dumb NO_COLOR=1
    trap "rm -rf $HOME" EXIT
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/terminal-context" <<"EOF"
#!/bin/sh
printf "warning\tnode 24 ≠ 22 · 100%%\n"
EOF
    chmod +x "$HOME/.local/bin/terminal-context"
    source "$ROOT_FOR_ZSH/dot_config/zsh/conf.d/90-prompt.zsh"
    [[ $TERMINAL_ENV_PROJECT_CONTEXT == "node 24 ≠ 22 · 100%" ]] || exit 32
    [[ $PROMPT == *"node 24 ≠ 22 · 100%%"* ]] || exit 33
    [[ $PROMPT != *"%F{"* ]] || exit 34
  ' || bad 'fallback prompt project context'
fi
(( source_only )) || echo "smoke: $([[ $fail == 0 ]] && echo PASS || echo FAIL)"
exit "$fail"

