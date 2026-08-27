# Deja owns inline prediction. Tab belongs exclusively to shell completion.
if (( $+commands[deja] )); then
  export DEJA_CYCLE_KEY='^N'
  export DEJA_HIGHLIGHT_STYLE='fg=#56636e'
  export DEJA_DISMISS_KEY='^G'
  if [[ -r "$HOME/.local/share/deja/init.zsh" ]]; then
    source "$HOME/.local/share/deja/init.zsh"
  else
    eval "$(deja init zsh 2>/dev/null)" || true
  fi
fi
