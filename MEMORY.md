# Project Memory

## Current Purpose

This project is for creating a production-oriented Moodle server deployment for small universities. The target is a smooth, repeatable setup that can bring Moodle online on a VPS or equivalent virtual machine within minutes.

## Target Deployment

- Target host: generic VPS / VM, with DigitalOcean as an example provider.
- Operating system: Ubuntu Server 24.04 LTS.
- Deployment model: one university per VM.
- Moodle model: one Moodle instance per VM.
- Runtime: Docker Compose.
- Scope: production deployment, not a local development-only stack.

## Locked Technical Decisions

- Do not run project services directly on macOS.
- Project work should run through Docker / Docker Compose.
- Docker Desktop exists on the local macOS machine and the Docker daemon is expected to be running.
- First implementation uses Docker Compose, not Kubernetes, Podman, native installs, or Ansible.
- Moodle target version decision: Moodle 5.2.
- Moodle 5.2 is not an LTS release, but is preferred over Moodle 4.5 LTS because Moodle 4.5 is considered too old for this project.
- Moodle 5.2 requires PHP 8.3 and PostgreSQL 16 or newer; this project targets PostgreSQL 18.
- PostgreSQL target decision: `postgres:18`.
- Keycloak target decision: `quay.io/keycloak/keycloak:26.7.2`.
- Moodle should run through a custom production Docker image built by this project.
- Moodle runtime should be PHP-FPM.
- Web server should be Nginx.
- Database should be PostgreSQL.
- Identity provider should be Keycloak.
- DNS is managed through Cloudflare nameservers.
- Moodle and Keycloak should each have their own subdomain.

## Core Container Layout

The first milestone should start these services:

- PostgreSQL container.
- Keycloak container.
- Moodle PHP-FPM container.
- Nginx container.

## Database Layout

- One PostgreSQL server/container.
- Separate PostgreSQL database and user for Moodle.
- Separate PostgreSQL database and user for Keycloak.
- PostgreSQL data must be persisted in a Docker volume.

## Moodle Data

- Moodle data must be persisted in a Docker volume.
- Backup support is required later, but is not part of the first milestone.

## Custom Moodle Plugin

- The project uses an in-house Moodle block plugin.
- The plugin source is stored in a private GitHub repository.
- A GitHub token or another credential will be provided later for plugin access.
- The plugin sends Moodle data to an external university REST API.
- Moodle initiates outbound HTTPS requests to the external API.
- The external API does not initiate callbacks to Moodle.
- Authentication uses an `X-API-KEY` header.
- The API token is stored in the plugin configuration inside Moodle.
- Plugin installation/configuration automation is undecided.

## Test Courses

- Three Moodle courses are needed for plugin testing.
- The in-house block plugin must be added to courses for testing.
- Course creation may be manual or automated; this is undecided.

## Hardening

- A hardening script is required later.
- It should cover security and resilience basics.
- SSH should be moved away from port `22`.
- Firewall configuration is required.
- The exact ordering of hardening versus service deployment is undecided.

## First Milestone

Create the repo structure needed to start the core services with Docker Compose:

- `docker-compose.yml`.
- Moodle PHP-FPM Dockerfile and image files.
- Nginx configuration.
- PostgreSQL configuration / environment structure as needed.
- Keycloak service configuration.

Out of scope for the first milestone:

- Server hardening.
- Plugin automation.
- Course automation.
- Final execution order.
- Backup support.
- Final domain / HTTPS / reverse proxy strategy.

## Current Workspace State

As of 2026-08-25:

- Workspace path: `/Users/amir/Desktop/sandbox/1UpMoodleServe`.
- GitHub repository: `https://github.com/amirahkami/1UpMoodleServe`.
- GitHub repository visibility: public.
- Branch policy: `dev` is for development, `main` is for deployment.
- Current Git state: local `dev` branch exists and tracks `origin/dev`.
- Initial commit on `dev`: `0b90590 chore: initialize deployment project`.
- Existing durable context files: `PROJECT.md`, `techstack.md`, and this `MEMORY.md`.
- `readme.md` contains initial deployment documentation.
- `docs/` and `runbooks/` currently contain no files.
- The folder is a Git repository.

## VPS State

As of 2026-08-25:

- A fresh VPS has been created.
- VPS operating system: Ubuntu 24.04 LTS x64.
- VPS IP address: `138.68.64.183`.
- Initial login method: password-based SSH, not SSH key authentication.
- Confirmed SSH login works as `root`.
- Confirmed hostname from login banner: `moodle`.
- Confirmed detected OS from login banner: Ubuntu 24.04.4 LTS.
- Login banner reported 33 pending package updates, including 31 standard security updates.
- SSH password exists, but must not be stored in project files.
- Preferred deployment path: deploy and validate directly on the VPS, not through Docker Desktop on macOS.
- VPS project code path decision: `/opt/1upmoodleserve`.
- Important operating rule from the user: do not run commands or scripts on macOS without explicit green light.

## Domain Decision

