function share_history {
  history -a
  history -c
  history -r
}
PROMPT_COMMAND='share_history'
shopt -u histappend

source ~/.git-prompt.sh
PS1='[\u@\h \W$(__git_ps1 " (%s)")]\$ '

export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
export JAVA_HOME=`/usr/libexec/java_home -v 1.8`

source /Users/takaneko/.phpbrew/bashrc

export PATH=/usr/local/opt/imagemagick@6/bin:/usr/local/opt/mysql@5.7/bin:${PATH}
export DYLD_LIBRARY_PATH=/usr/local/opt/mysql@5.7/:${DYLD_LIBRARY_PATH}
