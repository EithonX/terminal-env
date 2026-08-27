# Must be last: zsh-syntax-highlighting needs to observe widgets defined above it.
[[ ${TERM:-} != dumb && -r "$XDG_CACHE_HOME/terminal-env/zsh/final.zsh" ]] && source "$XDG_CACHE_HOME/terminal-env/zsh/final.zsh"
if (( ${+ZSH_HIGHLIGHT_STYLES} )); then
  ZSH_HIGHLIGHT_STYLES[command]='fg=#8aadf4,bold'
  ZSH_HIGHLIGHT_STYLES[builtin]='fg=#8aadf4'
  ZSH_HIGHLIGHT_STYLES[function]='fg=#8aadf4'
  ZSH_HIGHLIGHT_STYLES[alias]='fg=#c4a7e7'
  ZSH_HIGHLIGHT_STYLES[path]='fg=#7dd3fc,underline'
  ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#a6d189'
  ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#a6d189'
  ZSH_HIGHLIGHT_STYLES[comment]='fg=#56636e'
  ZSH_HIGHLIGHT_STYLES[redirection]='fg=#e5c07b'
  ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#98a6b3'
  ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#f38ba8,bold'
fi
