# Prompt must fail open. --strict resolves the binary through PATH after upgrades.
if [[ ${TERM:-} != dumb ]] && (( $+commands[oh-my-posh] )) && [[ -r "$XDG_CONFIG_HOME/oh-my-posh/terminal.omp.json" ]]; then
  eval "$(oh-my-posh init zsh --strict --config "$XDG_CONFIG_HOME/oh-my-posh/terminal.omp.json" 2>/dev/null)" || {
    PROMPT='%F{81}%n@%m%f %F{110}%~%f %# '
  }
else
  PROMPT='%F{81}%n@%m%f %F{110}%~%f %# '
fi
