# Fresh VPS Deployment

This runbook is the target reproducibility path for a new Ubuntu 24.04 VPS.

## Inputs

- DNS records for root, Moodle, and Keycloak domains point to the VPS.
- Cloudflare records are DNS-only during setup.
- Project code is available on the VPS under `/opt/1upmoodleserve`.
- Real secrets exist only in `/opt/1upmoodleserve/.env`.
- Runtime deployment mode is generated in `/opt/1upmoodleserve/.generated/deploy.env`.
- Desired platform state comes from committed JSON files under `data/`.

## Flow

```bash
sudo bash scripts/provision.sh
sudo bash scripts/harden.sh ssh-step1
sudo bash scripts/harden.sh ssh-step2
sudo bash scripts/harden.sh system
bash scripts/deploy.sh
bash scripts/https.sh issue
bash scripts/deploy.sh
bash scripts/keycloak-realm.sh apply
bash scripts/verify-keycloak-realm.sh
bash scripts/moodle-oidc.sh apply
bash scripts/moodle-oidc.sh verify
```

## Expected Result

- Moodle is reachable over HTTPS.
- Keycloak is reachable over HTTPS.
- The Keycloak realm and Moodle client exist.
- Moodle shows the configured Keycloak OAuth2 login option.
- Local Moodle admin login remains available as a backup.
- Seeded users can log in with the deterministic password pattern from `data/keycloak-realm.json`.

## State Files

- `.env` is operator-owned input and must not be rewritten by deploy scripts.
- `.generated/deploy.env` is generated runtime state and may be rewritten by deploy scripts.
- `.generated/deploy.env` contains no secrets.
