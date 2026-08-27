#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$ROOT/scripts/lib/common.sh"
source "$ROOT/versions.env"

# Install dotfiles as the current user. On a real root login (for example a VPS)
# SUDO_USER is empty; `sudo bash install.sh` is rejected so HOME cannot silently
# become /root while the caller expected a per-user installation.
if [[ $EUID -eq 0 && -n ${SUDO_USER:-} && ${SUDO_USER:-root} != root ]]; then
  die "Do not run Terminal Environment with sudo. Run it as your user; the installer will request sudo only for system packages."
fi

PROFILE=auto
LOGIN_USER=${SUDO_USER:-${USER:-$(id -un)}}
DRY_RUN=0
NO_SHELL_CHANGE=0
NO_FONT=0
FORCE=0

usage(){ cat <<'USAGE'
Usage: ./install.sh [options]
  --profile auto|server|workstation|minimal
  --dry-run
  --no-shell-change
  --no-font
  --force
  -h, --help
USAGE
}
while (($#)); do
  case "$1" in
    --profile) PROFILE=${2:?missing profile}; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    --no-shell-change) NO_SHELL_CHANGE=1; shift;;
    --no-font) NO_FONT=1; shift;;
    --force) FORCE=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "Unknown option: $1";;
  esac
done
case "$PROFILE" in auto|server|workstation|minimal) ;; *) die "Invalid profile: $PROFILE";; esac
if [[ $PROFILE == auto ]]; then
  if [[ $(uname -s) == Darwin ]]; then PROFILE=workstation
  elif [[ -n ${SSH_CONNECTION:-}${SSH_TTY:-} || -z ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then PROFILE=server
  else PROFILE=workstation
  fi
fi

export PROFILE DRY_RUN NO_FONT
STATE="$HOME/.local/state/terminal-env"
SOURCE="$HOME/.local/share/terminal-env/source"
CONFIG="$HOME/.config/terminal-env/chezmoi.toml"
BACKUP="$STATE/backups/transactions/install-$(date -u +%Y%m%dT%H%M%SZ)-$$"
PREVIOUS_LAST_BACKUP=$(cat "$STATE/last-install-backup" 2>/dev/null || true)
LOCAL_BIN="$HOME/.local/bin"
INSTALL_ACTIVE=0
SAME_SOURCE=0

MANAGED_TARGETS=(
  "$HOME/.zshenv"
  "$HOME/.config/zsh"
  "$HOME/.config/oh-my-posh"
  "$HOME/.config/atuin"
  "$HOME/.config/ghostty"
  "$HOME/.config/tmux"
  "$HOME/.config/terminal-env"
  "$HOME/.local/share/terminal-env/zsh-plugins"
  "$SOURCE"
  "$HOME/.local/bin/oh-my-posh"
  "$HOME/.local/bin/atuin"
  "$HOME/.local/bin/fzf"
  "$HOME/.local/bin/zoxide"
  "$HOME/.local/bin/chezmoi"
  "$HOME/.local/bin/terminal-doctor"
  "$HOME/.local/bin/terminal-update"
  "$HOME/.local/bin/terminal-rollback"
  "$HOME/.local/bin/terminal-backup"
  "$HOME/.local/bin/terminal-deps"
)

HELPER_TARGETS=(
  "$HOME/.local/bin/terminal-doctor"
  "$HOME/.local/bin/terminal-update"
  "$HOME/.local/bin/terminal-rollback"
  "$HOME/.local/bin/terminal-backup"
  "$HOME/.local/bin/terminal-deps"
)

canonical_dir(){ (cd -- "$1" 2>/dev/null && pwd -P) || return 1; }
if [[ -d $SOURCE ]] && [[ $(canonical_dir "$ROOT" || true) == $(canonical_dir "$SOURCE" || true) ]]; then SAME_SOURCE=1; fi

rollback_install(){
  local rc=$?
  trap - ERR
  (( INSTALL_ACTIVE )) || exit "$rc"
  warn "Installation failed; restoring managed files from the transaction snapshot."
  set +e
  local target
  for target in "${MANAGED_TARGETS[@]}"; do
    [[ $SAME_SOURCE == 1 && $target == "$SOURCE" ]] && continue
    rm -rf -- "$target"
  done
  restore_backup_tree "$BACKUP"
  if [[ -n $PREVIOUS_LAST_BACKUP ]]; then printf '%s\n' "$PREVIOUS_LAST_BACKUP" > "$STATE/last-install-backup"; else rm -f "$STATE/last-install-backup"; fi
  cleanup_failed_transaction "$BACKUP"
  warn "Managed configuration was restored. System packages installed by the OS package manager were left in place."
  exit "$rc"
}
trap rollback_install ERR

say "Terminal Environment installer"
say "Profile: $PROFILE | Platform: $(uname -s) $(uname -m)"

if [[ $DRY_RUN == 0 ]]; then
  mkdir -p "$STATE" "$BACKUP" "$LOCAL_BIN" "$(dirname "$CONFIG")"
  chmod 700 "$STATE" "$BACKUP" 2>/dev/null || true
  for target in "${MANAGED_TARGETS[@]}"; do
    [[ $SAME_SOURCE == 1 && $target == "$SOURCE" ]] && continue
    backup_path "$target" "$BACKUP"
  done
  [[ -f "$STATE/original-backup" ]] || printf '%s\n' "$BACKUP" > "$STATE/original-backup"
  [[ -f "$STATE/original-shell" ]] || printf '%s\n' "${SHELL:-}" > "$STATE/original-shell"
  printf '%s\n' "$PROFILE" > "$STATE/profile"
  printf '%s\n' "$BACKUP" > "$STATE/last-install-backup"
  chmod 600 "$STATE/original-backup" "$STATE/original-shell" "$STATE/profile" "$STATE/last-install-backup"
  INSTALL_ACTIVE=1
fi

bash "$ROOT/scripts/install-tools-unix.sh"

if [[ $DRY_RUN == 0 ]]; then
  OS=$(os_name); ARCH=$(arch_name); TMP=$(mktemp -d)
  ASSET="chezmoi_${CHEZMOI_VERSION}_${OS}_${ARCH}.tar.gz"
  (
    trap 'rm -rf "$TMP"' EXIT
    download_release_asset twpayne/chezmoi "v$CHEZMOI_VERSION" "$ASSET" "$TMP/chezmoi.tar.gz"
    install_archive_binary "$TMP/chezmoi.tar.gz" chezmoi "$LOCAL_BIN/chezmoi"
  )

  if [[ $SAME_SOURCE == 0 ]]; then
    if [[ -e $SOURCE && $FORCE != 1 && ! -f $SOURCE/.terminal-env-source ]]; then
      die "$SOURCE exists and is not managed by Terminal Environment. Use --force only if you intend to replace it."
    fi
    NEW_SOURCE="$SOURCE.new.$$"
    rm -rf "$NEW_SOURCE"
    mkdir -p "$NEW_SOURCE"
    (cd "$ROOT" && tar --exclude='./.git' -cf - .) | (cd "$NEW_SOURCE" && tar -xf -)
    [[ -d "$ROOT/.git" ]] && cp -a "$ROOT/.git" "$NEW_SOURCE/.git"
    : > "$NEW_SOURCE/.terminal-env-source"
    rm -rf "$SOURCE"
    mv "$NEW_SOURCE" "$SOURCE"
  else
    : > "$SOURCE/.terminal-env-source"
  fi

  cat > "$CONFIG" <<EOF2
[data]
profile = "$PROFILE"
EOF2
  chmod 600 "$CONFIG"
  "$LOCAL_BIN/chezmoi" --source "$SOURCE" --config "$CONFIG" apply --force

  # Operational helpers are part of the installation contract. A source-state
  # naming mistake or ignore rule must fail the transaction rather than leave
  # a partially functional installation that reports success.
  for helper in "${HELPER_TARGETS[@]}"; do
    [[ -x "$helper" ]] || die "Managed helper was not installed executable: $helper"
  done

  # Clean up a malformed helper target emitted by early development builds
  # builds, but only when it contains nothing except our four helper files.
  legacy_helper_dir="$HOME/executable_dot_local"
  if [[ -d "$legacy_helper_dir/bin" ]]; then
    legacy_safe=1
    while IFS= read -r -d '' legacy_file; do
      case "${legacy_file##*/}" in terminal-doctor|terminal-update|terminal-rollback|terminal-backup|terminal-deps) ;; *) legacy_safe=0;; esac
    done < <(find "$legacy_helper_dir" -type f -print0 2>/dev/null)
    if (( legacy_safe )); then rm -rf -- "$legacy_helper_dir"; else warn "Legacy $legacy_helper_dir exists with unrelated files; leaving it untouched."; fi
  fi

  # Preserve the user's historical command memory when moving to the XDG history path.
  old_hist="$HOME/.zsh_history"; new_hist="$HOME/.local/state/zsh/history"
  if [[ -s "$old_hist" && ! -s "$new_hist" ]]; then
    mkdir -p "${new_hist%/*}"; cp -p "$old_hist" "$new_hist"; chmod 600 "$new_hist" 2>/dev/null || true
  fi

  if [[ $PROFILE != minimal ]]; then PROFILE="$PROFILE" bash "$SOURCE/scripts/build-zsh-plugins.sh"; fi

  # Early development builds managed Deja. When upgrading through a full installer run,
  # retire only the binary/daemon proven to have been activated by this project;
  # preserve its local DB so rollback remains lossless.
  if [[ -f "$STATE/deja-imported" ]]; then
    pkill -f 'deja daemon' >/dev/null 2>&1 || true
    rm -f -- "$HOME/.local/bin/deja"
    : > "$STATE/deja-retired"
  fi

  if command -v atuin >/dev/null 2>&1 && [[ ! -f "$STATE/atuin-imported" ]]; then
    import_hist=""; [[ -s "$new_hist" ]] && import_hist="$new_hist"; [[ -z "$import_hist" && -s "$old_hist" ]] && import_hist="$old_hist"
    if [[ -n "$import_hist" ]] && HISTFILE="$import_hist" atuin import zsh >/dev/null 2>&1; then : > "$STATE/atuin-imported"; fi
  fi

