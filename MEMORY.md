# Project Memory

This file is a short handoff for future sessions. Formal documentation lives in `README.md`, `docs/`, and `runbooks/`.

## Working Rules

- The repo is the product.
- A VPS is only a disposable test bench.
- Manual VPS fixes are not enough. Important fixes must become repo code or docs.
- Do not run commands on macOS unless the user gives explicit green light.
- Never commit or record real secrets.

## Current Repo State

- Workspace: `/Users/amir/Desktop/sandbox/1UpMoodleServe`
- GitHub repo: `https://github.com/amirahkami/1UpMoodleServe`
- Development branch: `dev`
- Deployment branch policy: `main` is for deployment
- Latest known local commit before doc cleanup: `f8c0f6f Add fresh VPS install orchestrator`

## Product Goal

Deploy a full Moodle platform from a fresh Ubuntu 24.04 VPS:

- Docker Engine and Docker Compose
- hardened SSH and firewall
- PostgreSQL
- Moodle
- Keycloak
- Nginx
- Let's Encrypt HTTPS
- Keycloak realm/users
- Moodle OIDC login

## Current Implementation

- `scripts/install-fresh.sh` coordinates fresh VPS setup.
- `scripts/provision.sh` installs Docker and host dependencies.
- `scripts/harden.sh` handles SSH and system hardening.
- `scripts/deploy.sh` builds and starts the Compose stack.
- `scripts/https.sh` issues/renews Let's Encrypt certificates.
- `scripts/keycloak-realm.sh` applies Keycloak desired state.
- `scripts/verify-keycloak-realm.sh` verifies Keycloak state.
- `scripts/moodle-oidc.sh` applies/verifies Moodle OIDC.
- `scripts/verify-server.sh` verifies host and Compose state.

## Desired State

- Keycloak realm file: `data/keycloak-realm.json`
- Keycloak users file: `data/keycloak-users.json`
- Moodle OIDC file: `data/moodle-oidc.json`
- Realm: `unrealuni`
- Keycloak client: `moodle`
- Seeded users: 130
- Seed password pattern: `{username}@unrealuni`
- Example user: `sara.shirazi / sara.shirazi@unrealuni`

## Current Test VPS

- VPS IP: `138.68.64.183`
- Project path: `/opt/1upmoodleserve`
- SSH user: `underroot`
- SSH port: `44422`
- SSH is password-based.
- Current domains:
  - `unrealuni.xyz`
  - `moodle.unrealuni.xyz`
  - `iam.unrealuni.xyz`

This VPS is not the product and may be destroyed.

## Last Known Working VPS State

Confirmed before this cleanup:

- Docker Compose deploy completed.
- Moodle was reachable over HTTPS.
- Keycloak was reachable over HTTPS.
- HTTP redirected to HTTPS.
- Let's Encrypt certificate worked for both Moodle and Keycloak names.
- Keycloak realm `unrealuni` was applied from JSON.
- Forced Keycloak user reseed completed for 130 users.
- Keycloak verifier completed with `313 pass, 0 warn, 0 fail`.
- Moodle OIDC apply completed.
- Moodle OIDC verifier passed.
- Moodle login page showed `Log in with UnrealUni Login`.
- Moodle OAuth redirect returned HTTP 303 to Keycloak.
- Direct OIDC token test passed for `sara.shirazi`.
- Browser login into Moodle as `sara.shirazi` was confirmed.

## Important Fixes Already Captured In Repo

- Docker firewall forwarding fixed for nftables.
- Docker is restarted after nftables `flush ruleset`.
- `underroot` is added to the `docker` group when possible.
- `.env` placeholder checks ignore comments.
- PostgreSQL 18 volume mount uses `/var/lib/postgresql`.
- Moodle image includes required PHP PostgreSQL extensions.
- Moodle first install runs only when the database is empty.
- Moodle 5.2 is served from `/public`.
- Runtime mode is written to `.generated/deploy.env`, not `.env`.

## Known Gaps

- Fresh VPS end-to-end flow still needs a clean full test.
- `.env` is still manually created.
- Public DNS/HTTPS/OIDC flow needs one automated verifier.
- Policy is undecided for users removed from `data/keycloak-users.json`.
- Moodle test courses are not automated.
- In-house Moodle plugin install/config is not automated.
- Backup and restore are not implemented.
