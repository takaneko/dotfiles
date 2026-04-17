#shellcheck disable=SC1090,SC1091

export PATH="/usr/local/sbin:/usr/local/google-cloud-sdk/bin:/opt/homebrew/bin:$PATH"

export PS1='\[\033[1;32m\]\u\[\033[00m\]:\[\033[1;34m\]\w\[\033[1;31m\]$(__git_ps1)\[\033[00m\] \$ '

export BASH_SILENCE_DEPRECATION_WARNING=1

function share_history {
  history -a
  history -c
  history -r
}
PROMPT_COMMAND='share_history'
shopt -u histappend

bind "\C-r":reverse-search-history

# homebrew
eval $(brew shellenv)

# aqua (PATH must be set before evals below that resolve direnv/navi binaries)
export AQUA_GLOBAL_CONFIG="$HOME/dotfiles/aqua.yaml"
AQUA_BIN="${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}/bin"
case ":$PATH:" in
  *":$AQUA_BIN:"*) ;;
  *) export PATH="$AQUA_BIN:$PATH" ;;
esac
unset AQUA_BIN

# git
source ~/.git-completion.bash
source ~/.git-prompt.sh

export GIT_PS1_SHOWDIRTYSTATE=1
export GIT_PS1_SHOWUPSTREAM=1
export GIT_PS1_SHOWUNTRACKEDFILES=
export GIT_PS1_SHOWSTASHSTATE=1

# fzf
[ -f ~/.fzf.bash ] && source ~/.fzf.bash

# mise
export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash --shims)"

# direnv
eval "$(direnv hook bash)"

# navi
eval "$(navi widget bash)"

export NAVI_PATH="$(navi info cheats-path)"
export NAVI_PATH="~/.cheats:.cheats:cheats:../.cheats:../cheats:$NAVI_PATH"

# 1password
[ -f ~/.config/op/plugins.sh ] && source ~/.config/op/plugins.sh

# pnpm
export PNPM_HOME="/Users/takaneko/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
