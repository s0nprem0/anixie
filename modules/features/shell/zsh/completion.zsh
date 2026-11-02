# Home Manager already runs compinit (at init order 570); these are the
# completion styles that go with it, plus the LS_COLORS cache.

# Cache `dircolors -b` output once (LS_COLORS is otherwise unset, leaving
# the list-colors zstyle empty). The first line records the generator so a
# changed format regenerates the cache, and the write goes through a temp file
# so an interrupted start cannot leave a half-written script to source.
LSCOLORS_HEADER="# anixie: dircolors -b v1"
LSCOLORS_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/dircolors.zsh"
if (( $+commands[dircolors] )); then
    mkdir -p "${LSCOLORS_CACHE:h}"
    if [[ ! -s "$LSCOLORS_CACHE" || "$(head -n 1 "$LSCOLORS_CACHE")" != "$LSCOLORS_HEADER" ]]; then
        if tmp=$(mktemp "$LSCOLORS_CACHE.XXXXXX"); then
            if {
                print -r -- "$LSCOLORS_HEADER"
                dircolors -b
            } > "$tmp"; then
                mv "$tmp" "$LSCOLORS_CACHE"
            else
                rm -f "$tmp"
            fi
            unset tmp
        fi
    fi
    if [[ -s "$LSCOLORS_CACHE" ]]; then
        source "$LSCOLORS_CACHE"
    fi
fi
unset LSCOLORS_HEADER LSCOLORS_CACHE

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
