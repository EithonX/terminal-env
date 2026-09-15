# Must be last: zsh-syntax-highlighting needs to observe widgets defined above it.
[[ ${TERM:-} != dumb && -z ${NO_COLOR:-} && -r "$XDG_CACHE_HOME/terminal-env/zsh/final.zsh" ]] && source "$XDG_CACHE_HOME/terminal-env/zsh/final.zsh"
if [[ ${TERM:-} != dumb && -z ${NO_COLOR:-} ]] && (( ${+ZSH_HIGHLIGHT_STYLES} )); then
  ZSH_HIGHLIGHT_STYLES[command]='fg=#7cc4e4,bold'
  ZSH_HIGHLIGHT_STYLES[builtin]='fg=#7cc4e4'
  ZSH_HIGHLIGHT_STYLES[function]='fg=#7cc4e4'
  ZSH_HIGHLIGHT_STYLES[alias]='fg=#a2acb7'
  ZSH_HIGHLIGHT_STYLES[path]='fg=#7cc4e4,underline'
  ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#e6ebf0'
  ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#e6ebf0'
  ZSH_HIGHLIGHT_STYLES[comment]='fg=#707c88'
  ZSH_HIGHLIGHT_STYLES[redirection]='fg=#707c88'
  ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#707c88'
  ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#e07880,bold'
fi
