# Repository Guidelines

## Project Structure & Module Organization
The repo is intentionally lean: `setup.sh` in the root drives the entire provisioning workflow, while `README.md` documents the user-facing narrative. There are no nested modules or assets; all logic lives in Bash functions within `setup.sh`, and you should keep new helpers co-located there unless a feature clearly warrants a separate script (prefer `scripts/<name>.sh` for future additions).

## Development Workflow
Make changes directly in `setup.sh`, then re-run the script on a disposable Debian/Ubuntu VPS or LXD container to validate end-to-end behavior. Guard changes behind helper functions so they can be tested individually with targeted environment tweaks (e.g., `SKIP_DOCKER=1 sudo ./setup.sh` if you introduce optional flags).

## Build, Test, and Development Commands
- `chmod +x setup.sh`: ensure the script stays executable after edits.
- `bash -n setup.sh`: fast syntax verification.
- `shellcheck setup.sh`: lint for quoting, portability, and error handling issues.
- `sudo ./setup.sh`: run the full bootstrap; use `DRY_RUN=1` or similar env toggles if you add them.

## Coding Style & Naming Conventions
Stick to Bash with `set -euo pipefail` enabled. Indent with two spaces, keep functions named in `snake_case`, and log user-facing actions through the existing `log()` helper so output stays consistent. Prefer here-docs for config templates (as already used for SSH settings) and guard external calls with `command -v` checks before installing dependencies.

## Testing Guidelines
Unit-style tests are manual; rely on linting plus smoke runs on fresh VMs. Add temporary containers via `multipass` or `lxc launch ubuntu:22.04 <name>` to verify the Docker, UFW, and SSH branches. Document any new verification command in `README.md` to keep operators aligned. Do not ship changes that have not been exercised on at least one clean host.

## Commit & Pull Request Guidelines
Commits in this repo use short, imperative subjects (`fixed ssh hardening`, `using dockers official apt repo`). Follow that tone, reference issue IDs when relevant, and keep diffs tightly scoped. Pull requests should summarize the scenario being improved (e.g., “ensure gh installs on Jammy”), list manual test evidence (`shellcheck`, VPS run logs), and note any breaking changes such as required reboots or additional packages.

## Security & Configuration Tips
Always assume contributors are running this as root. When touching firewall, SSH, or package repositories, explain rollback steps and backup locations (e.g., `sshd_config.pre-vps-setup`). Default to least privilege, keep keys in `/etc/apt/keyrings`, and remind operators to re-login after group membership changes.
