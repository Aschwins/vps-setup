#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[setup] $1"
}

determine_sudo() {
  if [ "${EUID}" -eq 0 ]; then
    SUDO=""
  else
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      echo "Run this script as root or ensure sudo is installed." >&2
      exit 1
    fi
  fi
}

install_package() {
  local package="$1"
  if dpkg -s "$package" >/dev/null 2>&1; then
    log "$package is already installed."
  else
    log "Installing $package..."
    $SUDO apt install -y "$package"
  fi
}
