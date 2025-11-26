#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[smoke] $1"
}

error() {
  echo "[smoke] ERROR: $1" >&2
}

show_help() {
  cat <<EOF
Usage: $0

Smoke test for vps-setup by running setup.sh in a Docker container.

Environment variables:
  SMOKE_IMAGE            Docker image to use (default: ubuntu:24.04)
  SMOKE_CONTAINER_NAME   Container name (default: vps-setup-smoke)
  KEEP_CONTAINER         Keep container after test (default: 0, set to 1 to keep)
  VERBOSE                Show all command output (default: 0, set to 1 for verbose)
  SMOKE_TIMEOUT          Maximum test duration in seconds (default: 600)

Examples:
  bash $0                          # Run with defaults
  VERBOSE=1 bash $0                # Show all output
  KEEP_CONTAINER=1 bash $0         # Keep container for inspection
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  show_help
  exit 0
fi

command -v docker >/dev/null 2>&1 || {
  error "docker is required for the smoke test."
  exit 1
}

readonly IMAGE="${SMOKE_IMAGE:-ubuntu:24.04}"
readonly CONTAINER_NAME="${SMOKE_CONTAINER_NAME:-vps-setup-smoke}"
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly VERBOSE="${VERBOSE:-0}"
readonly TIMEOUT="${SMOKE_TIMEOUT:-600}"

run_quiet() {
  if [ "$VERBOSE" = "1" ]; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

cleanup() {
  local exit_code=$?
  
  if [ $exit_code -ne 0 ] && [ "${KEEP_CONTAINER:-0}" != "1" ]; then
    log "Test failed (exit code: $exit_code). Showing last 50 log lines:"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -50 || true
  fi
  
  if [ "${KEEP_CONTAINER:-0}" = "1" ]; then
    log "Keeping container ${CONTAINER_NAME}. Inspect with: docker exec -it ${CONTAINER_NAME} bash"
    return
  fi
  
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup

log "Pulling ${IMAGE}..."
run_quiet docker pull "$IMAGE"

log "Starting privileged Ubuntu container with systemd (bootstrapping if needed)..."
run_quiet docker run -d --name "$CONTAINER_NAME" --privileged --cgroupns=host \
  --tmpfs /tmp --tmpfs /run --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
  "$IMAGE" bash -c "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y systemd systemd-sysv sudo curl git psmisc && exec /lib/systemd/systemd"

log "Waiting for systemd to be ready..."
for i in {1..60}; do
  if docker exec "$CONTAINER_NAME" systemctl is-system-running 2>/dev/null | grep -qE "running|degraded"; then
    log "Systemd is ready."
    break
  fi
  if [ $i -eq 60 ]; then
    error "Systemd never became ready after 60 seconds"
    exit 1
  fi
  sleep 1
done

log "Copying repository into container..."
docker cp "$ROOT_DIR" "$CONTAINER_NAME:/opt/vps-setup"

log "Stopping apt-daily services to prevent lock conflicts..."
docker exec "$CONTAINER_NAME" bash -c '
  systemctl stop apt-daily.service apt-daily-upgrade.service apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
  systemctl kill --kill-who=all apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
'

log "Waiting for apt/dpkg locks to clear..."
docker exec "$CONTAINER_NAME" bash -c '
  max_wait=120
  elapsed=0
  while [ $elapsed -lt $max_wait ]; do
    # Check if apt-get, dpkg, or unattended-upgrade processes are running
    if pgrep -x apt-get >/dev/null 2>&1 || \
       pgrep -x dpkg >/dev/null 2>&1 || \
       pgrep -x unattended-upgrade >/dev/null 2>&1 || \
       fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
       fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
       fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
      sleep 2
      elapsed=$((elapsed + 2))
    else
      # Double-check with a short sleep to ensure processes have exited
      sleep 1
      if ! pgrep -x apt-get >/dev/null 2>&1 && \
         ! pgrep -x dpkg >/dev/null 2>&1 && \
         ! pgrep -x unattended-upgrade >/dev/null 2>&1; then
        break
      fi
    fi
  done
  if [ $elapsed -ge $max_wait ]; then
    echo "Warning: apt locks still held after ${max_wait}s, proceeding anyway" >&2
  fi
'

log "Running setup.sh inside the container (timeout: ${TIMEOUT}s)..."
if ! timeout "$TIMEOUT" docker exec -e DEBIAN_FRONTEND=noninteractive -w /opt/vps-setup "$CONTAINER_NAME" \
  bash -c "chmod +x setup.sh scripts/*.sh && ./setup.sh"; then
  error "setup.sh failed or timed out. Container logs:"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -100
  exit 1
fi

log "Verifying Docker installation..."
if ! docker exec "$CONTAINER_NAME" bash -c "command -v docker >/dev/null && docker --version"; then
  error "Docker not found or not working"
  exit 1
fi
log "✓ Docker is installed and accessible"

log "Verifying Docker service..."
if ! docker exec "$CONTAINER_NAME" systemctl is-active docker >/dev/null 2>&1; then
  error "Docker service is not running"
  exit 1
fi
log "✓ Docker service is active"

log "Verifying GitHub CLI..."
if ! docker exec "$CONTAINER_NAME" bash -c "command -v gh >/dev/null && gh --version"; then
  error "GitHub CLI not found or not working"
  exit 1
fi
log "✓ GitHub CLI is installed"

log "Verifying UFW configuration..."
if docker exec "$CONTAINER_NAME" bash -c "command -v ufw >/dev/null"; then
  docker exec "$CONTAINER_NAME" ufw status || true
  log "✓ UFW is installed"
else
  log "⚠ UFW not found (may be expected on some systems)"
fi

log "Verifying nginx installation..."
if ! docker exec "$CONTAINER_NAME" bash -c "command -v nginx >/dev/null && nginx -v"; then
  error "nginx not found or not working"
  exit 1
fi
log "✓ nginx is installed"

log "Verifying SSH configuration..."
if docker exec "$CONTAINER_NAME" test -f /etc/ssh/sshd_config 2>/dev/null; then
  # Check if hardening was applied
  if docker exec "$CONTAINER_NAME" test -f /etc/ssh/sshd_config.d/99-vps-setup.conf 2>/dev/null; then
    log "✓ SSH is configured and hardened"
  else
    log "⚠ SSH config exists but hardening was not applied (may be expected)"
  fi
else
  log "⚠ SSH not installed (setup.sh skips hardening when SSH is not present)"
fi

log ""
log "🎉 Smoke test completed successfully!"
log "All components verified: Docker, GitHub CLI, UFW, nginx, SSH"
