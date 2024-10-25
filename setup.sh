#!/bin/bash

DOT_FILES=(.vimrc .tmux.conf .bash_aliases .bash_profile .bashrc .gemrc .ctags .gitignore_global)

for file in "${DOT_FILES[@]}"
do
  ln -sf "$HOME/dotfiles/$file" "$HOME/$file"
done

# ln -sf "$HOME/dotfiles/init.vim" "$HOME/.config/nvim/init.vim"
ln -sf "$HOME/dotfiles/init.lua" "$HOME/.config/nvim/init.lua"
ln -sf "$HOME/dotfiles/coc-settings.json" "$HOME/.config/nvim/coc-settings.json"
