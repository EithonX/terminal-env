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
  [[ $DRY_RUN == 1 ]] && { say "Would install pinned Oh My Posh, Atuin, fzf, zoxide and Deja releases"; return 0; }
  local tmp; tmp=$(mktemp -d)
  local omp_asset atuin_asset fzf_asset zoxide_asset deja_asset
  if [[ $OS == linux ]]; then
    omp_asset="posh-linux-$ARCH"
    [[ $ARCH == amd64 ]] && atuin_asset="atuin-x86_64-unknown-linux-gnu.tar.gz" || atuin_asset="atuin-aarch64-unknown-linux-gnu.tar.gz"
    fzf_asset="fzf-${FZF_VERSION}-linux_${ARCH}.tar.gz"
    [[ $ARCH == amd64 ]] && zoxide_asset="zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz" || zoxide_asset="zoxide-${ZOXIDE_VERSION}-aarch64-unknown-linux-musl.tar.gz"
    deja_asset="deja_${DEJA_VERSION}_linux_${ARCH}.tar.gz"
  else
    omp_asset="posh-darwin-$ARCH"
    [[ $ARCH == amd64 ]] && atuin_asset="atuin-x86_64-apple-darwin.tar.gz" || atuin_asset="atuin-aarch64-apple-darwin.tar.gz"
    fzf_asset="fzf-${FZF_VERSION}-darwin_${ARCH}.tar.gz"
    [[ $ARCH == amd64 ]] && zoxide_asset="zoxide-${ZOXIDE_VERSION}-x86_64-apple-darwin.tar.gz" || zoxide_asset="zoxide-${ZOXIDE_VERSION}-aarch64-apple-darwin.tar.gz"
    deja_asset="deja_${DEJA_VERSION}_darwin_${ARCH}.tar.gz"
  fi

  download_release_asset JanDeDobbeleer/oh-my-posh "v$OH_MY_POSH_VERSION" "$omp_asset" "$tmp/omp"
  atomic_install_file "$tmp/omp" "$LOCAL_BIN/oh-my-posh" 0755
  download_release_asset atuinsh/atuin "v$ATUIN_VERSION" "$atuin_asset" "$tmp/atuin.tar.gz"
  install_archive_binary "$tmp/atuin.tar.gz" atuin "$LOCAL_BIN/atuin"
  download_release_asset junegunn/fzf "v$FZF_VERSION" "$fzf_asset" "$tmp/fzf.tar.gz"
  install_archive_binary "$tmp/fzf.tar.gz" fzf "$LOCAL_BIN/fzf"
  download_release_asset ajeetdsouza/zoxide "v$ZOXIDE_VERSION" "$zoxide_asset" "$tmp/zoxide.tar.gz"
  install_archive_binary "$tmp/zoxide.tar.gz" zoxide "$LOCAL_BIN/zoxide"
  download_release_asset Giammarco-Ferranti/deja "v$DEJA_VERSION" "$deja_asset" "$tmp/deja.tar.gz"
  install_archive_binary "$tmp/deja.tar.gz" deja "$LOCAL_BIN/deja"
  rm -rf "$tmp"
}

install_font(){
  [[ $PROFILE == workstation && $NO_FONT == 0 ]] || return 0
  if [[ $DRY_RUN == 1 ]]; then say "Would install Monaspice Neon Nerd Font for the current user"; return 0; fi
  local tmp fontdir archive="Monaspace.tar.xz" count
  tmp=$(mktemp -d)
  download_release_asset ryanoasis/nerd-fonts "v$NERD_FONTS_VERSION" "$archive" "$tmp/$archive"
  [[ $OS == darwin ]] && fontdir="$HOME/Library/Fonts" || fontdir="$HOME/.local/share/fonts"
  mkdir -p "$fontdir" "$tmp/font"
  tar -xJf "$tmp/$archive" -C "$tmp/font"
  count=$(find "$tmp/font" -type f \( -name 'MonaspiceNeNerdFont*.ttf' -o -name 'MonaspiceNeNerdFont*.otf' \) | wc -l | tr -d ' ')
  (( count > 0 )) || { rm -rf "$tmp"; die "Monaspace archive did not contain Monaspice Neon Nerd Font files"; }
  find "$tmp/font" -type f \( -name 'MonaspiceNeNerdFont*.ttf' -o -name 'MonaspiceNeNerdFont*.otf' \) -exec cp -f {} "$fontdir/" \;
  [[ $OS == linux ]] && have fc-cache && fc-cache -f "$fontdir" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}

install_system_packages
install_github_tools
install_font

if [[ $DRY_RUN == 0 ]]; then
  if ! have bat && have batcat; then ln -sfn "$(command -v batcat)" "$LOCAL_BIN/bat"; fi
  if ! have fd && have fdfind; then ln -sfn "$(command -v fdfind)" "$LOCAL_BIN/fd"; fi
fi
ok "Tool provisioning complete."
