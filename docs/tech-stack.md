# Tech Stack

Locked technical choices for this project.

## Target Environment

- Target machine: generic VPS / VM
- Example provider: DigitalOcean
- Operating system: Ubuntu Server 24.04 LTS
- Deployment scope: one university per VM
- Moodle scope: one Moodle instance per VM
- Deployment scope: one configured environment per VM

## Runtime Model

- Runtime: Docker Compose
- Services run on one VM.
- Services are separated into containers.
- Native install, Ansible, Podman, and Kubernetes are out of scope for now.

## Versions

- Moodle: 5.2
- Moodle branch: `MOODLE_502_STABLE`
- PHP: 8.3
- PostgreSQL: `postgres:18`
- Keycloak: `quay.io/keycloak/keycloak:26.7.2`
- Nginx: `nginx:1.27-alpine`
- Certbot: `certbot/certbot:v3.1.0`

## Core Services

- Moodle image: custom image built by this repo
- Moodle runtime: PHP-FPM
- Web entrypoint: Nginx
- Database: PostgreSQL
- Identity provider: Keycloak

## Container Layout

- `postgres`
- `keycloak`
- `moodle`
- `nginx`
- `certbot` profile container

## Database Layout

- One PostgreSQL container
- Separate PostgreSQL database and user for Moodle
- Separate PostgreSQL database and user for Keycloak
- PostgreSQL data persisted in Docker volume `postgres_data`

## Moodle Data

- Moodle data persisted in Docker volume `moodle_data`
- Moodle code persisted in Docker volume `moodle_code`
- Backup support is required later

## Domains And DNS

- DNS is managed through Cloudflare nameservers
- Moodle has its own subdomain
- Keycloak has its own subdomain
- HTTPS uses Let's Encrypt through Certbot

## Custom Moodle Plugin

- The project uses an in-house Moodle block plugin
- The plugin source is stored in a private GitHub repository
- The plugin sends Moodle data to an external university REST API
- Course data is included, and other request types may also be included
- Moodle initiates outbound requests to the external API
- The external API does not initiate callbacks to Moodle
- External API communication must use HTTPS
- Authentication is token-based using the `X-API-KEY` header
- The token is stored in the plugin configuration inside Moodle
- Plugin installation and configuration are not automated yet

## Test Courses

- Three Moodle courses are needed to test the in-house block plugin
- The block plugin must be added into courses for testing
- Course creation is not automated yet

## Local Machine Rule

- Do not run project deployment commands on macOS.
- The target is a Linux VPS.
- macOS is only the editing workstation unless the user gives explicit green light for a local command.
