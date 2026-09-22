#!/bin/bash

# Define the directory for Homebrew installation
BREW_HOME="$HOME/.homebrew"
BREW_BIN="$BREW_HOME/bin"
BREW_CELLAR="$BREW_HOME/Cellar"
BREW_REPO="$BREW_HOME/Homebrew"

# Create the necessary directories
mkdir -p "$BREW_HOME"
mkdir -p "$BREW_BIN"
mkdir -p "$BREW_CELLAR"

# Export paths to use the local Homebrew
export PATH="$BREW_BIN:$PATH"

# Install Homebrew in the specified directory
if [ ! -d "$BREW_REPO" ]; then
  echo "Installing Homebrew..."
  git clone https://github.com/Homebrew/brew "$BREW_REPO"
  ln -s "$BREW_REPO/bin/brew" "$BREW_BIN/brew"
  echo "Homebrew installed successfully."
else
  echo "Homebrew is already installed."
fi

# Set up the environment for Homebrew
export HOMEBREW_PREFIX="$BREW_HOME"
export HOMEBREW_CELLAR="$BREW_CELLAR"
export HOMEBREW_REPOSITORY="$BREW_REPO"
export PATH="$BREW_BIN:$HOMEBREW_PREFIX/sbin:$PATH"

# Check if brew works
if command -v brew >/dev/null 2>&1; then
  echo "Homebrew is ready to use."
else
  echo "Something went wrong with the Homebrew installation."
  exit 1
fi

# Install stackql using Homebrew
echo "Installing stackql..."
brew install stackql

if [ $? -eq 0 ]; then
  echo "stackql installed successfully."
else
  echo "Failed to install stackql."
fi
