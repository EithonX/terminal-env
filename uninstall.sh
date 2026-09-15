#!/usr/bin/env bash
set -Eeuo pipefail

STATE=${TERMINAL_ENV_STATE:-$HOME/.local/state/terminal-env}
LOGIN_USER=${USER:-$(id -un)}
restore=1
yes=0
dry=0
no_input=0
format=human
color=auto
quiet=0

usage(){ cat <<'USAGE'
Usage: ./uninstall.sh [options]

Options:
  --no-restore             Remove managed files without restoring the pre-install snapshot.
  --yes                    Skip interactive confirmation.
  --dry-run                Show the uninstall plan without changing anything.
  --no-input               Never prompt; requires --yes when applying changes.
  --format human|plain|json
  --color auto|always|never
  --quiet                  Print no result output; requires --yes when applying changes.
  -h, --help               Show this help.
USAGE
}

while (($#)); do
  case "$1" in
    --no-restore) restore=0; shift ;;
    --yes) yes=1; shift ;;
    --dry-run) dry=1; shift ;;
    --no-input) no_input=1; shift ;;
    --quiet) quiet=1; shift ;;
    --format) (($# >= 2)) || { printf '%s\n' 'Missing value for --format.' >&2; exit 2; }; format=$2; shift 2 ;;
    --format=*) format=${1#*=}; shift ;;
    --color) (($# >= 2)) || { printf '%s\n' 'Missing value for --color.' >&2; exit 2; }; color=$2; shift 2 ;;
    --color=*) color=${1#*=}; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$format" in human|plain|json) ;; *) printf 'Invalid format: %s\n' "$format" >&2; exit 2 ;; esac
case "$color" in auto|always|never) ;; *) printf 'Invalid color mode: %s\n' "$color" >&2; exit 2 ;; esac

script_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ui_lib=''
for candidate in "$script_root/dot_local/lib/terminal-env/output.sh" "$HOME/.local/lib/terminal-env/output.sh"; do
  if [[ -r $candidate ]]; then ui_lib=$candidate; break; fi
done
ui_available=0
if [[ -n $ui_lib ]]; then
  # shellcheck disable=SC1090
  source "$ui_lib"
  if te_ui_init "$format" "$color"; then ui_available=1; fi
fi
clean_text(){
  if (( ui_available )); then te_ui_clean_text "${1-}"; else printf '%s' "${1-}" | LC_ALL=C tr '\000-\037\177' ' '; fi
}
json_string(){
  if (( ui_available )); then te_ui_json_string "${1-}"; return; fi
  local s
  s=$(clean_text "${1-}")
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  printf '"%s"' "$s"
}

BACKUP=$(cat "$STATE/original-backup" 2>/dev/null || true)
orig_shell=$(cat "$STATE/original-shell" 2>/dev/null || true)
restore_available=0
if (( restore )); then
  [[ -n $BACKUP ]] || { printf '%s\n' 'No pre-install restore point is recorded. Re-run with --no-restore only if removing managed files without restoration is intentional.' >&2; exit 2; }
  [[ -d $BACKUP ]] || { printf '%s\n' 'The recorded pre-install restore point is missing. Re-run with --no-restore only if removing managed files without restoration is intentional.' >&2; exit 2; }
  (cd "$BACKUP" && tar -cf /dev/null .) 2>/dev/null || { printf '%s\n' 'The pre-install restore point could not be read safely; no files were changed.' >&2; exit 2; }
  restore_available=1
fi

render_plan(){
  (( quiet )) && return 0
  [[ $format == human ]] || return 0
  if (( ui_available )); then
    te_ui_title uninstall
    te_ui_section Plan
    te_ui_row 'Managed files' 'remove'
    if (( restore_available )); then te_ui_row 'Original files' "restore · $(clean_text "$BACKUP")"
    elif (( restore )); then te_ui_row 'Original files' 'no restore point recorded' warning
    else te_ui_row 'Original files' 'leave removed' warning
    fi
    [[ -n $orig_shell ]] && te_ui_row 'Login shell' "restore · $(clean_text "$orig_shell")"
    te_ui_row 'Packages/history' 'preserve'
    te_ui_meta 'System packages and history databases are not removed.'
  else
    printf 'Terminal Environment · uninstall\n\nPlan\n'
    printf '  Managed files      remove\n'
    if (( restore_available )); then printf '  Original files     restore · %s\n' "$(clean_text "$BACKUP")"
    elif (( restore )); then printf '  Original files     no restore point recorded\n'
    else printf '  Original files     leave removed\n'
    fi
    [[ -n $orig_shell ]] && printf '  Login shell        restore · %s\n' "$(clean_text "$orig_shell")"
    printf '  Packages/history   preserve\n\nSystem packages and history databases are not removed.\n'
  fi
}

render_result(){
  local status=$1 restored=$2 restored_json=false restore_requested_json=false restore_available_json=false
  (( quiet )) && return
  (( restored )) && restored_json=true
  (( restore )) && restore_requested_json=true
  (( restore_available )) && restore_available_json=true
  case "$format" in
    human)
      if (( ui_available )); then
        case "$status" in
          planned) te_ui_outcome accent 'Dry run complete · no changes applied' ;;
          cancelled) te_ui_outcome text 'Cancelled · no changes applied' ;;
          uninstalled)
            if (( restored )); then te_ui_outcome success 'Uninstalled · original files restored'
            else te_ui_outcome success 'Uninstalled · managed files removed'
            fi
            te_ui_meta 'System packages and history databases were preserved.' ;;
        esac
      else
        case "$status" in
          planned) printf '\nDry run complete · no changes applied\n' ;;
          cancelled) printf '\nCancelled · no changes applied\n' ;;
          uninstalled) if (( restored )); then printf '\nUninstalled · original files restored\n'; else printf '\nUninstalled · managed files removed\n'; fi; printf 'System packages and history databases were preserved.\n' ;;
        esac
      fi
      ;;
    plain)
      printf 'uninstall\t%s\t%d\t%d\t%s\n' "$status" "$restore" "$restored" "$(clean_text "$BACKUP")"
      ;;
    json)
      printf '{"command":"uninstall","status":%s,"restore_requested":%s,"restore_available":%s,"restored":%s,"backup":%s,"packages_preserved":true,"history_preserved":true}\n' \
        "$(json_string "$status")" "$restore_requested_json" "$restore_available_json" "$restored_json" "$(json_string "$BACKUP")"
      ;;
  esac
}

