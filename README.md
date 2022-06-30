# dotfiles

dotfiles for me.

## Install

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

```bash
brew install vim tmux git git-secrets ripgrep fzf asdf navi direnv ctags wget jq fd
```

```bash
cd
wget https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash -O ~/.git-completion.bash
wget https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh -O ~/.git-prompt.sh
$(brew --prefix)/opt/fzf/install
git secrets --register-aws --global
```

```bash
cd ~
git clone https://github.com/nirareba1969/dotfiles.git
bash dotfiles/setup.sh
```
