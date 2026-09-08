# Certbot

Certbot runs as a Docker Compose profile and uses the `certbot_conf` and `certbot_www` named volumes.

Initial certificate issuance:

```bash
bash scripts/https.sh issue
```

Renewal check:

```bash
bash scripts/https.sh renew
```

The initial issue command generates HTTP Nginx config for ACME validation, then writes HTTPS runtime mode to `.generated/deploy.env`. It does not rewrite `.env`.
