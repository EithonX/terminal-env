#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$ROOT/scripts/lib/common.sh"
source "$ROOT/versions.env"

PROFILE=auto
LOGIN_USER=${SUDO_USER:-${USER:-$(id -un)}}
DRY_RUN=0
NO_SHELL_CHANGE=0
NO_FONT=0
FORCE=0
FORMAT=human
COLOR=auto
QUIET=0
VERBOSE=0

usage(){ cat <<'USAGE'
Usage: ./install.sh [options]
  --profile auto|server|workstation|minimal
  --dry-run
  --no-shell-change
  --no-font
  --force
  --format human|plain|json
  --color auto|always|never
  --quiet
  --verbose
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
    --format) (($# >= 2)) || { printf '%s\n' 'Missing value for --format.' >&2; exit 2; }; FORMAT=$2; shift 2;;
    --format=*) FORMAT=${1#*=}; shift;;
    --color) (($# >= 2)) || { printf '%s\n' 'Missing value for --color.' >&2; exit 2; }; COLOR=$2; shift 2;;
    --color=*) COLOR=${1#*=}; shift;;
    --quiet) QUIET=1; shift;;
    --verbose) VERBOSE=1; shift;;
    -h|--help) usage; exit 0;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2;;
  esac
done
case "$PROFILE" in auto|server|workstation|minimal) ;; *) printf 'Invalid profile: %s\n' "$PROFILE" >&2; exit 2;; esac
case "$FORMAT" in human|plain|json) ;; *) printf 'Invalid format: %s\n' "$FORMAT" >&2; exit 2;; esac
case "$COLOR" in auto|always|never) ;; *) printf 'Invalid color mode: %s\n' "$COLOR" >&2; exit 2;; esac
(( QUIET == 0 || VERBOSE == 0 )) || { printf '%s\n' '--quiet and --verbose cannot be used together.' >&2; exit 2; }
if [[ $PROFILE == auto ]]; then
  if [[ $(uname -s) == Darwin ]]; then PROFILE=workstation
  elif [[ -n ${SSH_CONNECTION:-}${SSH_TTY:-} || -z ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then PROFILE=server
  else PROFILE=workstation
  fi
fi

export TERMINAL_ENV_COLOR="$COLOR"
terminal_common_color_init "$COLOR"
ui_lib="$ROOT/dot_local/lib/terminal-env/output.sh"
[[ -r $ui_lib ]] || die "Terminal Environment output library is missing: $ui_lib"
# shellcheck disable=SC1090
source "$ui_lib"
te_ui_init "$FORMAT" "$COLOR" || die 'Could not initialize output mode.'

# Install dotfiles as the current user. On a real root login (for example a VPS)
# SUDO_USER is empty; `sudo bash install.sh` is rejected so HOME cannot silently
# become /root while the caller expected a per-user installation.
if [[ $EUID -eq 0 && -n ${SUDO_USER:-} && ${SUDO_USER:-root} != root ]]; then
  die "Do not run Terminal Environment with sudo. Run it as your user; the installer will request sudo only for system packages."
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
  "$HOME/.local/bin/terminal"
  "$HOME/.local/bin/terminal-doctor"
  "$HOME/.local/bin/terminal-update"
  "$HOME/.local/bin/terminal-rollback"
  "$HOME/.local/bin/terminal-backup"
  "$HOME/.local/bin/terminal-deps"
  "$HOME/.local/bin/terminal-context"
)

HELPER_TARGETS=(
  "$HOME/.local/bin/terminal"
  "$HOME/.local/bin/terminal-doctor"
  "$HOME/.local/bin/terminal-update"
  "$HOME/.local/bin/terminal-rollback"
  "$HOME/.local/bin/terminal-backup"
  "$HOME/.local/bin/terminal-deps"
  "$HOME/.local/bin/terminal-context"
)

canonical_dir(){ (cd -- "$1" 2>/dev/null && pwd -P) || return 1; }
if [[ -d $SOURCE ]] && [[ $(canonical_dir "$ROOT" || true) == $(canonical_dir "$SOURCE" || true) ]]; then SAME_SOURCE=1; fi

PLATFORM="$(uname -s)"
ARCH="$(uname -m)"
preflight_install(){
  case "$PLATFORM" in
    Linux|Darwin) ;;
    *) die "Unsupported platform: $PLATFORM" ;;
  esac
  case "$ARCH" in
    x86_64|amd64|arm64|aarch64) ;;
    *) die "Unsupported architecture: $ARCH" ;;
  esac
  [[ -d $HOME && -w $HOME ]] || die "Home directory is not writable: $HOME"
  if [[ $SAME_SOURCE == 0 && -e $SOURCE && $FORCE != 1 && ! -f $SOURCE/.terminal-env-source ]]; then
    die "$SOURCE exists and is not managed by Terminal Environment. Use --force only if you intend to replace it."
  fi
  if [[ $PLATFORM == Linux ]]; then
    have apt-get || die 'Linux provisioning currently supports Ubuntu/Debian systems with apt-get.'
    if (( EUID != 0 )); then have sudo || die 'sudo is required to install system packages on Ubuntu/Debian.'; fi
  elif (( ! DRY_RUN )); then
    have brew || die 'Homebrew is required for macOS provisioning. Install Homebrew once, then rerun the installer.'
  fi
}
run_install_child(){
  local progress_quiet=1
  (( VERBOSE )) && progress_quiet=0
  if (( QUIET )); then
    TERMINAL_ENV_QUIET_PROGRESS=$progress_quiet TERMINAL_ENV_COLOR="$COLOR" "$@" >/dev/null
  else
    TERMINAL_ENV_QUIET_PROGRESS=$progress_quiet TERMINAL_ENV_COLOR="$COLOR" "$@" 1>&2
  fi
}
install_stage(){
  (( QUIET )) && return 0
  [[ $FORMAT == human ]] || return 0
  te_ui_section "$1"
}
render_install_result(){
  local status=$1 backup_json next_action backup_value='' dry_json=false
  (( QUIET )) && return 0
  if [[ $PROFILE == minimal ]]; then
    next_action='Open a new shell session.'
  elif [[ $PLATFORM == Darwin || $PLATFORM == Linux ]]; then
    next_action='Open a new terminal or run: exec zsh'
  else
    next_action='Open a new terminal session.'
  fi
  if [[ $status == installed ]]; then
    backup_value=$(te_ui_clean_text "$BACKUP")
    backup_json=$(te_ui_json_string "$backup_value")
  else
    backup_json=null
  fi
  (( DRY_RUN )) && dry_json=true
  case "$FORMAT" in
    human)
      if [[ $status == dry-run ]]; then
        te_ui_outcome accent 'Dry run complete · no files were changed'
      else
        te_ui_outcome success "Installed · $PROFILE"
        te_ui_meta "Transaction backup: $BACKUP"
        te_ui_meta "$next_action"
      fi
      ;;
    plain)
      printf 'install\t%s\t%s\t%s\t%s\t%s\n' \
        "$status" "$(te_ui_clean_text "$PROFILE")" "$(te_ui_clean_text "$PLATFORM")" \
        "$(te_ui_clean_text "$ARCH")" "$backup_value"
      ;;
    json)
      printf '{"command":"install","status":%s,"profile":%s,"platform":%s,"arch":%s,"dry_run":%s,"transaction_backup":%s,"next_action":%s}\n' \
        "$(te_ui_json_string "$status")" "$(te_ui_json_string "$(te_ui_clean_text "$PROFILE")")" \
        "$(te_ui_json_string "$(te_ui_clean_text "$PLATFORM")")" "$(te_ui_json_string "$(te_ui_clean_text "$ARCH")")" \
        "$dry_json" "$backup_json" "$(te_ui_json_string "$next_action")"
      ;;
  esac
  return 0
}

