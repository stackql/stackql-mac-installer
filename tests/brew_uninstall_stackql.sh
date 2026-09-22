#!/bin/bash

# Define the directory for Homebrew installation
BREW_HOME="$HOME/.homebrew"
BREW_BIN="$BREW_HOME/bin"
BREW_CELLAR="$BREW_HOME/Cellar"
BREW_REPO="$BREW_HOME/Homebrew"

# Export paths to use the local Homebrew
export PATH="$BREW_BIN:$PATH"

# Uninstall stackql using Homebrew
if command -v brew >/dev/null 2>&1; then
  echo "Uninstalling stackql..."
  brew uninstall stackql

  if [ $? -eq 0 ]; then
    echo "stackql uninstalled successfully."
  else
    echo "Failed to uninstall stackql or it may not be installed."
  fi
else
  echo "Homebrew not found. Please check your installation."
  exit 1
fi

# Optional: Remove the entire Homebrew installation
read -p "Do you want to remove the entire Homebrew installation? (y/n): " response
if [[ "$response" =~ ^[Yy]$ ]]; then
  echo "Removing Homebrew installation..."
  rm -rf "$BREW_HOME"
  if [ $? -eq 0 ]; then
    echo "Homebrew removed successfully."
  else
    echo "Failed to remove Homebrew."
  fi
else
  echo "Homebrew installation retained."
fi
