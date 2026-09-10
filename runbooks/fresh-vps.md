# Fresh VPS Deployment

This is the target reproducibility path for a new Ubuntu 24.04 VPS.

## Inputs

- Ubuntu 24.04 VPS
- DNS records point to the VPS IP
- Cloudflare records are DNS-only during setup
- repo is available on the VPS under `/opt/1upmoodleserve`
- real secrets are in `/opt/1upmoodleserve/.env`
- desired platform state is in `data/`

## Rule

If a manual step is needed, record it. If it matters, automate it in the repo.

## 1. Root Phase

Run from the repo on the VPS:

```bash
sudo bash scripts/install-fresh.sh root
```

This provisions the server, creates `underroot`, moves SSH to port `44422`, and applies base hardening.

## 2. Verify SSH

From a new terminal:

```bash
ssh -p 44422 underroot@<server-ip>
```

Do not continue until this works.

## 3. Disable Root SSH

```bash
SERVER_HOST=<server-ip> sudo bash scripts/harden.sh ssh-step2
```

## 4. Create `.env`

On the VPS:

```bash
cd /opt/1upmoodleserve
cp .env.example .env
chmod 600 .env
```

Fill all real values. Do not commit `.env`.

## 5. Application Phase

Run as `underroot` from `/opt/1upmoodleserve`:

```bash
bash scripts/install-fresh.sh app
```

This deploys the stack, issues HTTPS certificates, applies Keycloak state, and applies Moodle OIDC.

## 6. Verify

Run:

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
