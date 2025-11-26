#!/usr/bin/env bash
set -euo pipefail

setup_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed."
    return
  fi

  log "Preparing Docker apt repository..."
  install_package ca-certificates
  install_package curl
  $SUDO install -m 0755 -d /etc/apt/keyrings
  $SUDO curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  $SUDO chmod a+r /etc/apt/keyrings/docker.asc

  local codename
  codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
  cat <<EOF | $SUDO tee /etc/apt/sources.list.d/docker.sources >/dev/null
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  log "Installing Docker Engine packages..."
  $SUDO apt update
  $SUDO apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

ensure_docker_service() {
  log "Enabling and starting Docker service..."
  $SUDO systemctl enable docker >/dev/null
  $SUDO systemctl start docker
  $SUDO systemctl status docker --no-pager || true
}

ensure_user_in_docker_group() {
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    if id -nG "$SUDO_USER" | grep -qw docker; then
      log "$SUDO_USER already belongs to the docker group."
    else
      log "Adding $SUDO_USER to the docker group..."
      $SUDO usermod -aG docker "$SUDO_USER"
      log "User $SUDO_USER must log out and back in to use Docker without sudo."
    fi
  else
    log "Run this script via sudo to automatically add your user to the docker group."
  fi
}
