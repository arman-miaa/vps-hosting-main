#!/bin/bash

# Update and upgrade system
sudo apt update && sudo apt upgrade -y

# Install necessary packages
sudo apt install -y build-essential curl file git zsh

# Install zsh and set it as default shell
sudo chsh -s $(which zsh)

# Install Oh My Zsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Clone zsh-autosuggestions plugin
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# Clone zsh-syntax-highlighting plugin
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Add plugins to ~/.zshrc
plugins_to_add=(git zsh-autosuggestions zsh-syntax-highlighting nvm jsontools dirhistory history colored-man-pages)

# Ensure ~/.zshrc exists
touch ~/.zshrc

# Add plugins to ~/.zshrc if they are not already present
for plugin in "${plugins_to_add[@]}"; do
    if ! grep -q "^plugins=.*$plugin.*" ~/.zshrc; then
        sed -i "s/^plugins=(/plugins=($plugin /" ~/.zshrc
    fi
done

# Install NVM (Node Version Manager)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Configure NVM
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

# Setup NodeJs
nvm install --lts


# PM2 && PNPM Installation
npm i -g pm2 bun pnpm

# Version Checking NodeJs
echo "Node Version"
node -v

# Print versions and information
echo "Zsh version:"
zsh --version

echo "Location of zsh:"
which zsh

echo "Details about zsh installation:"
whereis zsh

echo "Current default shell:"
echo $SHELL

# Source .zshrc to apply changes
source ~/.zshrc

# Done
echo "Setup completed."