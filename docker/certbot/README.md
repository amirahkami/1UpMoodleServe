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

The initial issue command temporarily uses the HTTP Nginx config for ACME validation, then switches `.env` to `NGINX_CONF_DIR=./docker/nginx/https.d` and `MOODLE_WWWROOT=https://moodle.unrealuni.xyz`.