- Registered domain: `unrealuni.xyz`.
- DNS is managed through Cloudflare.
- Moodle and Keycloak require separate subdomains.
- Moodle domain decision: `moodle.unrealuni.xyz`.
- Keycloak domain decision: `iam.unrealuni.xyz`.
- DNS records confirmed via `1.1.1.1`:
  - `unrealuni.xyz -> 138.68.64.183`.
  - `moodle.unrealuni.xyz -> 138.68.64.183`.
  - `iam.unrealuni.xyz -> 138.68.64.183`.
- Cloudflare records are set to DNS-only for setup.

## HTTPS Decision

- Use Let's Encrypt certificates on the VPS.
- Run Certbot as a Docker container.
- Nginx should serve Moodle and Keycloak over HTTPS.
- Cloudflare is used for DNS pointing to the VPS, not as the primary certificate strategy.
- Ports `80/tcp` and `443/tcp` must remain open for HTTP validation and HTTPS traffic.

## Reverse Proxy Decision

- Use Nginx as the only public web entrypoint.
- Public inbound HTTP/HTTPS traffic should terminate at Nginx.
- Nginx routes `moodle.unrealuni.xyz` to Moodle internally.
- Nginx routes `iam.unrealuni.xyz` to Keycloak internally.
- Moodle, Keycloak, and PostgreSQL should not expose public host ports directly unless a specific operational need appears.

## Environment / Secrets Decision

- Commit `.env.example` to GitHub with placeholder values only.
- Keep real `.env` only on the VPS.
- Never commit real passwords, API keys, Moodle admin credentials, Keycloak admin credentials, database passwords, or plugin API keys.

## Persistence Decision

- Use Docker named volumes for persistent service data.
- Initial named volumes should include PostgreSQL data and Moodle data.
- Avoid host bind-mounted service data for the first milestone unless a specific operational need appears.

## Docker Installation Decision

- Install Docker Engine from Docker's official apt repository.
- Install the Docker Compose plugin from Docker's official apt repository.
- Do not use Ubuntu's default `docker.io` package for this project.

## Firewall Decision

- Use `nftables`, not UFW.
- Firewall policy should be default-deny for inbound traffic.
- Required inbound ports:
  - `44422/tcp` for SSH.
  - `80/tcp` for HTTP.
  - `443/tcp` for HTTPS.
- Outbound traffic should be allowed.
- Because password-based SSH remains enabled, fail2ban is required.
- Docker bridge forwarding must be allowed in nftables. A default-drop forward chain without Docker bridge rules blocks Docker image builds and container network egress.

## SSH Policy Decision

- Create a dedicated sudo user: `underroot`.
- Keep password-based SSH authentication enabled.
- Change SSH from port `22` to port `44422`.
- Disable direct root SSH login after confirming `underroot` works.
- Restrict SSH login to `underroot`.
- Configure fail2ban for SSH on port `44422`.
- SSH hardening must be two-step to avoid lockout:
  - Step 1: create/configure `underroot`, set password, open/activate SSH on port `44422`.
  - Step 2: only after `ssh -p 44422 underroot@138.68.64.183` is confirmed working, disable direct root SSH.
- The `underroot` password must be a new strong password.
- The script must ask the user to confirm the password has been saved outside the repo before continuing toward root SSH disablement.

## Next Practical Step

Implement the first milestone by creating the Docker Compose service layout and minimal production-oriented configuration files for Moodle, Nginx, PostgreSQL, and Keycloak.

## Script Layout Decision

- Use fewer scripts with subcommands where needed.
- Planned scripts:
  - `scripts/provision.sh`: prepare fresh Ubuntu VPS for Docker-based deployment.
  - `scripts/harden.sh`: support subcommands such as `ssh-step1`, `ssh-step2`, and `system`.
  - `scripts/deploy.sh`: deploy/update the Docker Compose application stack.
  - `scripts/verify-server.sh`: read-only verification of host and deployment state.

## Implemented Files

- `scripts/provision.sh` has been created.
- Current `provision.sh` behavior:
  - Requires root.
  - Requires Ubuntu 24.04.
  - Updates system packages.
  - Installs base tools.
  - Removes conflicting Docker packages.
  - Configures Docker's official apt repository.
  - Installs Docker Engine, Buildx plugin, and Docker Compose plugin.
  - Enables and starts Docker.
  - Creates `/opt/1upmoodleserve`.
  - Verifies Docker and Docker Compose are available.
- `scripts/harden.sh` has been created.
- Current `harden.sh` subcommands:
  - `ssh-step1`: creates/configures `underroot`, prompts for a new password, requires saved-password confirmation, moves SSH to `44422`, keeps root SSH temporarily.
  - `ssh-step2`: requires confirmation that `underroot` login works, then disables direct root SSH and restricts SSH to `underroot`.
  - `system`: configures unattended security updates, sysctl hardening, `/dev/shm`, login banner, nftables, fail2ban, unused-service removal, and `su` restriction.
- Initial Docker Compose skeleton has been created:
  - `.env.example`.
  - `docker-compose.yml`.
  - Moodle PHP-FPM image scaffold under `docker/moodle/`.
  - Nginx HTTP bootstrap config under `docker/nginx/`.
  - PostgreSQL first-run database/user init script under `docker/postgres/init/`.
  - Certbot notes under `docker/certbot/`.
