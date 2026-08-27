# Inline suggestions combine live Zsh completion with command history.
# Tab remains explicit fzf-tab completion; Ctrl+R remains Atuin deep history.
_zsh_autosuggest_strategy_terminal_env_autosuggest() {
  emulate -L zsh
  typeset -g suggestion
  local buffer=$1 candidate=''
  suggestion=''

  [[ -n $buffer ]] || return 0

  # Large or multiline buffers are usually pasted/generated commands. Avoid
  # invoking arbitrary CLI completers for those; history lookup stays cheap.
  if [[ $buffer == *$'\n'* || $buffer == *$'\r'* ]] || (( ${#buffer} > 180 )); then
    _zsh_autosuggest_strategy_history "$buffer"
    return 0
  fi

  if [[ $buffer == *[[:space:]]* ]]; then
    # Once arguments are being typed, current truth beats stale history: this
    # is what makes unseen files, folders, branches, flags and service names
    # eligible for inline suggestion when their completer exposes them.
    _zsh_autosuggest_strategy_completion "$buffer"
    candidate=$suggestion
    if [[ -n $candidate && $candidate != "$buffer" ]]; then
      suggestion=$candidate
      return 0
    fi
    _zsh_autosuggest_strategy_history "$buffer"
  else
    # For the first command token, repetitive full-command recall is usually
    # more valuable. Fall back to command completion when history has no hit.
    _zsh_autosuggest_strategy_history "$buffer"
    candidate=$suggestion
    if [[ -z $candidate || $candidate == "$buffer" ]]; then
      _zsh_autosuggest_strategy_completion "$buffer"
    fi
  fi
}

_autosuggest_plugin="$HOME/.local/share/terminal-env/zsh-plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
if [[ -r $_autosuggest_plugin ]]; then
  # Atuin deliberately adds its own zsh-autosuggestions strategy during init.
  # Override it here: Atuin owns Ctrl+R/history recording, not per-keystroke
  # ghost text. This also avoids its CLI query path competing with completion.
  typeset -ga ZSH_AUTOSUGGEST_STRATEGY
  ZSH_AUTOSUGGEST_STRATEGY=(terminal_env_autosuggest)
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c7986'
  ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=512
  source "$_autosuggest_plugin"

  # Common xterm/Windows Terminal Ctrl+Right sequences. forward-word is a
  # native partial-accept widget wrapped by zsh-autosuggestions.
  bindkey '^[[1;5C' forward-word
  bindkey '^[[5C' forward-word
fi
unset _autosuggest_plugin
