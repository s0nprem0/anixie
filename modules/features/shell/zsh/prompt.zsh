autoload -Uz colors vcs_info add-zsh-hook
zmodload zsh/datetime
colors

# Git configuration
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:*' check-for-changes true

zstyle ':vcs_info:git:*' unstagedstr '*'
zstyle ':vcs_info:git:*' stagedstr '+'

zstyle ':vcs_info:git:*' formats '(%b%c%u)'
zstyle ':vcs_info:git:*' actionformats '(%b|%a%c%u)'

# ---------- Command duration ----------
# Shows "(N.Ns)" in the right prompt when a command took >= 3s
typeset -g _PROMPT_CMD_START=''
typeset -g _PROMPT_DURATION_STR=''
_prompt_timer_preexec() {
    _PROMPT_CMD_START=$EPOCHREALTIME
}
_prompt_timer_precmd() {
    _PROMPT_DURATION_STR=''
    if [[ -n "$_PROMPT_CMD_START" ]]; then
        local elapsed=$(( EPOCHREALTIME - _PROMPT_CMD_START ))
        _PROMPT_CMD_START=''
        (( elapsed >= 3 )) && printf -v _PROMPT_DURATION_STR '(%.1fs) ' "$elapsed"
    fi
}

# ---------- Git info ----------
# Run vcs_info, throttled to once every 2 seconds per directory (git status
# on every keystroke stalls typing in large repos).
typeset -g _VCS_TTL=2
typeset -g _VCS_LAST_RUN=0
typeset -g _VCS_CACHED_DIR=''
_prompt_vcs_info() {
    local now=$EPOCHREALTIME
    if [[ "$PWD" == "$_VCS_CACHED_DIR" && $(( now - _VCS_LAST_RUN )) -lt $_VCS_TTL ]]; then
        return
    fi
    _VCS_LAST_RUN=$now
    _VCS_CACHED_DIR=$PWD
    vcs_info
}

add-zsh-hook preexec _prompt_timer_preexec
add-zsh-hook precmd _prompt_timer_precmd
add-zsh-hook precmd _prompt_vcs_info

PROMPT_ALTERNATIVE=twoline

configure_prompt() {
    local venv='${VIRTUAL_ENV:+(${VIRTUAL_ENV:t})}'

    case "$PROMPT_ALTERNATIVE" in
        twoline)
            PROMPT=$'%F{green}┌──'
            PROMPT+="$venv"
            PROMPT+=$'──(%B%F{blue}%n@%m%b%f)-[%B%4~%b]\n'
            PROMPT+=$'└─%F{red}%(?..✗ %? )%f'
            PROMPT+=$'%(#.%B%F{red}#%b.%F{blue}$)%f '
            RPROMPT='%F{yellow}${_PROMPT_DURATION_STR}%f%F{cyan}${vcs_info_msg_0_}%f'
            ;;
        oneline)
            PROMPT="$venv"
            PROMPT+=$'%B%F{blue}%n@%m%b%f:'
            PROMPT+=$'%B%F{green}%4~%b%f '
            PROMPT+=$'%F{red}%(?..✗ %? )%f'
            PROMPT+=$'%(#.%B%F{red}#%b.%F{blue}$)%f '
            RPROMPT='%F{yellow}${_PROMPT_DURATION_STR}%f%F{cyan}${vcs_info_msg_0_}%f'
            ;;
    esac
}

toggle_oneline_prompt() {
    if [[ "$PROMPT_ALTERNATIVE" == oneline ]]; then
        PROMPT_ALTERNATIVE=twoline
    else
        PROMPT_ALTERNATIVE=oneline
    fi

    configure_prompt
    zle reset-prompt
}

zle -N toggle_oneline_prompt
bindkey '^[p' toggle_oneline_prompt

configure_prompt