render_plan
if (( dry )); then render_result planned 0; exit 0; fi
if (( ! yes )); then
  if (( no_input || quiet )) || [[ $format != human ]] || [[ ! -t 0 ]]; then
    printf '%s\n' 'Uninstall requires --yes when confirmation cannot be requested interactively.' >&2
    exit 2
  fi
  printf 'Continue? [y/N] ' >&2
  IFS= read -r answer || answer=''
  case "$answer" in y|Y|yes|YES|Yes) ;; *) render_result cancelled 0; exit 0 ;; esac
fi

managed=(
  .zshenv .config/zsh .config/oh-my-posh .config/atuin .config/ghostty .config/tmux .config/terminal-env
  .local/bin/terminal .local/bin/terminal-doctor .local/bin/terminal-update .local/bin/terminal-rollback .local/bin/terminal-backup .local/bin/terminal-deps .local/bin/terminal-context .local/lib/terminal-env
  .local/bin/oh-my-posh .local/bin/atuin .local/bin/fzf .local/bin/zoxide .local/bin/chezmoi
  .local/share/terminal-env/source .local/share/terminal-env/zsh-plugins .cache/terminal-env
)
rollback_dir=$(mktemp -d "${TMPDIR:-/tmp}/terminal-env-uninstall.XXXXXX")
uninstall_active=0
cleanup_uninstall_snapshot(){ rm -rf -- "$rollback_dir" 2>/dev/null || true; }
rollback_uninstall(){
  local rc=$?
  trap - ERR
  if (( uninstall_active )); then
    printf '%s\n' 'Could not complete uninstall; restoring the managed state that was active before the command.' >&2
    set +e
    local rel saved
    for rel in "${managed[@]}"; do
      rm -rf -- "${HOME:?}/$rel"
      saved="$rollback_dir/home/$rel"
      if [[ -e $saved || -L $saved ]]; then
        mkdir -p -- "$(dirname -- "$HOME/$rel")"
        cp -a -- "$saved" "$HOME/$rel"
      fi
    done
    printf '%s\n' 'Managed files were restored. The pre-install restore point was left unchanged.' >&2
  fi
  exit "$rc"
}
trap cleanup_uninstall_snapshot EXIT
for rel in "${managed[@]}"; do
  current="$HOME/$rel"
  if [[ -e $current || -L $current ]]; then
    mkdir -p -- "$rollback_dir/home/$(dirname -- "$rel")"
    cp -a -- "$current" "$rollback_dir/home/$rel"
  fi
done
uninstall_active=1
trap rollback_uninstall ERR

for rel in "${managed[@]}"; do rm -rf -- "${HOME:?}/$rel"; done
if [[ -f "$STATE/deja-imported" ]]; then pkill -f 'deja daemon' >/dev/null 2>&1 || true; rm -f -- "$HOME/.local/bin/deja" || true; fi

restored=0
if (( restore_available )); then
  (cd "$BACKUP" && tar -cf - .) | (cd "$HOME" && tar -xf -)
  restored=1
fi
uninstall_active=0
trap - ERR

# Remove only versioned font files whose naming proves Terminal Environment owns them.
font_manifest="$STATE/fonts/current"
if [[ -r $font_manifest ]]; then
  while IFS= read -r fp; do
    case ${fp##*/} in *.terminal-env-*.otf|*.terminal-env-*.ttf) rm -f -- "$fp" || true ;; esac
  done < "$font_manifest"
  if command -v fc-cache >/dev/null 2>&1; then fc-cache -f >/dev/null 2>&1 || true; fi
fi

if (( restored )); then
  rm -rf -- "$STATE/backups/transactions" 2>/dev/null || printf '%s\n' 'Could not prune installer transaction backups; they were left in place.' >&2
  for old_backup in "$STATE/backups"/install-* "$STATE/backups"/20??????T??????Z*; do
    [[ -d $old_backup ]] || continue
    rm -rf -- "$old_backup" 2>/dev/null || printf 'Could not remove old transaction backup: %s\n' "$(clean_text "$old_backup")" >&2
  done
  rm -f -- "$STATE/original-backup" "$STATE/last-install-backup" 2>/dev/null || printf '%s\n' 'Could not clear restore-point state; review the state directory manually.' >&2
fi
if [[ -n $orig_shell && -x $orig_shell && ${SHELL:-} != "$orig_shell" ]]; then
  if [[ $EUID -eq 0 ]]; then chsh -s "$orig_shell" "$LOGIN_USER" 2>/dev/null || true
  elif (( ! quiet )); then printf 'To restore the old login shell: chsh -s %s\n' "$(clean_text "$orig_shell")" >&2
  fi
fi

render_result uninstalled "$restored"
