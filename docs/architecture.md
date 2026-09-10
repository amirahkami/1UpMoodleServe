# Architecture

## Purpose

This repo deploys one Moodle platform for one university on one VPS.

The VPS is replaceable. The repo is the source of truth.

## Services

```text
Internet
  |
  v
Nginx
  |-- moodle.unrealuni.xyz -> Moodle PHP-FPM
  |-- iam.unrealuni.xyz    -> Keycloak

Moodle   -> PostgreSQL
Keycloak -> PostgreSQL
Certbot  -> Let's Encrypt certificates
```

## Public Entry Point

Only Nginx exposes public web ports:

- `80/tcp`
- `443/tcp`

Moodle, Keycloak, and PostgreSQL do not expose public host ports.

## Internal Network

Docker Compose creates internal service networking.

- Moodle talks to PostgreSQL through the Docker network.
- Keycloak talks to PostgreSQL through the Docker network.
- Nginx talks to Moodle and Keycloak through the Docker network.

## HTTPS

Certbot obtains one Let's Encrypt certificate for both names:

- `moodle.unrealuni.xyz`
- `iam.unrealuni.xyz`

Nginx serves HTTPS using that certificate.

## Moodle Login

Moodle keeps local admin login as a backup.

Normal users can log in through Keycloak using Moodle's built-in OAuth2 support.

## Persistence

Docker named volumes hold runtime data:

- `postgres_data`: PostgreSQL databases
- `moodle_data`: Moodle file data
- `moodle_code`: installed Moodle code
- `certbot_conf`: certificates
- `certbot_www`: HTTP challenge files

## Generated State

Generated files live under `.generated/`.

`.generated/deploy.env` records current runtime mode:

- HTTP bootstrap mode
- HTTPS final mode

This file contains no secrets.
