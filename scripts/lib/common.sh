#!/usr/bin/env bash
set -Eeuo pipefail

c_reset=''; c_dim=''; c_ok=''; c_warn=''; c_err=''; c_info=''
terminal_common_color_init(){
  local mode=${1:-auto} enabled=0
  case "$mode" in
    always) enabled=1 ;;
    never) enabled=0 ;;
    auto) [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-} != dumb ]] && enabled=1 ;;
    *) return 2 ;;
  esac
  if (( enabled )); then
    c_reset='\033[0m'; c_dim='\033[2m'
    c_ok='\033[38;2;139;181;148m'; c_warn='\033[38;2;214;168;95m'
    c_err='\033[38;2;224;120;128m'; c_info='\033[38;2;124;196;228m'
  else
    c_reset='' c_dim='' c_ok='' c_warn='' c_err='' c_info=''
  fi
}
terminal_common_color_init "${TERMINAL_ENV_COLOR:-auto}"
progress_quiet(){ [[ ${TERMINAL_ENV_QUIET_PROGRESS:-0} == 1 ]]; }
say(){ progress_quiet && return 0; printf '%b%s%b\n' "$c_info" "$*" "$c_reset"; }
ok(){ progress_quiet && return 0; printf '%b%s%b\n' "$c_ok" "$*" "$c_reset"; }
warn(){ printf '%b%s%b\n' "$c_warn" "$*" "$c_reset" >&2; }
die(){ printf '%b%s%b\n' "$c_err" "$*" "$c_reset" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
run(){ if [[ ${DRY_RUN:-0} == 1 ]]; then if ! progress_quiet; then printf '%b+' "$c_dim"; printf ' %q' "$@"; printf '%b\n' "$c_reset"; fi; else "$@"; fi; }
retry(){ local n=0 max=${RETRY_MAX:-3}; until "$@"; do n=$((n+1)); (( n >= max )) && return 1; sleep $((n*2)); done; }
ensure_dir(){ [[ ${DRY_RUN:-0} == 1 ]] || mkdir -p "$1"; }
sha256_file(){ if have sha256sum; then sha256sum "$1" | awk '{print $1}'; elif have shasum; then shasum -a 256 "$1" | awk '{print $1}'; else return 1; fi; }
os_name(){ case "$(uname -s)" in Linux) echo linux;; Darwin) echo darwin;; *) echo unsupported;; esac; }
arch_name(){ case "$(uname -m)" in x86_64|amd64) echo amd64;; arm64|aarch64) echo arm64;; *) echo unsupported;; esac; }

