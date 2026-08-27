# Keep zsh powerful while making ordinary AI-pasted Bash-style commands unsurprising.
setopt INTERACTIVE_COMMENTS
unsetopt NOMATCH
unsetopt BANG_HIST
setopt NO_BEEP
setopt EXTENDED_GLOB

bindkey -e
WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'
