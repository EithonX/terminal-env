zmodload zsh/terminfo 2>/dev/null || true
bindkey '^[[D' backward-char
bindkey '^[OD' backward-char
bindkey '^[[C' forward-char
bindkey '^[OC' forward-char
bindkey '^[[1;5D' backward-word
bindkey '^[[5D' backward-word
bindkey '^[[1;5C' forward-word
bindkey '^[[5C' forward-word
bindkey '^[[H' beginning-of-line
bindkey '^[OH' beginning-of-line
bindkey '^[[1~' beginning-of-line
bindkey '^[[7~' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[OF' end-of-line
bindkey '^[[4~' end-of-line
bindkey '^[[8~' end-of-line
bindkey '^[[3~' delete-char
[[ -n ${terminfo[kcub1]-} ]] && bindkey "$terminfo[kcub1]" backward-char
[[ -n ${terminfo[kcuf1]-} ]] && bindkey "$terminfo[kcuf1]" forward-char
[[ -n ${terminfo[khome]-} ]] && bindkey "$terminfo[khome]" beginning-of-line
[[ -n ${terminfo[kend]-} ]] && bindkey "$terminfo[kend]" end-of-line
[[ -n ${terminfo[kdch1]-} ]] && bindkey "$terminfo[kdch1]" delete-char

# Contextual sudo toggle: deliberately absent for root and machines without sudo.
if (( EUID != 0 )) && (( $+commands[sudo] )); then
  terminal-env-sudo-toggle() {
    [[ -z $BUFFER ]] && zle up-history
    if [[ $BUFFER == sudo\ * ]]; then BUFFER="${BUFFER#sudo }"; else BUFFER="sudo $BUFFER"; fi
    CURSOR=${#BUFFER}
  }
  zle -N terminal-env-sudo-toggle
  bindkey '\e\e' terminal-env-sudo-toggle
fi
