# Shared visual language for fuzzy search and interactive file listings.
export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-} --height=62% --layout=reverse --border=rounded --info=inline-right --no-separator --pointer=› --marker=+ --color=bg+:#11161d,bg:#090d12,spinner:#7dd7ff,hl:#7dd7ff,fg:#e7edf3,header:#6c7986,info:#6c7986,pointer:#7dd7ff,marker:#a6d189,prompt:#8ab4ff,hl+:#c5a6f5,border:#25303b,label:#a7b3bf"

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

if [[ -z ${NO_COLOR:-} ]]; then
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
  export EZA_COLORS='di=1;38;2;125;215;255:ln=38;2;197;166;245:ex=1;38;2;166;209;137:da=38;2;108;121;134:sn=38;2;108;121;134:uu=38;2;229;192;123:gu=38;2;229;192;123:ur=38;2;167;179;191:uw=38;2;229;192;123:ux=38;2;166;209;137:gr=38;2;108;121;134:gw=38;2;229;192;123:gx=38;2;166;209;137:tr=38;2;231;237;243:tw=38;2;229;192;123:tx=38;2;166;209;137:fi=38;2;231;237;243'
  alias l='eza --icons=auto --group-directories-first --color=always'
  alias la='eza -a --icons=auto --group-directories-first --color=always'
  alias ll='eza -lah --icons=auto --group-directories-first --git --color=always'
  alias lt='eza --tree --icons=auto --group-directories-first --color=always'
else
  alias l='ls -lah'
  alias la='ls -la'
  alias ll='ls -lah'
fi
