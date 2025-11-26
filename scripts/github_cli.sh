#!/usr/bin/env bash
set -euo pipefail

setup_github_cli() {
  if command -v gh >/dev/null 2>&1; then
    log "GitHub CLI already installed."
    return
  fi

  install_package wget

  log "Configuring GitHub CLI apt repository..."
  $SUDO mkdir -p -m 755 /etc/apt/keyrings
  local tmp_key
  tmp_key=$(mktemp)
  wget -nv -O"$tmp_key" https://cli.github.com/packages/githubcli-archive-keyring.gpg
  cat "$tmp_key" | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  rm -f "$tmp_key"

  $SUDO mkdir -p -m 755 /etc/apt/sources.list.d
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null

  log "Installing GitHub CLI..."
  $SUDO apt update
  $SUDO apt install -y gh
}
