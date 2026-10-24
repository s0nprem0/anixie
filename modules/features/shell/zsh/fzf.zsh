# If fd is available use it (way faster than find); exclude heavy dirs so the
# picker does not walk caches or build trees.
typeset -ga _fzf_fd_excludes=(
  --exclude .git
  --exclude node_modules
  --exclude .cache
  --exclude .direnv
  --exclude .venv
  --exclude target
  --exclude result
)

if (( $+commands[fd] )); then
  export FZF_DEFAULT_COMMAND="fd --type f --hidden ${_fzf_fd_excludes[*]}"
else
  export FZF_DEFAULT_COMMAND='find . -type f'
fi

export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# No --prompt here: it applies to every fzf invocation, including history
# search and fzf-tab completion. The prompt belongs to the widget.
export FZF_DEFAULT_OPTS='
--height=60%
--layout=reverse
--border=rounded
--pointer=">"
--preview-window=right:65%:wrap:border-left
'

if (( $+commands[bat] )); then
  export FZF_PREVIEW='bat --color=always --style=plain,numbers --line-range=:500 -- {}'
else
  # No embedded double quotes: this string is spliced into FZF_CTRL_T_OPTS
  # inside another pair below.
  export FZF_PREVIEW='sed -n 1,500p {}'
fi

export FZF_CTRL_T_OPTS="--prompt='files > ' --preview \"$FZF_PREVIEW\""
export FZF_CTRL_R_OPTS="--prompt='history > '"
export FZF_ALT_C_OPTS="--prompt='dirs > '"

# Official key bindings (CTRL-T files, CTRL-R history, ALT-C dirs).
# bindings.zsh gives CTRL-R back to Atuin after this, since Atuin is the
# interactive history in this setup.
# fzf >= 0.48 ships them via --zsh; cached and regenerated whenever the
# binary is newer (post-upgrade).
if (( $+commands[fzf] )); then
  FZF_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/fzf.zsh"
  mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
  if [[ ! -s "$FZF_CACHE" || "$commands[fzf]" -nt "$FZF_CACHE" ]]; then
    fzf --zsh > "$FZF_CACHE"
  fi
  source "$FZF_CACHE"
fi

# Custom: insert a file at the cursor without hidden files
_fzf_file_no_hidden() {
  local result

  result=$(
    if (( $+commands[fd] )); then
      fd --type f "${_fzf_fd_excludes[@]}"
    else
      find . -type f
    fi |
    fzf --preview "$FZF_PREVIEW"
  ) || return

  [[ -n "$result" ]] || return
  LBUFFER+="${(q)result}"
  zle reset-prompt
}

zle -N _fzf_file_no_hidden
bindkey '^Xf' _fzf_file_no_hidden

# Palette-derived FZF/EZA/BAT colours, rewritten by `theme` on every switch.
theme_env="${XDG_STATE_HOME:-$HOME/.local/state}/anixie/theme/terminal.zsh"
if [[ -r "$theme_env" ]]; then
  source "$theme_env"
fi
