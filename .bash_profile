[[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc" # Load .bashrc
[[ -s "$HOME/.profile" ]] && source "$HOME/.profile" # Load the default .profile

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/usr/local/google-cloud-sdk/path.bash.inc' ]; then . '/usr/local/google-cloud-sdk/path.bash.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/usr/local/google-cloud-sdk/completion.bash.inc' ]; then . '/usr/local/google-cloud-sdk/completion.bash.inc'; fi
