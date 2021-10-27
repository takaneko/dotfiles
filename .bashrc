#shellcheck disable=SC1090,SC1091

export PATH="/usr/local/sbin:$PATH"

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

# git
source /usr/local/etc/bash_completion.d/git-completion.bash
source /usr/local/etc/bash_completion.d/git-prompt.sh

export GIT_PS1_SHOWDIRTYSTATE=1
export GIT_PS1_SHOWUPSTREAM=1
export GIT_PS1_SHOWUNTRACKEDFILES=
export GIT_PS1_SHOWSTASHSTATE=1

# fzf
[ -f ~/.fzf.bash ] && source ~/.fzf.bash

# asdf
source "$(brew --prefix asdf)"/asdf.sh
source "$(brew --prefix asdf)"/etc/bash_completion.d/asdf.bash

# direnv
eval "$(direnv hook bash)"

# navi
eval "$(navi widget bash)"

export NAVI_PATH="$(navi info cheats-path)"
export NAVI_PATH=".cheats:$NAVI_PATH"
