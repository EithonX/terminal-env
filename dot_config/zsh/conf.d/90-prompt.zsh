# Prompt must fail open. --strict resolves the binary through PATH after upgrades.
zmodload zsh/datetime 2>/dev/null || true
typeset -g _TERMINAL_ENV_CONTEXT_CACHE_KEY=''
typeset -g _TERMINAL_ENV_CONTEXT_CACHE_AT=0
function set_poshcontext() {
  local key="${PWD}|${PATH}|${VIRTUAL_ENV:-}|${PYENV_VERSION:-}|${RUSTUP_TOOLCHAIN:-}|${GOTOOLCHAIN:-}"
  local now=${EPOCHSECONDS:-0}
  if [[ $key != $_TERMINAL_ENV_CONTEXT_CACHE_KEY || $now -eq 0 || $(( now - _TERMINAL_ENV_CONTEXT_CACHE_AT )) -ge 5 ]]; then
    local resolver="$HOME/.local/bin/terminal-context"
    local record state text
    if [[ -x $resolver ]]; then
      record="$("$resolver" --prompt-record 2>/dev/null)" || record=$'normal\t'
    else
      record=$'normal\t'
    fi
    if [[ $record == *$'\t'* ]]; then
      state=${record%%$'\t'*}
      text=${record#*$'\t'}
    else
      state=normal
      text=''
    fi
    export TERMINAL_ENV_PROJECT_CONTEXT=$text
    export TERMINAL_ENV_PROJECT_CONTEXT_STATE=$state
    _TERMINAL_ENV_CONTEXT_CACHE_KEY=$key
    _TERMINAL_ENV_CONTEXT_CACHE_AT=$now
  fi
}
function _terminal_env_render_fallback_prompt() {
  set_poshcontext
  local host_plain='' host_rich='' marker project project_part=''
  if [[ -n ${SSH_CONNECTION:-}${SSH_TTY:-} ]]; then
    host_plain='%m  '
    host_rich='%F{#a2acb7}%m%f  '
  fi
  if (( EUID == 0 )); then marker='#'; else marker='❯'; fi
  project=${TERMINAL_ENV_PROJECT_CONTEXT:-}
  project=${project//\%/%%}
  if [[ -n $project ]]; then project_part="  $project"; fi
  if [[ ${TERM:-} == dumb || -n ${NO_COLOR:-} ]]; then
    PROMPT="${host_plain}%~${project_part} │ ${marker} "
    return
  fi
  if [[ -n $project_part ]]; then
    if [[ ${TERMINAL_ENV_PROJECT_CONTEXT_STATE:-normal} == warning ]]; then
      project_part="%F{#d6a85f}${project_part}%f"
    else
      project_part="%F{#707c88}${project_part}%f"
    fi
  fi
  if (( EUID == 0 )); then
    PROMPT="${host_rich}%F{#7cc4e4}%~%f${project_part} %F{#707c88}│%f %F{#e07880}#%f "
  else
    PROMPT="${host_rich}%F{#7cc4e4}%~%f${project_part} %F{#707c88}│%f %F{#e6ebf0}❯%f "
  fi
}
function _terminal_env_enable_fallback_prompt() {
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _terminal_env_render_fallback_prompt
  _terminal_env_render_fallback_prompt
}

if [[ ${TERM:-} != dumb ]] && (( $+commands[oh-my-posh] )) && [[ -r "$XDG_CONFIG_HOME/oh-my-posh/terminal.omp.json" ]]; then
  eval "$(oh-my-posh init zsh --strict --config "$XDG_CONFIG_HOME/oh-my-posh/terminal.omp.json" 2>/dev/null)" || _terminal_env_enable_fallback_prompt
else
  _terminal_env_enable_fallback_prompt
fi
