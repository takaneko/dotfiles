[[ -s "$HOME/.profile" ]] && source "$HOME/.profile" # Load the default .profile
[[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc" # Load .bashrc

#export PATH="$HOME/.anyenv/bin:$PATH"
#eval "$(anyenv init -)"
. $(brew --prefix asdf)/asdf.sh
. $(brew --prefix asdf)/etc/bash_completion.d/asdf.bash

export PATH="$HOME/.cargo/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="~/Library/Python/3.7/bin:$PATH"
#export PATH="$HOME/.tfenv/bin:$PATH"
export GOPATH=$HOME/go
export PATH="$PATH:$GOPATH/bin"

export JAVA_HOME=$(/usr/libexec/java_home)
export PATH=$PATH:$JAVA_HOME/bin

function share_history {
  history -a
  history -c
  history -r
}
PROMPT_COMMAND='share_history'
shopt -u histappend

bind \C-r:reverse-search-history

source $HOME/.git-completion.bash
source $HOME/.git-prompt.sh

GIT_PS1_SHOWDIRTYSTATE=1
GIT_PS1_SHOWUPSTREAM=1
GIT_PS1_SHOWUNTRACKEDFILES=
GIT_PS1_SHOWSTASHSTATE=1

export PS1='\[\033[1;32m\]\u\[\033[00m\]:\[\033[1;34m\]\w\[\033[1;31m\]$(__git_ps1)\[\033[00m\] \$ '
export XDG_CONFIG_HOME=$HOME/.config

export BASH_SILENCE_DEPRECATION_WARNING=1

# The next line updates PATH for the Google Cloud SDK.
#if [ -f '/Users/nirareba1969/Downloads/google-cloud-sdk/path.bash.inc' ]; then . '/Users/nirareba1969/Downloads/google-cloud-sdk/path.bash.inc'; fi

# The next line enables shell command completion for gcloud.
#if [ -f '/Users/nirareba1969/Downloads/google-cloud-sdk/completion.bash.inc' ]; then . '/Users/nirareba1969/Downloads/google-cloud-sdk/completion.bash.inc'; fi

# Added by serverless binary installer
export PATH="$HOME/.serverless/bin:$PATH"
