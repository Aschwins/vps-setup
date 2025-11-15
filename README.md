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
- Hardens SSH by disabling root/password logins and enforcing keep-alive settings

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
settings with `sudo sshd -T`. Ensure you have an alternate console or active SSH
session before hardening SSH in case you need to revert.
