#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/scripts/lib/common.sh"
source "$ROOT/versions.env"
PROFILE=${PROFILE:-server}; DRY_RUN=${DRY_RUN:-0}; NO_FONT=${NO_FONT:-0}
OS=$(os_name); ARCH=$(arch_name)
[[ $OS != unsupported && $ARCH != unsupported ]] || die "Unsupported platform $(uname -s)/$(uname -m)"
LOCAL_BIN="$HOME/.local/bin"; ensure_dir "$LOCAL_BIN"

install_system_packages(){
  if [[ $OS == linux ]]; then
    have apt-get || die "Linux provisioning currently supports Ubuntu/Debian systems with apt-get."
    local sudo_cmd=(); [[ $EUID -ne 0 ]] && sudo_cmd=(sudo)
    run "${sudo_cmd[@]}" apt-get update
    local required=(zsh git curl ca-certificates gnupg jq unzip xz-utils tar)
    local optional=()
    [[ $PROFILE != minimal ]] && optional+=(ripgrep bat fd-find eza git-delta vivid)
    [[ $PROFILE == server ]] && optional+=(tmux)
    [[ $PROFILE == workstation ]] && optional+=(shellcheck ghostty)
    if [[ $DRY_RUN == 1 ]]; then
      run "${sudo_cmd[@]}" apt-get install -y "${required[@]}" "${optional[@]}"
      return 0
    fi
    local p missing=()
    for p in "${required[@]}"; do apt-cache show "$p" >/dev/null 2>&1 || missing+=("$p"); done
    ((${#missing[@]} == 0)) || die "Required apt packages are unavailable: ${missing[*]}"
    run "${sudo_cmd[@]}" apt-get install -y "${required[@]}"
    local available=() unavailable=()
    for p in "${optional[@]}"; do if apt-cache show "$p" >/dev/null 2>&1; then available+=("$p"); else unavailable+=("$p"); fi; done
    ((${#available[@]} == 0)) || run "${sudo_cmd[@]}" apt-get install -y "${available[@]}"
    ((${#unavailable[@]} == 0)) || warn "Optional distro packages unavailable here: ${unavailable[*]}. Core shell features do not depend on them."
  else
    if ! have brew && [[ $DRY_RUN == 0 ]]; then
      die "Homebrew is required for macOS provisioning. Install Homebrew once, then rerun this installer."
    fi
    local pkgs=(zsh git gnupg jq)
    [[ $PROFILE != minimal ]] && pkgs+=(ripgrep bat fd eza git-delta shellcheck vivid)
    [[ $PROFILE == server ]] && pkgs+=(tmux)
    run brew install "${pkgs[@]}"
    if [[ $PROFILE == workstation ]]; then run brew install --cask ghostty || warn "Ghostty installation failed; shell setup can still be used in another terminal."; fi
  fi
}

install_github_tools(){
  [[ $PROFILE == minimal ]] && return 0
  [[ $DRY_RUN == 1 ]] && { say "Would install pinned Oh My Posh, Atuin, fzf and zoxide releases"; return 0; }
  local tmp; tmp=$(mktemp -d)
  (
    trap 'rm -rf "$tmp"' EXIT
    local omp_asset atuin_asset fzf_asset zoxide_asset
    if [[ $OS == linux ]]; then
      omp_asset="posh-linux-$ARCH"
      [[ $ARCH == amd64 ]] && atuin_asset="atuin-x86_64-unknown-linux-gnu.tar.gz" || atuin_asset="atuin-aarch64-unknown-linux-gnu.tar.gz"
      fzf_asset="fzf-${FZF_VERSION}-linux_${ARCH}.tar.gz"
      [[ $ARCH == amd64 ]] && zoxide_asset="zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz" || zoxide_asset="zoxide-${ZOXIDE_VERSION}-aarch64-unknown-linux-musl.tar.gz"
    else
      omp_asset="posh-darwin-$ARCH"
      [[ $ARCH == amd64 ]] && atuin_asset="atuin-x86_64-apple-darwin.tar.gz" || atuin_asset="atuin-aarch64-apple-darwin.tar.gz"
      fzf_asset="fzf-${FZF_VERSION}-darwin_${ARCH}.tar.gz"
      [[ $ARCH == amd64 ]] && zoxide_asset="zoxide-${ZOXIDE_VERSION}-x86_64-apple-darwin.tar.gz" || zoxide_asset="zoxide-${ZOXIDE_VERSION}-aarch64-apple-darwin.tar.gz"
    fi

    download_release_asset JanDeDobbeleer/oh-my-posh "v$OH_MY_POSH_VERSION" "$omp_asset" "$tmp/omp"
    atomic_install_file "$tmp/omp" "$LOCAL_BIN/oh-my-posh" 0755
    download_release_asset atuinsh/atuin "v$ATUIN_VERSION" "$atuin_asset" "$tmp/atuin.tar.gz"
    install_archive_binary "$tmp/atuin.tar.gz" atuin "$LOCAL_BIN/atuin"
    download_release_asset junegunn/fzf "v$FZF_VERSION" "$fzf_asset" "$tmp/fzf.tar.gz"
    install_archive_binary "$tmp/fzf.tar.gz" fzf "$LOCAL_BIN/fzf"
    download_release_asset ajeetdsouza/zoxide "v$ZOXIDE_VERSION" "$zoxide_asset" "$tmp/zoxide.tar.gz"
    install_archive_binary "$tmp/zoxide.tar.gz" zoxide "$LOCAL_BIN/zoxide"
  )
}

install_font(){
  [[ $PROFILE == workstation && $NO_FONT == 0 ]] || return 0
  if [[ $DRY_RUN == 1 ]]; then say "Would install the four Monaspice Neon Nerd Font RIBBI faces for the current user"; return 0; fi
  local tmp fontdir archive="Monaspace.tar.xz" state manifest list style member src base ext dest hash existing existing_hash
  local members=() selected=() current=()
  tmp=$(mktemp -d)
  state="$HOME/.local/state/terminal-env/fonts"
  manifest="$state/current"
  (
    trap 'rm -rf "$tmp"' EXIT
  download_release_asset ryanoasis/nerd-fonts "v$NERD_FONTS_VERSION" "$archive" "$tmp/$archive"
  list=$(tar -tf "$tmp/$archive")
  for style in Regular Bold Italic BoldItalic; do
    member=$(printf '%s\n' "$list" | awk -F/ -v n="MonaspiceNeNerdFont-${style}.otf" '$NF==n {print; exit}')
    [[ -n $member ]] || member=$(printf '%s\n' "$list" | awk -F/ -v n="MonaspiceNeNerdFont-${style}.ttf" '$NF==n {print; exit}')
    [[ -n $member ]] || die "Monaspace archive is missing Monaspice Neon $style"
    members+=("$member")
  done
  [[ $OS == darwin ]] && fontdir="$HOME/Library/Fonts" || fontdir="$HOME/.local/share/fonts"
  mkdir -p "$fontdir" "$tmp/font" "$state"
  tar -xf "$tmp/$archive" -C "$tmp/font" "${members[@]}"
  for member in "${members[@]}"; do
    src="$tmp/font/$member"; base=${member##*/}; ext=${base##*.}
    hash=$(sha256_file "$src") || die "Could not hash extracted font $base"
    existing="$fontdir/$base"
    if [[ -f $existing ]]; then
      existing_hash=$(sha256_file "$existing" 2>/dev/null || true)
      if [[ $existing_hash == "$hash" ]]; then
        current+=("$existing")
        continue
      fi
    fi
    dest="$fontdir/${base%.*}.terminal-env-${NERD_FONTS_VERSION}.${ext}"
    if [[ ! -f $dest || $(sha256_file "$dest" 2>/dev/null || true) != "$hash" ]]; then
      install -m 0644 "$src" "$dest.new.$$"
      mv -f "$dest.new.$$" "$dest"
    fi
    current+=("$dest")
  done
  : > "$manifest.tmp"
  printf '%s\n' "${current[@]}" > "$manifest.tmp"
  mv -f "$manifest.tmp" "$manifest"
  printf '%s\n' "$NERD_FONTS_VERSION" > "$state/version"
  # Only files with our explicit versioned suffix are ours to garbage-collect.
  shopt -s nullglob
  for old in "$fontdir"/MonaspiceNeNerdFont-*.terminal-env-*.otf "$fontdir"/MonaspiceNeNerdFont-*.terminal-env-*.ttf; do
    local keep=0 c
    for c in "${current[@]}"; do [[ $old == "$c" ]] && { keep=1; break; }; done
    (( keep )) || rm -f -- "$old"
  done
  shopt -u nullglob
  [[ $OS == linux ]] && have fc-cache && fc-cache -f "$fontdir" >/dev/null 2>&1 || true
  )
}

install_system_packages
install_github_tools
install_font

if [[ $DRY_RUN == 0 ]]; then
  if ! have bat && have batcat; then ln -sfn "$(command -v batcat)" "$LOCAL_BIN/bat"; fi
  if ! have fd && have fdfind; then ln -sfn "$(command -v fdfind)" "$LOCAL_BIN/fd"; fi
fi
ok "Tool provisioning complete."
