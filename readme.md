# 1UpMoodleServe

Production-oriented Moodle deployment kit for small universities.

The target is a fresh Ubuntu 24.04 VPS that can be repeatedly prepared and deployed with Docker Compose.

## Target Stack

- Moodle 5.2
- PHP 8.3
- PostgreSQL 18
- Keycloak 26.7.2
- Nginx as the only public web entrypoint
- Certbot container for Let's Encrypt certificates
- Docker Engine from Docker's official apt repository
- Docker Compose plugin
- Docker named volumes for persistent data

## Domains

- Moodle: `moodle.unrealuni.xyz`
- Keycloak: `iam.unrealuni.xyz`

Both records should point to the VPS and stay DNS-only in Cloudflare during setup.

## VPS Target

- OS: Ubuntu 24.04 LTS x64
- Project path on VPS: `/opt/1upmoodleserve`
- SSH user after hardening: `underroot`
- SSH port after hardening: `44422`

## Scripts

```bash
sudo bash scripts/provision.sh
sudo bash scripts/harden.sh ssh-step1
sudo bash scripts/harden.sh ssh-step2
sudo bash scripts/harden.sh system
bash scripts/deploy.sh
bash scripts/https.sh issue
```

`provision.sh` prepares the VPS for Docker-based deployment.

`harden.sh ssh-step1` creates/configures `underroot`, moves SSH to port `44422`, and keeps root SSH temporarily.

`harden.sh ssh-step2` disables direct root SSH only after `underroot` login has been confirmed.

`harden.sh system` applies firewall and baseline host security.

`deploy.sh` starts the HTTP bootstrap stack.

`https.sh issue` obtains the initial Let's Encrypt certificate and switches the stack to HTTPS.

## Secrets

Real secrets must never be committed.

Use:

```text
.env.example  committed placeholder values
.env          real VPS-only values
```

## Durable Context

Read `MEMORY.md` before resuming work in a new session.
