#!/bin/bash

set -euo pipefail

DOT_FILES=(.tmux.conf .bash_aliases .bash_profile .bashrc .gemrc .gitignore_global)

for file in "${DOT_FILES[@]}"
do
  ln -sf "$HOME/dotfiles/$file" "$HOME/$file"
done

ln -sf "$HOME/dotfiles/init.lua" "$HOME/.config/nvim/init.lua"
ln -sf "$HOME/dotfiles/lazy-lock.json" "$HOME/.config/nvim/lazy-lock.json"

mkdir -p "$HOME/.cheats"

if [ -d "$HOME/dotfiles/cheats" ]; then
  for file in "$HOME/dotfiles/cheats"/*; do
    if [ -f "$file" ]; then
      filename=$(basename "$file")
      ln -sf "$file" "$HOME/.cheats/$filename"
    fi
  done
fi
