#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
readme = (ROOT / 'README.md').read_text()

headings = re.findall(r'^## (.+)$', readme, flags=re.MULTILINE)
required = ['Install', 'What you get', 'Everyday commands', 'Daily keys', 'Backups and recovery', 'Documentation']
for heading in required:
    assert heading in headings, f'missing README section: {heading}'
assert headings.index('Install') < headings.index('What you get') < headings.index('Everyday commands')
assert headings[-1] == 'Documentation'

assert '\nPS> ' not in readme
assert re.search(r'(?m)^\$ ', readme) is None
assert 'shields.io' not in readme

for target in re.findall(r'\[[^\]]+\]\(([^)]+\.md)\)', readme):
    assert (ROOT / target).is_file(), f'broken local documentation link: {target}'

for name in ('ARCHITECTURE.md', 'SECURITY.md', 'CONTRIBUTING.md'):
    text = (ROOT / name).read_text()
    assert text.startswith('# '), f'{name} needs a single document title'

print('docs quality: PASS')
