#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/scripts/lib/common.sh"
source "$ROOT/versions.env"
DRY_RUN=${DRY_RUN:-0}
SYNC_PLUGINS=${SYNC_PLUGINS:-1}
PLUGIN_ROOT="$HOME/.local/share/terminal-env/zsh-plugins"
GEN_DIR="$HOME/.cache/terminal-env/zsh"

install_plugin() {
  local repo=$1 ref=$2 name=$3 expected=${4:-}
  local dest tmp actual
  dest="$PLUGIN_ROOT/$name"
  if [[ $DRY_RUN == 1 ]]; then say "Would install $repo@$ref"; return 0; fi
  if [[ -d "$dest/.git" ]]; then
    actual=$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)
    if [[ -n $expected && $actual == "$expected"* ]]; then return 0; fi
    if [[ -z $expected ]] && git -C "$dest" describe --tags --exact-match 2>/dev/null | grep -Fxq "$ref"; then return 0; fi
  fi
  tmp=$(mktemp -d "$PLUGIN_ROOT/.${name}.XXXXXX")
  if ! retry git clone --quiet --depth=1 --branch "$ref" "https://github.com/$repo.git" "$tmp/repo"; then rm -rf "$tmp"; die "Could not install $repo@$ref"; fi
  actual=$(git -C "$tmp/repo" rev-parse HEAD)
  if [[ -n $expected && $actual != "$expected"* ]]; then rm -rf "$tmp"; die "$repo@$ref resolved to unexpected commit $actual"; fi
  rm -rf "$dest.old"
  [[ -e $dest ]] && mv "$dest" "$dest.old"
  mv "$tmp/repo" "$dest"
  rm -rf "$tmp" "$dest.old"
}

ensure_dir "$PLUGIN_ROOT"
ensure_dir "$GEN_DIR"
if [[ $SYNC_PLUGINS == 1 ]]; then
  install_plugin zsh-users/zsh-autosuggestions "$ZSH_AUTOSUGGESTIONS_REF" zsh-autosuggestions "$ZSH_AUTOSUGGESTIONS_SHA"
  install_plugin zsh-users/zsh-completions "$ZSH_COMPLETIONS_REF" zsh-completions "$ZSH_COMPLETIONS_SHA"
  install_plugin Aloxaf/fzf-tab "$FZF_TAB_REF" fzf-tab "$FZF_TAB_SHA"
  install_plugin zsh-users/zsh-syntax-highlighting "$ZSH_SYNTAX_HIGHLIGHTING_REF" zsh-syntax-highlighting
fi

if [[ $DRY_RUN == 0 ]]; then
  cat > "$GEN_DIR/fpath.zsh.tmp" <<EOF2
fpath=("$PLUGIN_ROOT/zsh-completions/src" \$fpath)
EOF2
  cat > "$GEN_DIR/interactive.zsh.tmp" <<EOF2
[[ -r "$PLUGIN_ROOT/fzf-tab/fzf-tab.plugin.zsh" ]] && source "$PLUGIN_ROOT/fzf-tab/fzf-tab.plugin.zsh"
EOF2
  cat > "$GEN_DIR/final.zsh.tmp" <<EOF2
[[ -r "$PLUGIN_ROOT/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$PLUGIN_ROOT/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
EOF2
  for f in fpath interactive final; do mv "$GEN_DIR/$f.zsh.tmp" "$GEN_DIR/$f.zsh"; done
  if command -v fzf >/dev/null 2>&1 && fzf --zsh > "$GEN_DIR/fzf.zsh.tmp"; then
    mv "$GEN_DIR/fzf.zsh.tmp" "$GEN_DIR/fzf.zsh"
  else
    rm -f -- "$GEN_DIR/fzf.zsh.tmp"
  fi
  if command -v zoxide >/dev/null 2>&1 && zoxide init zsh --cmd z > "$GEN_DIR/zoxide.zsh.tmp"; then
    mv "$GEN_DIR/zoxide.zsh.tmp" "$GEN_DIR/zoxide.zsh"
  else
    rm -f -- "$GEN_DIR/zoxide.zsh.tmp"
  fi
  if command -v atuin >/dev/null 2>&1 && atuin init zsh --disable-up-arrow --disable-ai > "$GEN_DIR/atuin.zsh.tmp"; then
    mv "$GEN_DIR/atuin.zsh.tmp" "$GEN_DIR/atuin.zsh"
  else
    rm -f -- "$GEN_DIR/atuin.zsh.tmp"
  fi
  if command -v vivid >/dev/null 2>&1; then
    if vivid generate terminal-env > "$HOME/.cache/terminal-env/ls-colors.tmp" 2>/dev/null; then
      mv "$HOME/.cache/terminal-env/ls-colors.tmp" "$HOME/.cache/terminal-env/ls-colors"
    else
      rm -f -- "$HOME/.cache/terminal-env/ls-colors.tmp"
    fi
  fi
fi
ok "Zsh integrations prepared."
