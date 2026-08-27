autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search

# Atuin owns deep Ctrl-R search, but not Up/Down. If it is unavailable the native widget remains.
if [[ -r "$XDG_CACHE_HOME/terminal-env/zsh/atuin.zsh" ]]; then
  source "$XDG_CACHE_HOME/terminal-env/zsh/atuin.zsh"
elif (( $+commands[atuin] )); then
  eval "$(atuin init zsh --disable-up-arrow --disable-ai 2>/dev/null)" || true
fi
