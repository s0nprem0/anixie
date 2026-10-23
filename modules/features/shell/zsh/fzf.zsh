# If fd is available use it (way faster than find); exclude heavy dirs
# to avoid freezing on large trees.
if (( $+commands[fd] )); then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git --exclude node_modules'
else
  export FZF_DEFAULT_COMMAND='find . -type f'
fi

export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

export FZF_DEFAULT_OPTS='
--height=60%
--layout=reverse
--border=rounded
--prompt="files > "
--pointer=">"
--preview-window=right:65%:wrap:border-left
'

if (( $+commands[bat] )); then
  export FZF_PREVIEW='bat --color=always --style=plain,numbers --line-range=:500 -- {}'
else
  export FZF_PREVIEW='sed -n "1,500p" {}'
fi

export FZF_CTRL_T_OPTS="--preview \"$FZF_PREVIEW\""

# Official key bindings (CTRL-T files, CTRL-R history, ALT-C dirs).
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
      fd --type f --exclude .git --exclude node_modules
    else
      find . -type f
    fi |
    fzf --preview "$FZF_PREVIEW"
  ) || return

  LBUFFER+="$result"
  zle reset-prompt
}

zle -N _fzf_file_no_hidden
bindkey '^[f' _fzf_file_no_hidden

# Palette-derived FZF/EZA/BAT colours, rewritten by `theme` on every switch.
theme_env="${XDG_STATE_HOME:-$HOME/.local/state}/anixie/theme/terminal.zsh"
if [[ -r "$theme_env" ]]; then
  source "$theme_env"
fi
