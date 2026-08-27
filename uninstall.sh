#!/usr/bin/env bash
set -Eeuo pipefail
STATE="$HOME/.local/state/terminal-env"
LOGIN_USER=${USER:-$(id -un)}
BACKUP=$(cat "$STATE/original-backup" 2>/dev/null || true)
restore=1; [[ ${1:-} == --no-restore ]] && restore=0
orig_shell=$(cat "$STATE/original-shell" 2>/dev/null || true)
managed=(
  .zshenv .config/zsh .config/oh-my-posh .config/atuin .config/ghostty .config/tmux .config/terminal-env
  .local/bin/terminal-doctor .local/bin/terminal-update .local/bin/terminal-rollback .local/bin/terminal-backup .local/bin/terminal-deps
  .local/bin/oh-my-posh .local/bin/atuin .local/bin/fzf .local/bin/zoxide .local/bin/chezmoi
  .local/share/terminal-env/zsh-plugins .cache/terminal-env
)
for rel in "${managed[@]}"; do rm -rf -- "$HOME/$rel"; done
if [[ -f "$STATE/deja-imported" ]]; then pkill -f 'deja daemon' >/dev/null 2>&1 || true; rm -f -- "$HOME/.local/bin/deja"; fi
# Remove only versioned font files whose naming proves Terminal Environment owns them.
font_manifest="$STATE/fonts/current"
if [[ -r $font_manifest ]]; then
  while IFS= read -r fp; do
    case ${fp##*/} in *.terminal-env-*.otf|*.terminal-env-*.ttf) rm -f -- "$fp" ;; esac
  done < "$font_manifest"
  if command -v fc-cache >/dev/null 2>&1; then fc-cache -f >/dev/null 2>&1 || true; fi
fi
# Source is removed only after its uninstall script has finished reading.
source_tree="$HOME/.local/share/terminal-env/source"
if (( restore )) && [[ -n $BACKUP && -d $BACKUP ]]; then
  (cd "$BACKUP" && tar -cf - .) | (cd "$HOME" && tar -xf -)
  echo "Restored original pre-install files from $BACKUP"
  rm -rf -- "$STATE/backups/transactions"
  for old_backup in "$STATE/backups"/install-* "$STATE/backups"/20??????T??????Z*; do [[ -d $old_backup ]] && rm -rf -- "$old_backup"; done
  rm -f -- "$STATE/original-backup" "$STATE/last-install-backup"
else
  echo 'Managed configuration removed; persistent history and backups were left in place.'
fi
if [[ -n $orig_shell && -x $orig_shell && ${SHELL:-} != "$orig_shell" ]]; then
  if [[ $EUID -eq 0 ]]; then chsh -s "$orig_shell" "$LOGIN_USER" 2>/dev/null || true; else echo "To restore the old login shell: chsh -s $orig_shell"; fi
fi
rm -rf -- "$source_tree"
echo 'System packages and history databases were intentionally left installed/preserved.'
