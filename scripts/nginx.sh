#!/usr/bin/env bash
set -euo pipefail

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
