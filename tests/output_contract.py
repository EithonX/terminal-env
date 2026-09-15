#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')
OUTPUT = ROOT / 'dot_local/lib/terminal-env/output.sh'
if not BASH:
    raise SystemExit('output contract tests require bash')


def run(script: str, **env_values: str) -> str:
    env = os.environ.copy()
    env.update({'TERM': 'xterm-256color', 'COLUMNS': '80'})
    env.pop('NO_COLOR', None)
    env.update(env_values)
    return subprocess.check_output(
        [BASH, '-c', 'source "$1"; ' + script, 'output-contract', str(OUTPUT)],
        env=env,
        text=True,
    )


auto = run("te_ui_init human auto; te_ui_style warning 'warning'")
assert auto == 'warning' and '\x1b[' not in auto

always = run("te_ui_init human always; te_ui_style warning 'warning'")
assert '\x1b[' in always

no_color = run("te_ui_init human auto; te_ui_style warning 'warning'", NO_COLOR='1')
assert no_color == 'warning'

dumb = run("te_ui_init human auto; te_ui_style warning 'warning'", TERM='dumb')
assert dumb == 'warning'

plain = run("te_ui_init plain always; te_ui_style warning 'warning'")
assert plain == 'warning'

narrow = run("te_ui_init human never; te_ui_row PowerShell 7.6.6", COLUMNS='50')
assert narrow == '  PowerShell\n    7.6.6\n'
normal = run("te_ui_init human never; te_ui_row PowerShell 7.6.6", COLUMNS='80')
assert normal == '  PowerShell        7.6.6\n'
wide = run("te_ui_init human never; te_ui_row PowerShell 7.6.6", COLUMNS='120')
assert wide == '  PowerShell            7.6.6\n'

clean = run("te_ui_clean_text $'ok\\e[31m\\nnext'")
assert '\x1b' not in clean and '\n' not in clean and clean.startswith('ok [31m')

encoded = run("te_ui_json_string $'quote\\\" slash\\\\ esc\\e[31m\\nnext'")
value = json.loads(encoded)
assert '\x1b' not in value and '\n' not in value
assert value.startswith('quote\" slash\\ esc [31m')

print('output contract: PASS')
