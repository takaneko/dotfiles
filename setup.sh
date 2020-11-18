#!/bin/bash

DOT_FILES=( .vimrc .tmux.conf .bash_aliases .bash_profile .bashrc .gemrc .ctags .gitignore_global)

for file in ${DOT_FILES[@]}
do
  ln -sf $HOME/dotfiles/$file $HOME/$file
done
