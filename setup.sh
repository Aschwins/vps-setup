#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/scripts/common.sh"
source "$SCRIPT_DIR/scripts/docker.sh"
source "$SCRIPT_DIR/scripts/github_cli.sh"
source "$SCRIPT_DIR/scripts/firewall.sh"
source "$SCRIPT_DIR/scripts/nginx.sh"
source "$SCRIPT_DIR/scripts/ssh.sh"

determine_sudo

log "Updating package repositories..."
$SUDO apt update

install_package git

setup_docker
ensure_docker_service
setup_github_cli
configure_firewall
configure_nginx_reverse_proxy
provision_https_certificate
harden_ssh
ensure_user_in_docker_group

log "Setup complete."