if (( ! QUIET )) && [[ $FORMAT == human ]]; then
  te_ui_title install
  te_ui_meta "$PROFILE · $PLATFORM $ARCH"
  install_stage Preflight
fi
preflight_install
if (( ! QUIET )) && [[ $FORMAT == human ]]; then
  te_ui_row Platform "$PLATFORM $ARCH"
  te_ui_row Profile "$PROFILE"
  te_ui_row 'Home directory' writable
  install_stage Plan
  if (( DRY_RUN )); then te_ui_row Mode 'dry run'; else te_ui_row Mode 'transactional apply'; fi
  if (( NO_SHELL_CHANGE )) || [[ $PROFILE == minimal ]]; then te_ui_row 'Login shell' unchanged; else te_ui_row 'Login shell' 'set to Zsh when permitted'; fi
  if (( NO_FONT )) || [[ $PROFILE != workstation ]]; then te_ui_row Fonts skipped; else te_ui_row Fonts 'Monaspice Neon NF · 4 faces'; fi
fi

rollback_install(){
  local rc=$?
  trap - ERR
  (( INSTALL_ACTIVE )) || exit "$rc"
  printf '%s\n' 'Could not install Terminal Environment.' >&2
  printf '%s\n' 'Managed files are being restored from the transaction snapshot.' >&2
  set +e
  local target
  for target in "${MANAGED_TARGETS[@]}"; do
    [[ $SAME_SOURCE == 1 && $target == "$SOURCE" ]] && continue
    rm -rf -- "$target"
  done
  restore_backup_tree "$BACKUP"
  if [[ -n $PREVIOUS_LAST_BACKUP ]]; then printf '%s\n' "$PREVIOUS_LAST_BACKUP" > "$STATE/last-install-backup"; else rm -f "$STATE/last-install-backup"; fi
  cleanup_failed_transaction "$BACKUP"
  printf '%s\n' 'Managed configuration was restored. System packages installed by the OS package manager were left in place.' >&2
  exit "$rc"
}
trap rollback_install ERR