backup_path(){
  local src=$1 backup_root=$2 rel
  [[ -e "$src" || -L "$src" ]] || return 0
  rel=${src#"$HOME"/}
  mkdir -p "$backup_root/$(dirname -- "$rel")"
  cp -a "$src" "$backup_root/$rel"
}

restore_backup_tree(){
  local backup_root=$1
  [[ -d $backup_root ]] || return 0
  (cd "$backup_root" && tar -cf - .) | (cd "$HOME" && tar -xf -)
}

api_asset(){
  local repo=$1 tag=$2 asset=$3 json url digest token=${GITHUB_TOKEN:-${GH_TOKEN:-}}
  local auth=(); [[ -n $token ]] && auth=(-H "Authorization: Bearer $token")
  json=$(retry curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -H 'Accept: application/vnd.github+json' -H 'User-Agent: terminal-env-installer' "${auth[@]}" "https://api.github.com/repos/$repo/releases/tags/$tag") || return 1
  url=$(jq -r --arg a "$asset" '.assets[] | select(.name==$a) | .browser_download_url' <<<"$json" | head -n1)
  digest=$(jq -r --arg a "$asset" '.assets[] | select(.name==$a) | (.digest // "")' <<<"$json" | head -n1)
  [[ -n "$url" && "$url" != null ]] || return 1
  printf '%s\t%s\n' "$url" "$digest"
}

download_release_asset(){
  local repo=$1 tag=$2 asset=$3 out=$4 url digest='' actual info
  url="https://github.com/$repo/releases/download/$tag/$asset"
  info=$(api_asset "$repo" "$tag" "$asset" 2>/dev/null || true)
  if [[ -n $info ]]; then IFS=$'\t' read -r url digest <<<"$info"; fi
  say "Downloading $asset"
  retry curl --proto '=https' --tlsv1.2 -fL --retry 3 -H 'User-Agent: terminal-env-installer' -o "$out" "$url" || die "Download failed: $asset"
  if [[ $digest == sha256:* ]]; then
    actual=$(sha256_file "$out") || die "No SHA-256 implementation available"
    [[ $actual == "${digest#sha256:}" ]] || die "SHA-256 mismatch for $asset"
  elif [[ -z $info ]]; then
    warn "GitHub release metadata unavailable for $asset; deterministic HTTPS release URL was used."
  fi
}

atomic_install_file(){
  local src=$1 dest=$2 mode=${3:-0755}
  local staged
  staged="${dest}.new.$$"
  install -m "$mode" "$src" "$staged"
  mv -f "$staged" "$dest"
}

install_archive_binary(){
  local archive=$1 binary=$2 dest=$3 tmp
  tmp=$(mktemp -d)
  (
    trap 'rm -rf "$tmp"' EXIT
    local found
    case "$archive" in *.tar.gz|*.tgz) tar -xzf "$archive" -C "$tmp";; *.tar.xz) tar -xJf "$archive" -C "$tmp";; *.zip) unzip -q "$archive" -d "$tmp";; *) die "Unsupported archive: $archive";; esac
    found=$(find "$tmp" -type f \( -name "$binary" -o -name "$binary.exe" \) -print -quit)
    [[ -n "$found" ]] || die "Archive did not contain $binary"
    atomic_install_file "$found" "$dest" 0755
  )
}

terminal_state_dir(){ printf '%s\n' "${TERMINAL_ENV_STATE:-$HOME/.local/state/terminal-env}"; }
transaction_backup_root(){ printf '%s/backups/transactions\n' "$(terminal_state_dir)"; }
manual_backup_root(){ printf '%s/backups/manual\n' "$(terminal_state_dir)"; }
path_size_bytes(){
  local p=$1 kb
  [[ -e $p ]] || { printf '0\n'; return; }
  kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}') || kb=0
  printf '%s\n' "$(( ${kb:-0} * 1024 ))"
}
prune_transaction_backups(){
  local keep=${1:-3} state root original dir kept=0
  state=$(terminal_state_dir); root=$(transaction_backup_root)
  [[ -d $root ]] || return 0
  original=$(cat "$state/original-backup" 2>/dev/null || true)
  while IFS= read -r dir; do
    [[ -n $dir && -f "$dir/.complete" ]] || continue
    if [[ -n $original && $dir == "$original" ]]; then continue; fi
    kept=$((kept+1))
    (( kept <= keep )) && continue
    rm -rf -- "$dir"
  done < <(for dir in "$root"/install-*; do [[ -d $dir ]] && printf '%s\n' "$dir"; done | sort -r)
  # Legacy development builds stored transaction directories directly under backups/.
  # Once a new transaction has succeeded, only the original restore point has
  # long-term value; manual backup archives are files and are never touched.
  local legacy_root="$state/backups" legacy
  for legacy in "$legacy_root"/install-* "$legacy_root"/20??????T??????Z*; do
    [[ -d $legacy ]] || continue
    [[ -n $original && $legacy == "$original" ]] && continue
    rm -rf -- "$legacy"
  done
}
cleanup_failed_transaction(){
  local dir=$1 state original
  [[ -d $dir ]] || return 0
  state=$(terminal_state_dir); original=$(cat "$state/original-backup" 2>/dev/null || true)
  [[ -n $original && $dir == "$original" ]] || rm -rf -- "$dir"
}
