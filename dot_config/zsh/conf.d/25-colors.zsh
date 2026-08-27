# Resolve file colors before completion reads LS_COLORS. Prefer the setup-time cache.
if [[ -r "$XDG_CACHE_HOME/terminal-env/ls-colors" ]]; then
  export LS_COLORS="$(<"$XDG_CACHE_HOME/terminal-env/ls-colors")"
elif (( $+commands[vivid] )); then
  export LS_COLORS="$(vivid generate terminal-env 2>/dev/null || vivid generate ansi 2>/dev/null)"
elif (( $+commands[dircolors] )); then
  eval "$(dircolors -b 2>/dev/null)"
fi
