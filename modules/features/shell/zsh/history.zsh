# History configuration.
# When atuin is installed it owns interactive history (search, recording);
# these settings remain as the on-disk source for `atuin import auto`
# and as a fallback on machines without atuin.
mkdir -p "$XDG_STATE_HOME/zsh"
HISTFILE="$XDG_STATE_HOME/zsh/history"
HISTSIZE=10000
SAVEHIST=20000

if (( !$+commands[atuin] )); then
  setopt hist_expire_dups_first # delete duplicates first when HISTFILE size exceeds HISTSIZE
  setopt hist_ignore_dups       # ignore duplicated commands history list
  setopt hist_ignore_space      # ignore commands that start with space
  setopt hist_verify            # show command with history expansion to user before running it
  setopt hist_reduce_blanks     # strip extra blanks before recording history
  setopt extended_history       # save timestamps and command durations to the history file
  setopt inc_append_history     # write commands immediately, not just on shell exit

  # force zsh to show the complete history
  alias history="history 0"
fi

# configure `time` format
TIMEFMT=$'\nreal\t%E\nuser\t%U\nsys\t%S\ncpu\t%P'

if (( $+commands[zoxide] )); then
    # Cache the init script to speed up shell startup; regenerate when the
    # binary is newer than the cache (i.e. after an upgrade)
    ZOXIDE_CACHE="$XDG_CACHE_HOME/zsh/zoxide.zsh"
    mkdir -p "$XDG_CACHE_HOME/zsh"
    if [[ ! -s "$ZOXIDE_CACHE" || "$commands[zoxide]" -nt "$ZOXIDE_CACHE" ]]; then
        zoxide init zsh > "$ZOXIDE_CACHE"
    fi
    source "$ZOXIDE_CACHE"
fi

if (( $+commands[atuin] )); then
    # Atuin: fuzzy searchable history, bound to Up and Ctrl-R.
    # Cached like zoxide; regenerated after binary upgrades.
    ATUIN_CACHE="$XDG_CACHE_HOME/zsh/atuin.zsh"
    mkdir -p "$XDG_CACHE_HOME/zsh"
    if [[ ! -s "$ATUIN_CACHE" || "$commands[atuin]" -nt "$ATUIN_CACHE" ]]; then
        atuin init zsh > "$ATUIN_CACHE"
    fi
    source "$ATUIN_CACHE"
fi