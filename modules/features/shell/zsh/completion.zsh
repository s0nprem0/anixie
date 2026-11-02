# Home Manager already runs compinit (at init order 570); these are the
# completion styles that go with it, plus the LS_COLORS cache.

# Cache `dircolors -b` output once (LS_COLORS is otherwise unset, leaving
# the list-colors zstyle empty).
LSCOLORS_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/dircolors.zsh"
if (( $+commands[dircolors] )); then
    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
    if [[ ! -s "$LSCOLORS_CACHE" ]]; then
        dircolors -b > "$LSCOLORS_CACHE"
    fi
    source "$LSCOLORS_CACHE"
fi

zstyle ':completion:*:*:*:*:*' menu select
zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' rehash true
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

# anixie: group names first, then that group's own words, then files. Both lists
# are read back from the command (`anixie commands --aliases` and `anixie
# subcommands`), so completion cannot list something the dispatcher does not know
# — including the aliases, which are real groups but not primary names.
_anixie() {
  case $CURRENT in
    2)
      local -a groups
      groups=( ${(f)"$(command anixie commands --aliases 2>/dev/null)"} )
      _describe -t groups 'anixie group' groups
      ;;
    3)
      local -a subs
      subs=( ${(f)"$(command anixie subcommands "${words[2]}" 2>/dev/null)"} )
      if (( ${#subs} )); then
        _describe -t subcommands 'subcommand' subs
      else
        _files
      fi
      ;;
    *)
      _files
      ;;
  esac
}
compdef _anixie anixie
