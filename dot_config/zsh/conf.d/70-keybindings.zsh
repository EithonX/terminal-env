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
