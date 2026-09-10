# Troubleshooting

Known problems from the first VPS test bench.

## Docker Cannot Download Packages

Symptom:

```text
container package downloads fail
```

Cause:

Firewall forwarding blocked Docker bridge traffic after nftables reload.

Fix now captured in repo:

- allow Docker bridge/private-subnet forwarding
- restart Docker after nftables `flush ruleset`

## Moodle Image Build Fails On mbstring

Symptom:

```text
mbstring extension fails to build
```

Cause:

Missing `libonig-dev`.

Fix now captured in repo:

- Moodle Dockerfile installs `libonig-dev`

## PostgreSQL 18 Fails On First Boot

Symptom:

```text
PostgreSQL container startup fails with data directory layout errors
```

Cause:

The volume was mounted at `/var/lib/postgresql/data`.

Fix now captured in repo:

- mount PostgreSQL volume at `/var/lib/postgresql`

## Moodle Public Directory

Symptom:

```text
Moodle web requests fail or serve wrong path
```

Cause:

Moodle 5.2 must be served from `/public`.

Fix now captured in repo:

- Nginx Moodle root is `/var/www/html/public`

## underroot Cannot Use Docker

Symptom:

```text
permission denied while trying to connect to Docker socket
```

Cause:

`underroot` was not in the `docker` group, or the SSH session was created before group membership changed.

Fix:

```bash
sudo usermod -aG docker underroot
```

Then log out and back in.

This is now handled by `scripts/harden.sh ssh-step1` when the Docker group exists.

## .env Placeholder False Positive

Symptom:

```text
.env still contains CHANGE_ME placeholders
```

Cause:

The check matched `CHANGE_ME` inside comments.

Fix now captured in repo:

- placeholder checks only inspect active env assignment lines

## SSH Blocked By Fail2ban

Symptom:

```text
SSH to port 44422 hangs or is refused from one IP
```

Possible cause:

The local IP was banned by fail2ban.

Recovery from VPS provider console:

```bash
sudo fail2ban-client set sshd unbanip <your-public-ip>
```

Optional:

Add a trusted IP to the fail2ban ignore list.
