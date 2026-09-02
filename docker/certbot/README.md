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

The initial issue command generates HTTP Nginx config for ACME validation, then switches `.env` to the generated HTTPS config directory and sets `MOODLE_WWWROOT=https://<MOODLE_DOMAIN>`.
