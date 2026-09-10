# Architecture

This repo deploys one Moodle platform for one university on one VPS.

The VPS is replaceable. The repo is the source of truth.

## Services

```text
Internet
  |
  v
Nginx
  |-- moodle.example.edu -> Moodle PHP-FPM
  |-- iam.example.edu    -> Keycloak

Moodle   -> PostgreSQL
Keycloak -> PostgreSQL
Certbot  -> Let's Encrypt certificates
```

The real domains are chosen during bootstrap and stored only in `.env`.

## Public Entry Point

Only Nginx exposes public web ports:

- `80/tcp`
- `443/tcp`

Moodle, Keycloak, and PostgreSQL stay inside Docker networks.

## HTTPS

Certbot obtains Let's Encrypt certificates for:

- Moodle domain
- Keycloak domain

Nginx serves HTTPS using those certificates.

## Login

Moodle keeps one local admin for bootstrap and emergency access.

Normal demo users log in through Keycloak.

## Persistence

Docker named volumes hold runtime data:

- `postgres_data`
- `moodle_data`
- `moodle_code`
- `certbot_conf`
- `certbot_www`

## Generated State

Generated files live under `.generated/`.

They are ignored by Git.
