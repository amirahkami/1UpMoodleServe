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

The fresh install is split into two phases because SSH/user hardening must be verified before direct root SSH is disabled.

Root phase, run from the repo on the VPS:

```bash
sudo bash scripts/install-fresh.sh root
```

Then verify password SSH from a new terminal:

```bash
ssh -p 44422 underroot@<server-ip>
```

After that, disable direct root SSH:

```bash
SERVER_HOST=<server-ip> sudo bash scripts/harden.sh ssh-step2
```

Application phase, run as the SSH/app user from `/opt/1upmoodleserve`:

```bash
bash scripts/install-fresh.sh app
```

Read-only verification can be rerun with:

```bash
bash scripts/install-fresh.sh verify
sudo bash scripts/verify-server.sh
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
