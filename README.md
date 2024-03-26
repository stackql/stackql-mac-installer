# stackql-mac-installer

Creates a multi arch (fat) `pkg` MacOS installer for [stackql](https://github.com/stackql/stackql), notarizes the package with Apple and staples the notarization ticket to the package.

## Prerequisites

Apple developer code signing certificates need to be installed in the key chain on the machine creating the installer

## Usage

```bash
DEV_TEAM=...
APP_SPECIFIC_PASSWORD=...
DEV_ACCOUNT=...
APP_SIGNATURE=...
INST_SIGNATURE=...
sh create-mac-installer.sh
```

### Prereq For Mac In Cloud (without admin priveleges)

```bash
mkdir $HOME/.homebrew && curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C $HOME/.homebrew
export PATH=$HOME/.homebrew/bin:$PATH
brew install jq
```