# Tool setup for history. The history itself — HISTFILE, HISTSIZE, SAVEHIST and
# the setopts — is configured in default.nix (programs.zsh.history), because
# Home Manager writes its own history block at init order 910, after this file.
#
# Atuin owns interactive history (Up and Ctrl-R; bindings.zsh puts Ctrl-R back
# after fzf claims it). The `history` builtin still reads the zsh file, so it is
# useful on a machine without Atuin too.
alias history="history 0"

# configure `time` format
TIMEFMT=$'\nreal\t%E\nuser\t%U\nsys\t%S\ncpu\t%P'

if (( $+commands[zoxide] )); then
    # Cache the init script to speed up shell startup; regenerate when the
    # binary is newer than the cache (i.e. after an upgrade). The temp+mv keeps
    # a failed or interrupted run from leaving a truncated script to source.
    ZOXIDE_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zoxide.zsh"
    mkdir -p "${ZOXIDE_CACHE:h}"
    if [[ ! -s "$ZOXIDE_CACHE" || "$commands[zoxide]" -nt "$ZOXIDE_CACHE" ]]; then
        if tmp=$(mktemp "$ZOXIDE_CACHE.XXXXXX"); then
            if zoxide init zsh > "$tmp"; then
                mv "$tmp" "$ZOXIDE_CACHE"
            else
                rm -f "$tmp"
            fi
            unset tmp
        fi
    fi
    if [[ -s "$ZOXIDE_CACHE" ]]; then
        source "$ZOXIDE_CACHE"
    fi
fi

if (( $+commands[atuin] )); then
    # Atuin: fuzzy searchable history, bound to Up and Ctrl-R.
    #
    # --disable-ai because Atuin 18.23 binds `?` at an empty prompt to its AI
    # TUI; a bare question mark should be a question mark.
    #
    # Cached like zoxide, but also regenerated when the flags change: the first
    # line of the cache records them, so a flag added here cannot leave an old
    # init behind.
    atuin_flags=(--disable-ai)
    atuin_header="# anixie: atuin init zsh ${atuin_flags[*]}"
    ATUIN_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/atuin.zsh"
    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"

    regen=0
    if [[ ! -s "$ATUIN_CACHE" || "$commands[atuin]" -nt "$ATUIN_CACHE" ]]; then
        regen=1
    elif [[ "$(head -n 1 "$ATUIN_CACHE")" != "$atuin_header" ]]; then
        regen=1
    fi

    if (( regen )); then
        if tmp=$(mktemp "$ATUIN_CACHE.XXXXXX"); then
            if {
                print -r -- "$atuin_header"
                atuin init zsh "${atuin_flags[@]}"
            } > "$tmp"; then
                mv "$tmp" "$ATUIN_CACHE"
            else
                rm -f "$tmp"
            fi
            unset tmp
        fi
    fi

    if [[ -s "$ATUIN_CACHE" ]]; then
        source "$ATUIN_CACHE"
    fi
    unset atuin_flags atuin_header ATUIN_CACHE regen
fi
