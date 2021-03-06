#!/bin/bash

DOT_FILES=( .vimrc .tmux.conf .bash_aliases .bashrc .gemrc .ctags .gitignore_global)

for file in ${DOT_FILES[@]}
do
  ln -sf $HOME/dotfiles/$file $HOME/$file
done

[ ! -d ~/.vim/bundle ] && mkdir -p ~/.vim/bundle && git clone git://github.com/Shougo/neobundle.vim ~/.vim/bundle/neobundle.vim
