if [[ -t 0 && -t 1 ]] && (( $+commands[gpg-connect-agent] )); then
  export GPG_TTY="$(tty 2>/dev/null)"
  [[ -n $GPG_TTY ]] && gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true
fi
