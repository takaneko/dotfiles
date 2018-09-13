[[ -s "$HOME/.bashrc" ]] && source "$HOME/.bashrc"

export PATH="$HOME/.anyenv/bin:$PATH"
eval "$(anyenv init -)"

export PATH="/usr/local/opt/file-formula/bin:$PATH"
