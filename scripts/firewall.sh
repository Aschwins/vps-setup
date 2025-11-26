#!/usr/bin/env bash
set -euo pipefail

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

  # Try OpenSSH profile first, fall back to port 22 if profile doesn't exist
  if $SUDO ufw app list 2>/dev/null | grep -Fq "OpenSSH"; then
    ensure_ufw_rule "allow OpenSSH" "OpenSSH"
  else
    log "OpenSSH profile not found, using port 22 directly"
    ensure_ufw_rule "allow 22/tcp" "22/tcp"
  fi
  
  ensure_ufw_rule "allow http" "80/tcp"
  ensure_ufw_rule "allow https" "443/tcp"

  if $SUDO ufw status | grep -iq "inactive"; then
    log "Enabling UFW firewall..."
    $SUDO ufw --force enable
  else
    log "UFW already active."
  fi
}
