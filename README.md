# dotfiles

dotfiles for me.

## Install

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Homebrew はアクア管理外のもの（tmux / fzf / git / wget / 言語ランタイム等）だけに絞る。CLI ツール本体は aqua 経由で入れる。

```bash
brew install tmux fzf git wget
```

mise は Homebrew ではなく公式インストーラで入れる（`~/.local/bin/mise` に入る）。

```bash
curl https://mise.run | sh
```

```bash
cd ~
git clone https://github.com/takaneko/dotfiles.git
bash dotfiles/setup.sh
bash dotfiles/scripts/bootstrap-aqua.sh
```

```bash
cd
wget https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash -O ~/.git-completion.bash
wget https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh -O ~/.git-prompt.sh
$(brew --prefix)/opt/fzf/install
git secrets --register-aws --global
```
