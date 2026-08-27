#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_only=0; [[ ${1:-} == --source-only ]] && source_only=1
fail=0
bad(){ echo "FAIL: $*" >&2; fail=1; }
check(){ "$@" || bad "$*"; }
check bash -n "$ROOT/install.sh" "$ROOT/uninstall.sh"
while IFS= read -r -d '' f; do check bash -n "$f"; done < <(find "$ROOT/scripts" "$ROOT/dot_local/bin" -type f -print0)

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
python3 - <<PY || bad 'configuration invariants'
import json, pathlib, re
r=pathlib.Path(r'''$ROOT''')
t=json.loads((r/'dot_config/oh-my-posh/terminal.omp.json').read_text())
assert t.get('streaming') == 100
assert t.get('shell_integration') is True
v=(r/'versions.env').read_text()
assert 'OH_MY_POSH_VERSION=30.7.0' in v
alltext='\n'.join(p.read_text(errors='ignore') for p in r.rglob('*') if p.is_file() and '.git' not in p.parts)
assert 'ZSH_AUTOSUGGESTIONS_REF=v0.7.1' in v
assert 'DEJA_VERSION=' not in v
assert ('ANTIDOTE'+'_VERSION=') not in v
# chezmoi executable_ is a regular-file attribute, not a directory attribute.
# Helpers must live under dot_local/bin/executable_<name>.
assert not (r/'executable_dot_local').exists()
helpers = sorted((r/'dot_local/bin').glob('executable_terminal-*'))
assert [p.name for p in helpers] == [
    'executable_terminal-backup',
    'executable_terminal-deps',
    'executable_terminal-doctor',
    'executable_terminal-rollback',
    'executable_terminal-update',
]
for p in helpers:
    assert p.read_text().startswith('#!/usr/bin/env bash')
# Prompt should stay compact, transcript-friendly and one-line.
assert 'transient_prompt' not in t
blob = json.dumps(t, ensure_ascii=False)
assert '❯' in blob
assert '│' in blob
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
pred=(r/'dot_config/zsh/conf.d/60-prediction.zsh').read_text()
assert 'ZSH_AUTOSUGGEST_STRATEGY=(terminal_env_autosuggest)' in pred
assert '_zsh_autosuggest_strategy_completion' in pred
assert '_zsh_autosuggest_strategy_history' in pred
update=(r/'dot_local/bin/executable_terminal-update').read_text()
assert 'install-tools-unix.sh' not in update
assert 'SYNC_PLUGINS=0' in update
assert (r/'dot_local/bin/executable_terminal-deps').is_file()
PY
# Windows state writes must never rely on Set-Content positional binding.
python3 - <<'PY2' || bad 'PowerShell Set-Content safety'
from pathlib import Path
r=Path(r'''$ROOT''')
for p in r.rglob('*.ps1'):
    for no,line in enumerate(p.read_text(errors='ignore').splitlines(), 1):
        if 'Set-Content' in line and not line.lstrip().startswith('#'):
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
fi
if command -v shellcheck >/dev/null 2>&1; then shellcheck -x "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/scripts/"*.sh "$ROOT/scripts/lib/"*.sh "$ROOT/dot_local/bin/executable_terminal-"* || fail=1; fi
(( source_only )) || echo "smoke: $([[ $fail == 0 ]] && echo PASS || echo FAIL)"
exit "$fail"

