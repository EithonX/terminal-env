mkdir -p "$XDG_STATE_HOME/zsh" 2>/dev/null
HISTFILE="$XDG_STATE_HOME/zsh/history"
HISTSIZE=200000
SAVEHIST=200000
setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_FCNTL_LOCK
setopt EXTENDED_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_SAVE_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY

# Commands intentionally prefixed with a space are never persisted. Obvious inline
# credential forms are also excluded so history-backed inline suggestions do not resurface them.
HISTORY_IGNORE='( *|*(Authorization:[[:space:]]#Bearer|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]=|[Ss][Ee][Cc][Rr][Ee][Tt]=|[Tt][Oo][Kk][Ee][Nn]=|[Aa][Pp][Ii]_[Kk][Ee][Yy]=)*)'
