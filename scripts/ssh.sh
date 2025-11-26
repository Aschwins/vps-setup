#!/usr/bin/env bash
set -euo pipefail

harden_ssh() {
  local sshd_config="/etc/ssh/sshd_config"
  if [ ! -f "$sshd_config" ]; then
    log "sshd_config not found; skipping SSH hardening."
    return
  fi

  local include_dir="/etc/ssh/sshd_config.d"
  local custom_config="$include_dir/99-vps-setup.conf"

  if [ ! -f "${sshd_config}.pre-vps-setup" ]; then
    log "Backing up SSH configuration to ${sshd_config}.pre-vps-setup"
    $SUDO cp "$sshd_config" "${sshd_config}.pre-vps-setup"
  fi

  $SUDO mkdir -p "$include_dir"
  cat <<'EOF' | $SUDO tee "$custom_config" >/dev/null
PasswordAuthentication no
PermitRootLogin no
ChallengeResponseAuthentication no
X11Forwarding no
UsePAM yes
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

  log "Validating SSH configuration..."
  $SUDO sshd -t

  log "Reloading SSH daemon with hardened settings..."
  if ! $SUDO systemctl reload ssh >/dev/null 2>&1; then
    $SUDO systemctl restart ssh
  fi
}
