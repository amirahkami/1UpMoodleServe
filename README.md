# 1UpMoodleServe

Repeatable deployment repo for a small-university Moodle platform.

The repo is the product. A VPS is only a disposable target.

## Target Result

- Ubuntu 24.04 VPS
- Docker Compose stack
- Moodle over HTTPS
- Keycloak over HTTPS
- PostgreSQL persistence
- Keycloak realm, roles, groups, and 130 demo users
- Moodle login connected to Keycloak
- basic SSH/firewall hardening

## Main Workflow

On a fresh VPS:

```bash
apt update
apt install git -y
git clone https://github.com/<owner>/<repo>.git /opt/1upmoodleserve
cd /opt/1upmoodleserve
bash scripts/bootstrap.sh
```

The installer asks for:

- domain names
- VPS IP
- SSH user, port, and password
- Moodle local admin account
- Keycloak realm name
- demo-user temporary password
- Let's Encrypt email

The installer creates `.env` automatically.

## Public Data Policy

The public repo may contain:

- scripts
- Docker files
- safe examples
- fake demo users
- realm structure
- docs

The public repo must not contain:

- `.env`
- real passwords
- tokens
- private keys
- real VPS IPs
- local machine paths
- disposable VPS notes
- public working password rules

## Keycloak Users

The 130 users in `data/keycloak-users.json` are demo university users.

They are created during bootstrap.

They use one temporary password from `.env`:

```text
KEYCLOAK_SEED_USER_TEMP_PASSWORD
```

Keycloak forces password change on first login.

## Important Files

```text
data/        Keycloak and Moodle desired state
docker/      container images and service config
scripts/     automation
docs/        explanations
runbooks/    operations notes
.env.example safe public template
.env         private VPS config, never committed
```

## Docs

- [Project Scope](PROJECT.md)
- [Architecture](docs/architecture.md)
- [Tech Stack](docs/tech-stack.md)
- [Security Model](docs/security-model.md)
- [Desired State](docs/desired-state.md)
- [Fresh VPS Runbook](runbooks/fresh-vps.md)
- [Troubleshooting](runbooks/troubleshooting.md)
