# Optional machine-local customization. This file is intentionally unmanaged.
local _terminal_env_local="$XDG_CONFIG_HOME/terminal-env/local.zsh"
[[ -r "$_terminal_env_local" ]] && source "$_terminal_env_local"
unset _terminal_env_local
