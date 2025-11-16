#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[setup] $1"
}

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

log "Updating package repositories..."
$SUDO apt update

install_package() {
  local package="$1"
  if dpkg -s "$package" >/dev/null 2>&1; then
    log "$package is already installed."
  else
    log "Installing $package..."
    $SUDO apt install -y "$package"
  fi
}

install_package git

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

setup_docker

log "Enabling and starting Docker service..."
$SUDO systemctl enable docker >/dev/null
$SUDO systemctl start docker
$SUDO systemctl status docker --no-pager || true

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

ensure_ufw_rule() {
  local rule_cmd="$1"
  local pattern="$2"
  if $SUDO ufw status | grep -Fq "$pattern"; then
    log "UFW already has rule for $pattern."
  else
    log "Adding UFW rule: $rule_cmd"
    $SUDO ufw $rule_cmd
  fi
}

configure_firewall() {
  install_package ufw

  log "Configuring UFW defaults..."
  $SUDO ufw default deny incoming
  $SUDO ufw default allow outgoing

  ensure_ufw_rule "allow OpenSSH" "OpenSSH"
  ensure_ufw_rule "allow http" "80/tcp"
  ensure_ufw_rule "allow https" "443/tcp"

  if $SUDO ufw status | grep -iq "inactive"; then
    log "Enabling UFW firewall..."
    $SUDO ufw --force enable
  else
    log "UFW already active."
  fi
}

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

configure_nginx_reverse_proxy() {
  local domain="improvlib.com"
  local backend_port="8000"
  local container_name="improvlib_app"
  local site_available="/etc/nginx/sites-available/${domain}"
  local site_enabled="/etc/nginx/sites-enabled/${domain}"

  install_package nginx

  log "Writing Nginx config for ${domain}..."
  cat <<EOF | $SUDO tee "$site_available" >/dev/null
server {
  listen 80;
  listen [::]:80;
  server_name ${domain} www.${domain};

  location / {
    # Forward traffic to the improvlib_app Docker container published on localhost:${backend_port}
    proxy_pass http://127.0.0.1:${backend_port};
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
EOF

  if [ -e /etc/nginx/sites-enabled/default ]; then
    log "Disabling default Nginx site..."
    $SUDO rm -f /etc/nginx/sites-enabled/default
  fi

  if [ ! -L "$site_enabled" ]; then
    log "Enabling ${domain} site..."
    $SUDO ln -s "$site_available" "$site_enabled"
  else
    log "${domain} site already enabled."
  fi

  log "Checking Nginx configuration..."
  $SUDO nginx -t

  log "Ensuring Nginx is enabled and running..."
  $SUDO systemctl enable nginx >/dev/null
  if ! $SUDO systemctl reload nginx >/dev/null 2>&1; then
    $SUDO systemctl restart nginx
  fi

  log "Nginx now routes http(s) traffic for ${domain} to ${container_name} on port ${backend_port}."
}

setup_github_cli
configure_firewall
configure_nginx_reverse_proxy
harden_ssh

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

log "Setup complete."