- `scripts/deploy.sh` has been created.
- Current `deploy.sh` behavior:
  - Requires project root.
  - Warns if not running from `/opt/1upmoodleserve`.
  - Requires `.env`.
  - Fails if `.env` contains `CHANGE_ME`.
  - Verifies Docker and Docker Compose are available.
  - Runs `docker compose --env-file .env config`.
  - Builds the Moodle image.
  - Starts the HTTP bootstrap stack: PostgreSQL, Keycloak, Moodle, and Nginx.
  - Prints `docker compose ps`.
  - Does not configure HTTPS yet.
- `scripts/verify-server.sh` has been created.
- Current `verify-server.sh` behavior:
  - Read-only server audit.
  - Checks Ubuntu version, DNS, project path, `.env`, Docker, Compose config/status, SSH policy, nftables/fail2ban, unattended upgrades, sysctl basics, and `/dev/shm`.

## VPS Execution Notes

- The VPS was provisioned with Docker Engine and Docker Compose from Docker's official apt repository.
- SSH hardening was applied:
  - `underroot` exists and has sudo access.
  - SSH listens on port `44422`.
  - Direct root SSH is disabled.
  - Password login remains enabled by project decision.
- System hardening was applied:
  - nftables default-deny inbound policy.
  - inbound ports `44422`, `80`, and `443` allowed.
  - fail2ban active for SSH.
  - unattended security upgrades configured.
  - `/dev/shm` hardened.
- Real `.env` exists only on the VPS at `/opt/1upmoodleserve/.env`; secrets must not be committed or written into memory.
- First deploy attempt reached Moodle image build but container package downloads could not reach Debian mirrors because nftables forward policy blocked Docker bridge traffic. The hardening script now includes Docker bridge forwarding rules.

## VPS Execution State

- The public GitHub repository `dev` branch has been cloned on the VPS to `/opt/1upmoodleserve`.
- Baseline `scripts/verify-server.sh` was run on the VPS before provisioning.
- Baseline result:
  - DNS passed for `unrealuni.xyz`, `moodle.unrealuni.xyz`, and `iam.unrealuni.xyz`.
  - Project path and `docker-compose.yml` exist on the VPS.
  - `.env` does not exist yet.
  - Docker is not installed yet.
  - SSH hardening has not run yet.
  - fail2ban is not installed yet.
  - nftables exists but project firewall rules are not configured yet.
- `scripts/provision.sh` has been run successfully on the VPS.
- Provisioning installed Docker Engine `29.7.2` and Docker Compose plugin `v5.5.0` from Docker's official apt repository.
- Post-provision `scripts/verify-server.sh` result: 12 pass, 10 warnings, 0 failures.
- Remaining post-provision warnings are expected before `.env` creation and hardening:
  - `.env` missing.
  - SSH hardening not run.
  - fail2ban not installed.
  - project nftables rules not configured.
  - `/dev/shm` not hardened yet.
- Docker set `net.ipv4.ip_forward = 1`; this is required for Docker container networking.
- `scripts/harden.sh` and `scripts/verify-server.sh` were adjusted to treat `net.ipv4.ip_forward = 1` as the correct Docker-host state.
- `scripts/harden.sh ssh-step1` has been run successfully on the VPS.
- SSH as `underroot` on port `44422` has been verified successfully.
- `scripts/harden.sh ssh-step2` has been run successfully on the VPS.
- Direct root SSH is disabled.
- SSH as `underroot` on port `44422` was re-verified after disabling root SSH.
- Root SSH on port `44422` was checked and denied as expected.
- `scripts/harden.sh system` has been run successfully on the VPS.
- SSH as `underroot` on port `44422` was re-verified after firewall hardening.
- Post-hardening `scripts/verify-server.sh` result: 25 pass, 2 warnings, 0 failures.
- Remaining post-hardening warnings are expected until `.env` is created and the Compose stack is deployed:
  - `.env` missing.
  - Compose check skipped because `.env` is missing.
- The VPS login banner reports that a system restart is required after package upgrades.
- `/opt/1upmoodleserve` ownership has been changed to `underroot:underroot` for future Git pull/deploy operations.
- `/opt/1upmoodleserve/.env` has been generated on the VPS with real secrets and file mode `600`.
- Real `.env` values must not be committed or stored in project memory.
- First verifier run after `.env` creation reported one failure because the placeholder check matched `CHANGE_ME` inside a comment.
- `scripts/deploy.sh` and `scripts/verify-server.sh` have been fixed so placeholder detection only checks active env assignment lines, not comments.
- The placeholder-check fix has been pulled on the VPS.
- Post-fix `scripts/verify-server.sh` result: 29 pass, 0 warnings, 0 failures.
- First `scripts/deploy.sh` attempt failed before containers started because `underroot` did not have permission to access `/var/run/docker.sock`.
- Fix needed: add `underroot` to the `docker` group and start a fresh SSH session before rerunning deploy.
- `scripts/deploy.sh` has been updated to check Docker daemon access before build/start.
- `scripts/harden.sh ssh-step1` has been updated to add `underroot` to the `docker` group when the group exists.
