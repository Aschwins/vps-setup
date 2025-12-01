#!/usr/bin/env bash
set -euo pipefail

configure_nginx_reverse_proxy() {
  local domain="${NGINX_DOMAIN:-improvlib.com}"
  local backend_port="${NGINX_BACKEND_PORT:-8000}"
  local container_name="${NGINX_CONTAINER_NAME:-improvlib_app}"
  local media_path="${NGINX_MEDIA_PATH:-/var/www/${domain}/media}"
  local acme_root="/var/www/${domain}/.well-known/acme-challenge"
  local site_available="/etc/nginx/sites-available/${domain}"
  local site_enabled="/etc/nginx/sites-enabled/${domain}"
  local cert_path="/etc/letsencrypt/live/${domain}/fullchain.pem"
  local privkey_path="/etc/letsencrypt/live/${domain}/privkey.pem"
  local ssl_options="/etc/letsencrypt/options-ssl-nginx.conf"
  local ssl_dhparam="/etc/letsencrypt/ssl-dhparams.pem"
  local has_cert=0

  install_package nginx

  log "Ensuring media directory exists at ${media_path} for Nginx alias..."
  $SUDO mkdir -p "$media_path"
  log "Ensuring ACME challenge directory exists at ${acme_root}..."
  $SUDO mkdir -p "$acme_root"

  if [ -f "$cert_path" ] && [ -f "$privkey_path" ]; then
    has_cert=1
    log "Found existing certificate for ${domain}; rendering HTTPS-enabled Nginx config."
  else
    log "No certificate detected for ${domain}; rendering HTTP-only Nginx config."
  fi

  log "Writing Nginx config for ${domain}..."
  if [ "$has_cert" -eq 1 ]; then
    cat <<EOF | $SUDO tee "$site_available" >/dev/null
server {
  listen 80;
  listen [::]:80;
  server_name ${domain} www.${domain};

  location /.well-known/acme-challenge/ {
    # Serve ACME challenges without redirecting.
    alias ${acme_root%/}/;
    try_files \$uri =404;
  }

  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name ${domain} www.${domain};

  ssl_certificate ${cert_path};
  ssl_certificate_key ${privkey_path};
  include ${ssl_options};
  ssl_dhparam ${ssl_dhparam};

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

  location /media/ {
    # Serve user-uploaded media files from the host filesystem shared with the app container.
    alias ${media_path%/}/;
    try_files \$uri \$uri/ =404;
    access_log off;
    add_header Cache-Control "private, no-store";
  }

  location /.well-known/acme-challenge/ {
    # Allow certbot renewals via HTTP-01 without changing config.
    alias ${acme_root%/}/;
    try_files \$uri =404;
  }
}
EOF
  else
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

  location /media/ {
    # Serve user-uploaded media files from the host filesystem shared with the app container.
    alias ${media_path%/}/;
    try_files \$uri \$uri/ =404;
    access_log off;
    add_header Cache-Control "private, no-store";
  }

  location /.well-known/acme-challenge/ {
    # Allow certbot HTTP-01 challenges before HTTPS is provisioned.
    alias ${acme_root%/}/;
    try_files \$uri =404;
  }
}
EOF
  fi

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

provision_https_certificate() {
  local domain="${NGINX_DOMAIN:-improvlib.com}"
  local email="${CERTBOT_EMAIL:-aschwin.schilperoort@gmail.com}"
  local cert_path="/etc/letsencrypt/live/${domain}/fullchain.pem"
  local provisioning_ran=0

  if [ "${SKIP_CERTBOT:-0}" != "0" ]; then
    log "SKIP_CERTBOT set; skipping HTTPS provisioning for ${domain}."
    return
  fi

  if [ -z "$email" ]; then
    log "CERTBOT_EMAIL not set; skipping automatic certificate request for ${domain}."
    return
  fi

  install_package certbot
  install_package python3-certbot-nginx

  if [ -f "$cert_path" ]; then
    log "Certificate for ${domain} already exists; running renewal dry run..."
    $SUDO certbot renew --dry-run
  else
    log "Requesting Let's Encrypt certificate for ${domain}..."
    $SUDO certbot --nginx --non-interactive --agree-tos --email "$email" -d "$domain" -d "www.${domain}" --redirect
    provisioning_ran=1
  fi

  if command -v systemctl >/dev/null 2>&1; then
    if $SUDO systemctl list-timers --all 2>/dev/null | grep -Fq certbot; then
      log "Certbot renewal timer detected."
    else
      log "Certbot renewal timer not found; verify certbot installation."
    fi
  else
    log "systemctl not available; verify certbot renewal scheduling manually."
  fi

  # Render HTTPS-enabled config after cert issuance to keep Nginx in sync even when certs pre-exist.
  if [ -f "$cert_path" ]; then
    if [ "$provisioning_ran" -eq 1 ]; then
      log "Re-rendering Nginx config now that certificate is issued..."
    else
      log "Refreshing Nginx config to ensure HTTPS blocks are present..."
    fi
    configure_nginx_reverse_proxy
  fi
}
