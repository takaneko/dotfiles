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

# git
source ~/.git-completion.bash
source ~/.git-prompt.sh

export GIT_PS1_SHOWDIRTYSTATE=1
export GIT_PS1_SHOWUPSTREAM=1
export GIT_PS1_SHOWUNTRACKEDFILES=
export GIT_PS1_SHOWSTASHSTATE=1

# fzf
[ -f ~/.fzf.bash ] && source ~/.fzf.bash

# mise または asdf のどちらかを有効にする
if [ "$USE_MISE" = "true" ]; then
    # mise の設定
    export PATH="$HOME/.local/share/mise/shims:$PATH"
    eval "$(mise activate bash --shims)"
else
    # asdf の設定
    export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
    . <(asdf completion bash)
fi

# direnv
eval "$(direnv hook bash)"

# navi
eval "$(navi widget bash)"

export NAVI_PATH="$(navi info cheats-path)"
export NAVI_PATH="~/.cheats:.cheats:cheats:../.cheats:../cheats:$NAVI_PATH"