fi

if [[ $DRY_RUN == 0 && $NO_SHELL_CHANGE == 0 && $PROFILE != minimal ]]; then
  ZSH_BIN=$(command -v zsh || true)
  if [[ -n $ZSH_BIN && ${SHELL:-} != "$ZSH_BIN" ]]; then
    if (( EUID == 0 )); then
      chsh -s "$ZSH_BIN" "$LOGIN_USER" 2>/dev/null && ok "Login shell changed to $ZSH_BIN" || warn "Could not change login shell; run: chsh -s $ZSH_BIN $LOGIN_USER"
    elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      sudo chsh -s "$ZSH_BIN" "$LOGIN_USER" && ok "Login shell changed to $ZSH_BIN" || warn "Could not change login shell; run: chsh -s $ZSH_BIN"
    else
      warn "Login shell was not changed non-interactively. Run: chsh -s $ZSH_BIN"
    fi
  fi
fi

if [[ $DRY_RUN == 0 ]]; then
  : > "$BACKUP/.complete"
  prune_transaction_backups 3
  INSTALL_ACTIVE=0
  trap - ERR
  [[ -x "$HOME/.local/bin/terminal-doctor" ]] && "$HOME/.local/bin/terminal-doctor" --quick || true
  ok "Installation complete. Transaction backup: $BACKUP"
  [[ $PROFILE != minimal ]] && printf 'Open a new terminal or run: exec zsh\n'
else
  ok "Dry run complete; no files were changed."
fi
