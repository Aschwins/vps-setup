# vps-setup

Bootstrap a VPS with everything needed to start hosting apps. The included
`setup.sh` script installs Git and Docker with sensible defaults so a new
machine is ready to pull code and run containers within minutes.

## What the script does
- Updates apt package metadata
- Installs Git
- Installs Docker Engine from Docker's official apt repository (Engine, CLI, containerd, Buildx, Compose plugin)
- Enables and starts the Docker service
- Adds the invoking sudo user to the `docker` group (so Docker can run without sudo)
- Installs the GitHub CLI (`gh`) via the official apt repository
- Installs and enables UFW with sane defaults (deny incoming, allow outgoing) while allowing SSH/HTTP/HTTPS
- Installs Nginx and configures `improvlib.com` (and `www`) to proxy inbound HTTP traffic to the `improvlib_app` container published on localhost port `8000`
- Hardens SSH by installing a drop-in config (`/etc/ssh/sshd_config.d/99-vps-setup.conf`) that disables root/password logins and enforces keep-alive settings

## Requirements
- Debian/Ubuntu based distribution with `apt`
- Run as root or through `sudo`
- Network access to fetch the GitHub CLI repository key and package
- SSH key-based access already configured (password logins are disabled by the script)

## Usage
```bash
git clone https://github.com/<your-account>/vps-setup.git
cd vps-setup
chmod +x setup.sh   # one-time
sudo ./setup.sh
```

If your user was added to the `docker` group, log out and back in (or reboot) to
pick up the new permissions.

After the script finishes, run `gh auth login` to authenticate the GitHub CLI.

You can verify the firewall status with `sudo ufw status` and review SSH daemon
settings with `sudo sshd -T`. Check the reverse proxy setup with
`sudo nginx -t` and `systemctl status nginx` (or `curl -H "Host: improvlib.com" http://127.0.0.1`)
while the `improvlib_app` container publishes port `8000`. Ensure you have an
alternate console or active SSH session before hardening SSH in case you need to revert.

## Smoke test in Docker
Prereq: Docker available on your workstation. This starts a privileged Ubuntu
container with systemd to exercise `setup.sh` end-to-end.

```bash
./tests/smoke-test.sh
```

Run with `--help` to see all available environment variables. Useful options:
- `KEEP_CONTAINER=1` to leave the container running for inspection
- `VERBOSE=1` to show all command output
- `SMOKE_IMAGE=ubuntu:24.04` to test on a different base image
- `SMOKE_TIMEOUT=600` to adjust the maximum test duration
