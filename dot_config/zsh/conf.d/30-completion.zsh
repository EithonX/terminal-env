# Pinned completion functions are generated during setup; missing files fail open.
[[ -r "$XDG_CACHE_HOME/terminal-env/zsh/fpath.zsh" ]] && source "$XDG_CACHE_HOME/terminal-env/zsh/fpath.zsh"

autoload -Uz compinit
_zcompdump="$XDG_CACHE_HOME/zsh/zcompdump-${ZSH_VERSION}"
mkdir -p "${_zcompdump:h}" 2>/dev/null

# A full compaudit/compinit runs at least once per day. Subsequent shells use the dump.
zmodload -F zsh/stat b:zstat 2>/dev/null || true
zmodload zsh/datetime 2>/dev/null || true
_zcomp_full=1
if [[ -s $_zcompdump ]] && (( $+builtins[zstat] )); then
  typeset -A _zst
  if zstat -H _zst -- "$_zcompdump" 2>/dev/null; then
    (( EPOCHSECONDS - _zst[mtime] < 86400 )) && _zcomp_full=0
  fi
fi
if (( _zcomp_full )); then
  compinit -d "$_zcompdump"
else
  compinit -C -d "$_zcompdump"
fi
unset _zcompdump _zcomp_full _zst

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' menu no
zstyle ':completion:*' group-name ''
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/completion"
zstyle ':completion:*:descriptions' format '%F{#98a6b3}  %d%f'
zstyle ':completion:*:warnings' format '%F{#f38ba8}  no matches%f'
[[ -n ${LS_COLORS:-} ]] && zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# fzf-tab decorates real Zsh completion; if absent, Tab remains native completion.
[[ ${TERM:-} != dumb && -r "$XDG_CACHE_HOME/terminal-env/zsh/interactive.zsh" ]] && source "$XDG_CACHE_HOME/terminal-env/zsh/interactive.zsh"
if (( $+functions[fzf-tab-complete] )); then
  zstyle ':fzf-tab:*' switch-group ',' '.'
  zstyle ':fzf-tab:*' fzf-flags --height=62% --layout=reverse --border=rounded --info=inline-right --no-separator --pointer=› --marker=+
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'command eza -la --icons=auto --group-directories-first --color=always -- "$realpath" 2>/dev/null || command ls -la --color=always -- "$realpath" 2>/dev/null || command ls -la -- "$realpath"'
fi
