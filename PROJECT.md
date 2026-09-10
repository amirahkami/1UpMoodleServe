# Project Scope

## Goal

Build a public, repeatable deployment repo for a Moodle platform.

The repo should make this possible:

1. Create a fresh Ubuntu VPS.
2. Point DNS to the VPS.
3. Clone the public repo.
4. Run one bootstrap script.
5. Get Moodle, Keycloak, PostgreSQL, HTTPS, and OIDC login working.

## Product Rule

The repo is the product.

The VPS is only a test target. Important fixes must become code or docs in this repo.

## In Scope

- Ubuntu 24.04 VPS provisioning
- Docker Engine and Docker Compose setup
- host hardening
- PostgreSQL container
- Moodle container
- Keycloak container
- Nginx reverse proxy
- Let's Encrypt HTTPS
- interactive `.env` creation
- generated machine secrets
- Keycloak realm/client/groups/roles/users from JSON
- Moodle OIDC configuration from JSON
- verification scripts

## Out Of Scope For Now

- Cloudflare API automation
- Kubernetes
- Ansible
- native Moodle installation
- multi-server architecture
- macOS as deployment target
