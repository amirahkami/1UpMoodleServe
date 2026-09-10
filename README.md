# 1UpMoodleServe

Infrastructure-as-code style deployment kit for a small-university Moodle platform.

The repo is the product. A VPS is only a disposable target used to prove that this repo can deploy the full stack from zero.

## Target Result

- fresh Ubuntu 24.04 VPS
- hardened SSH and firewall
- Docker Engine and Docker Compose
- Moodle online over HTTPS
- Keycloak online over HTTPS
- PostgreSQL persistence
- Keycloak realm, roles, groups, users, and Moodle OIDC configured from repo state

## Stack

- Moodle 5.2
- PHP 8.3
- PostgreSQL 18
- Keycloak 26.7.2
- Nginx
- Certbot
- Docker Compose

## Default Domains

- Moodle: `moodle.unrealuni.xyz`
- Keycloak: `iam.unrealuni.xyz`

For another university or server, change the domain values in `.env`.

## Fresh VPS Flow

Root phase:

```bash
sudo bash scripts/install-fresh.sh root
```

Verify the new SSH user from another terminal:

```bash
ssh -p 44422 underroot@<server-ip>
```

Disable direct root SSH:

```bash
SERVER_HOST=<server-ip> sudo bash scripts/harden.sh ssh-step2
```

Application phase:

```bash
cd /opt/1upmoodleserve
bash scripts/install-fresh.sh app
```

Verification:

```bash
bash scripts/install-fresh.sh verify
sudo bash scripts/verify-server.sh
```

## Important Files

```text
data/        desired platform state
docker/      container images and service config
scripts/     automation
docs/        explanations
runbooks/    step-by-step operations
MEMORY.md    session handoff
```

## Desired State

Non-secret platform state is committed under `data/`:

```text
data/keycloak-realm.json
data/keycloak-users.json
data/moodle-oidc.json
```

Seeded user passwords use:

```text
{username}@unrealuni
```

Example:

```text
sara.shirazi / sara.shirazi@unrealuni
```

## Secrets

Real secrets must never be committed.

Use:

```text
.env.example  committed placeholders
.env          real VPS-only values
```

## Documentation

- [Project Scope](PROJECT.md)
- [Architecture](docs/architecture.md)
- [Tech Stack](docs/tech-stack.md)
- [Security Model](docs/security-model.md)
- [Desired State](docs/desired-state.md)
- [Fresh VPS Runbook](runbooks/fresh-vps.md)
- [Troubleshooting](runbooks/troubleshooting.md)

Read [MEMORY.md](MEMORY.md) before resuming work in a new session.
