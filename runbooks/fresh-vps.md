# Fresh VPS Runbook

Target: Ubuntu 24.04 VPS.

## 1. Point DNS

In Cloudflare, point these records to the VPS IP:

```text
example.edu
moodle.example.edu
iam.example.edu
```

Use your real domain, not `example.edu`.

## 2. Clone Repo

SSH as root:

```bash
ssh root@<server-ip>
```

Then:

```bash
apt update
apt install git -y
git clone https://github.com/<owner>/<repo>.git /opt/1upmoodleserve
cd /opt/1upmoodleserve
```

## 3. Bootstrap

Run:

```bash
bash scripts/bootstrap.sh
```

The installer will:

- install required server packages
- install Docker
- ask setup questions
- create `.env`
- configure SSH user, port, and password
- ask you to test the new SSH login
- disable root SSH after confirmation
- deploy Moodle, Keycloak, PostgreSQL, Nginx, and HTTPS
- apply Keycloak users and Moodle OIDC
- apply Moodle site-admin role sync
- verify the platform

## 4. Final Check

Open:

```text
https://your-domain
https://moodle.your-domain
https://iam.your-domain
```

## Important

`.env` is private VPS config.

Never commit `.env`.
