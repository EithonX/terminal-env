# Shared visual language for fuzzy search and interactive file listings.
_fzf_terminal_env_base=' --style=minimal --height=~60% --min-height=10+ --layout=reverse --info=inline-right --no-separator --pointer=› --marker=+'
if [[ ${TERM:-} == dumb || -n ${NO_COLOR:-} ]]; then
  export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-}${_fzf_terminal_env_base} --no-color"
else
  export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-}${_fzf_terminal_env_base} --color=bg+:#151b22,bg:#0a0e13,spinner:#707c88,hl:#7cc4e4,fg:#e6ebf0,header:#707c88,info:#707c88,pointer:#7cc4e4,marker:#7cc4e4,prompt:#7cc4e4,hl+:#7cc4e4,border:#28323d,label:#a2acb7"
fi
unset _fzf_terminal_env_base

if [[ ${TERM:-} != dumb && -r "$XDG_CACHE_HOME/terminal-env/zsh/fzf.zsh" ]]; then
  source "$XDG_CACHE_HOME/terminal-env/zsh/fzf.zsh"
elif [[ ${TERM:-} != dumb ]] && (( $+commands[fzf] )); then
  source <(fzf --zsh 2>/dev/null) || true
fi
if [[ -r "$XDG_CACHE_HOME/terminal-env/zsh/zoxide.zsh" ]]; then
  source "$XDG_CACHE_HOME/terminal-env/zsh/zoxide.zsh"
elif (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh --cmd z)"
fi
export BAT_THEME=ansi
export BAT_STYLE=numbers,changes,header
(( $+commands[delta] )) && export GIT_PAGER=delta

if [[ ${TERM:-} != dumb && -z ${NO_COLOR:-} ]]; then
  if [[ $OSTYPE == darwin* ]]; then
    export CLICOLOR=1
    alias ls='ls -G'
  else
    alias ls='ls --color=auto'
  fi
  (( $+commands[grep] )) && alias grep='grep --color=auto'
fi

mkcd() { [[ $# == 1 ]] || { print -u2 'usage: mkcd <directory>'; return 2; }; mkdir -p -- "$1" && cd -- "$1"; }
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

if (( $+commands[eza] )); then
  export EZA_ICONS_AUTO=1
  export EZA_COLORS='di=1;38;2;124;196;228:ln=38;2;162;172;183:ex=1;38;2;230;235;240:da=38;2;112;124;136:sn=38;2;112;124;136:uu=38;2;214;168;95:gu=38;2;214;168;95:ur=38;2;162;172;183:uw=38;2;214;168;95:ux=1;38;2;230;235;240:gr=38;2;112;124;136:gw=38;2;214;168;95:gx=1;38;2;230;235;240:tr=38;2;230;235;240:tw=38;2;214;168;95:tx=1;38;2;230;235;240:fi=38;2;230;235;240'
  if [[ ${TERM:-} == dumb || -n ${NO_COLOR:-} ]]; then
    _terminal_env_eza_color=never
  else
    _terminal_env_eza_color=auto
  fi
  alias l="eza --icons=auto --group-directories-first --color=${_terminal_env_eza_color}"
  alias la="eza -a --icons=auto --group-directories-first --color=${_terminal_env_eza_color}"
  alias ll="eza -lah --icons=auto --group-directories-first --git --color=${_terminal_env_eza_color}"
  alias lt="eza --tree --icons=auto --group-directories-first --color=${_terminal_env_eza_color}"
  unset _terminal_env_eza_color
else
  alias l='ls -lah'
  alias la='ls -la'
  alias ll='ls -lah'
fi
