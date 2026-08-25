# Certbot

Certbot runs as a Docker Compose profile and uses the `certbot_conf` and `certbot_www` named volumes.

Initial certificate issuance will be wired into `scripts/deploy.sh` after the HTTP-only Nginx bootstrap config is validated on the VPS.
