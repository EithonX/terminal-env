# Prompt must fail open. --strict resolves the binary through PATH after upgrades.
if (( EUID == 0 )); then
  _terminal_env_fallback_prompt='%F{203}%BROOT%b%f %F{81}%n@%m%f %F{110}%~%f %# '
else
  _terminal_env_fallback_prompt='%F{81}%n@%m%f %F{110}%~%f %# '
fi

if [[ ${TERM:-} != dumb ]] && (( $+commands[oh-my-posh] )) && [[ -r "$XDG_CONFIG_HOME/oh-my-posh/terminal.omp.json" ]]; then
  eval "$(oh-my-posh init zsh --strict --config "$XDG_CONFIG_HOME/oh-my-posh/terminal.omp.json" 2>/dev/null)" || {
    PROMPT=$_terminal_env_fallback_prompt
  }
else
  PROMPT=$_terminal_env_fallback_prompt
fi
unset _terminal_env_fallback_prompt