if [[ $DRY_RUN == 0 ]]; then
  install_stage Apply
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

run_install_child bash "$ROOT/scripts/install-tools-unix.sh"

if [[ $DRY_RUN == 0 ]]; then
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
  run_install_child "$LOCAL_BIN/chezmoi" --source "$SOURCE" --config "$CONFIG" apply --force

  # Operational helpers are part of the installation contract. A source-state
  # naming mistake or ignore rule must fail the transaction rather than leave
  # a partially functional installation that reports success.
  for helper in "${HELPER_TARGETS[@]}"; do
    [[ -x "$helper" ]] || die "Managed helper was not installed executable: $helper"
  done

  # Clean up a malformed helper target emitted by early development builds
  # builds, but only when it contains nothing except managed helper files.
  legacy_helper_dir="$HOME/executable_dot_local"
  if [[ -d "$legacy_helper_dir/bin" ]]; then
    legacy_safe=1
    while IFS= read -r -d '' legacy_file; do
      case "${legacy_file##*/}" in terminal-doctor|terminal-update|terminal-rollback|terminal-backup|terminal-deps|terminal-context) ;; *) legacy_safe=0;; esac
    done < <(find "$legacy_helper_dir" -type f -print0 2>/dev/null)
    if (( legacy_safe )); then rm -rf -- "$legacy_helper_dir"; else warn "Legacy $legacy_helper_dir exists with unrelated files; leaving it untouched."; fi
  fi

  # Preserve the user's historical command memory when moving to the XDG history path.
  old_hist="$HOME/.zsh_history"; new_hist="$HOME/.local/state/zsh/history"
  if [[ -s "$old_hist" && ! -s "$new_hist" ]]; then
    mkdir -p "${new_hist%/*}"; cp -p "$old_hist" "$new_hist"; chmod 600 "$new_hist" 2>/dev/null || true
  fi

  if [[ $PROFILE != minimal ]]; then run_install_child env PROFILE="$PROFILE" bash "$SOURCE/scripts/build-zsh-plugins.sh"; fi

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
      if chsh -s "$ZSH_BIN" "$LOGIN_USER" 2>/dev/null; then
        :
      else
        warn "Could not change login shell; run: chsh -s $ZSH_BIN $LOGIN_USER"
      fi
    elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      if sudo chsh -s "$ZSH_BIN" "$LOGIN_USER"; then
        :
      else
        warn "Could not change login shell; run: chsh -s $ZSH_BIN"
      fi
    else
      warn "Login shell was not changed non-interactively. Run: chsh -s $ZSH_BIN"
    fi
  fi
fi

if [[ $DRY_RUN == 0 ]]; then
  install_stage Verify
  [[ -x "$HOME/.local/bin/terminal" ]] || die 'Managed terminal command was not installed.'
  [[ -x "$HOME/.local/bin/terminal-doctor" ]] || die 'Managed terminal-doctor was not installed.'
  PATH="$LOCAL_BIN:$PATH" "$HOME/.local/bin/terminal-doctor" --quick --quiet
  if [[ $PROFILE != minimal ]]; then
    [[ -x "$HOME/.local/bin/terminal-deps" ]] || die 'Managed terminal-deps was not installed.'
    PATH="$LOCAL_BIN:$PATH" "$HOME/.local/bin/terminal-deps" status --quiet
  fi
  : > "$BACKUP/.complete"
  prune_transaction_backups 3
  INSTALL_ACTIVE=0
  trap - ERR
  install_stage Finish
  render_install_result installed
else
  install_stage Finish
  render_install_result dry-run
fi
