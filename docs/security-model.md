# Security Model

## SSH

- Create a sudo user chosen by the admin.
- Move SSH from port `22` to the port chosen by the admin.
- Keep password SSH enabled by project decision.
- Disable direct root SSH only after the new SSH login is confirmed.
- Restrict SSH login to the chosen admin user.

SSH hardening is split into two steps to avoid lockout:

```bash
sudo bash scripts/harden.sh ssh-step1
ssh -p <ssh-port> <ssh-user>@<server-ip>
SERVER_HOST=<server-ip> sudo bash scripts/harden.sh ssh-step2
```

## Firewall

The project uses `nftables`, not UFW.

Inbound policy is default-deny.

Allowed inbound ports:

- chosen SSH port
- `80/tcp` for HTTP
- `443/tcp` for HTTPS

Outbound traffic is allowed.

## Docker Networking

Docker needs forwarding and NAT.

The firewall must allow Docker bridge/private-subnet forwarding. Without this, image builds and container egress can fail.

After nftables reloads with `flush ruleset`, Docker is restarted so Docker recreates its own bridge/NAT rules.

## Fail2ban

Fail2ban is required because password SSH remains enabled.

It protects SSH on the chosen SSH port.

## HTTPS

HTTPS uses Let's Encrypt through the Certbot container.

Cloudflare is DNS only during setup. It is not the primary certificate source.

## Secrets

Secrets live only in `.env` on the VPS.

Never commit:

- `.env`
- passwords
- API keys
- Moodle admin password
- Keycloak admin password
- database passwords
- Moodle plugin API token
