#!/usr/bin/env python3
import json
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

EXPECTED = {
    "bg": "#0A0E13",
    "surface": "#151B22",
    "surface_active": "#1B232D",
    "line": "#28323D",
    "text": "#E6EBF0",
    "soft": "#A2ACB7",
    "muted": "#707C88",
    "accent": "#7CC4E4",
    "warning": "#D6A85F",
    "danger": "#E07880",
    "success": "#8BB594",
}


def fail(message: str) -> None:
    raise AssertionError(message)


def read_json(path: str):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def read_toml(path: str):
    return tomllib.loads((ROOT / path).read_text(encoding="utf-8"))


def parse_simple_config(path: str):
    values = {}
    palettes = {}
    for raw in (ROOT / path).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        if key == "palette":
            index, color = value.split("=", 1)
            palettes[int(index)] = color.lower()
        elif key not in values:
            values[key] = value.strip('"').lower()
    return values, palettes


tokens = read_json("dot_config/terminal-env/theme.json")
if tokens != EXPECTED:
    fail("semantic token manifest differs from the design-system palette")

omp = read_json("dot_config/oh-my-posh/terminal.omp.json")
if omp.get("palette") != EXPECTED:
    fail("Oh My Posh palette is not sourced from the semantic design roles")
plain_palette = omp.get("palettes", {}).get("list", {}).get("plain", {})
if plain_palette != {key: "transparent" for key in EXPECTED}:
    fail("Oh My Posh NO_COLOR palette does not preserve prompt structure without chromatic roles")
if ".Env.NO_COLOR" not in omp.get("palettes", {}).get("template", ""):
    fail("Oh My Posh palette selection does not honor NO_COLOR")
if "transient_prompt" in omp:
    fail("persistent prompt contract regressed to a transient prompt")
segments = [segment for block in omp.get("blocks", []) if block.get("type") == "prompt" for segment in block.get("segments", [])]
segment_types = [segment.get("type") for segment in segments]
for runtime in ("node", "python", "go", "rust"):
    if runtime in segment_types:
        fail(f"unresolved runtime segment remains in the prompt: {runtime}")
status_segments = [segment for segment in segments if segment.get("type") == "status"]
if len(status_segments) != 1 or status_segments[0].get("options", {}).get("always_enabled") is not False:
    fail("previous-command failure context is not a single exception-only status segment")
prompt_text = json.dumps(segments, ensure_ascii=False)
if any(0xE000 <= ord(char) <= 0xF8FF for char in prompt_text):
    fail("persistent prompt contains a private-use glyph")
if "{{ if .Root }}#{{ else }}❯{{ end }}" not in prompt_text:
    fail("compact elevated marker is missing")

completion = (ROOT / "dot_config/zsh/conf.d/30-completion.zsh").read_text(encoding="utf-8")
if "--border=rounded" in completion or "--border rounded" in completion:
    fail("fzf-tab still uses decorative rounded framing")
if "--style=minimal" not in completion or "--no-color" not in completion:
    fail("fzf-tab does not follow the minimal/NO_COLOR visual contract")
for legacy_color in ("#98a6b3", "#f38ba8"):
    if legacy_color in completion.lower():
        fail("Zsh completion retains a legacy non-semantic color")

tmux = (ROOT / "dot_config/tmux/tmux.conf").read_text(encoding="utf-8")
tmux_escape_time = None
for raw in tmux.splitlines():
    fields = raw.strip().split()
    if len(fields) == 4 and fields[0] in {"set", "set-option"} and fields[1] == "-sg" and fields[2] == "escape-time":
        try:
            tmux_escape_time = int(fields[3])
        except ValueError:
            pass
        break
if tmux_escape_time is None or tmux_escape_time < 500:
    fail("tmux escape-time is too short for reliable terminal-query replies over SSH")

atuin = read_toml("dot_config/atuin/themes/terminal-env.toml")["colors"]
atuin_expected = {
    "AlertInfo": EXPECTED["accent"],
    "AlertWarn": EXPECTED["warning"],
    "AlertError": EXPECTED["danger"],
    "Annotation": EXPECTED["muted"],
    "Base": EXPECTED["text"],
    "Guidance": EXPECTED["soft"],
    "Important": EXPECTED["accent"],
    "Title": EXPECTED["text"],
    "Muted": EXPECTED["muted"],
    "SyntaxCommand": EXPECTED["accent"],
    "SyntaxFlag": EXPECTED["soft"],
    "SyntaxString": EXPECTED["text"],
    "SyntaxVariable": EXPECTED["soft"],
    "SyntaxOperator": EXPECTED["muted"],
    "SyntaxComment": EXPECTED["muted"],
}
if atuin != atuin_expected:
    fail("Atuin semantic roles do not match the Terminal Environment palette")

wt = read_json("dot_config/windows-terminal/terminal-env.json")["schemes"][0]
wt_expected = {
    "background": EXPECTED["bg"],
    "foreground": EXPECTED["text"],
    "cursorColor": EXPECTED["accent"],
    "selectionBackground": EXPECTED["surface_active"],
    "red": EXPECTED["danger"],
    "green": EXPECTED["success"],
    "yellow": EXPECTED["warning"],
    "cyan": EXPECTED["accent"],
    "brightBlack": EXPECTED["muted"],
}
for key, value in wt_expected.items():
    if wt.get(key) != value:
        fail(f"Windows Terminal {key} does not match its semantic role")

ghostty, ghostty_palette = parse_simple_config("dot_config/ghostty/config.tmpl")
ghostty_expected = {
    "background": EXPECTED["bg"].lower(),
    "foreground": EXPECTED["text"].lower(),
    "cursor-color": EXPECTED["accent"].lower(),
    "selection-background": EXPECTED["surface_active"].lower(),
}
for key, value in ghostty_expected.items():
    if ghostty.get(key) != value:
        fail(f"Ghostty {key} does not match its semantic role")
for index, role in ((1, "danger"), (2, "success"), (3, "warning"), (6, "accent"), (8, "muted")):
    if ghostty_palette.get(index) != EXPECTED[role].lower():
        fail(f"Ghostty ANSI palette index {index} does not match {role}")

print("visual foundation: PASS")
