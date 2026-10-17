# Better ls (eza required; fall back to plain ls if absent)
if (( $+commands[eza] )); then
  alias ls='eza --icons'
  alias ll='eza -lh --icons --git'      # detailed listing
  alias la='eza -lah --icons --git'     # detailed listing including hidden files
  alias tree='eza --tree --icons'       # tree view
fi

alias git_personal='git config user.email "s0nprem0@proton.me" && git config user.name "s0nprem0"'
alias git_academic='git config user.email "jaysonbulugagao@gmail.com" && git config user.name "202302986"'