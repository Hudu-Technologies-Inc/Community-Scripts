#!/usr/bin/env bash
set -euo pipefail

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

if ! command -v brew >/dev/null 2>&1; then
  log "Homebrew not found. Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Load brew into this shell
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -x "$HOME/.linuxbrew/bin/brew" ]]; then
  eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
else
  echo "brew was not found after installation attempt." >&2
  exit 1
fi

log "Updating Homebrew metadata..."
brew update

log "Installing Python 3.14..."
brew install python@3.14

# Prefer the formula's unversioned shims in this shell
PY314_PREFIX="$(brew --prefix python@3.14)"
export PATH="$PY314_PREFIX/libexec/bin:$PATH"

log "Verifying installation..."
echo "brew:     $(brew --version | head -n1)"
echo "python:   $(python --version)"
echo "python3:  $(python3 --version)"
echo "pip:      $(pip --version)"
echo "pip3:     $(pip3 --version)"

cat <<EOF

Python 3.14 installed via Homebrew.

For future shells, add this to your shell profile:
  export PATH="$PY314_PREFIX/libexec/bin:\$PATH"

Examples:
  python --version
  python3.14 --version
  python -m venv .venv
EOF

python -m venv .venv
source ~/.venv/bin/activate
log "Virtual environment created at .venv"
python -m pip install --upgrade pip
log "pip upgraded in virtual environment"