# Project Scope

## Goal

Build a repeatable deployment repo for a production-grade Moodle platform.

The repo should make this possible:

1. Create a fresh Ubuntu VPS.
2. Clone this repo.
3. Fill real secrets in `.env`.
4. Run the documented scripts.
5. Get Moodle, Keycloak, PostgreSQL, HTTPS, and OIDC login working.

## Product Rule

The repo is the product.

The current VPS is only a test bench. Manual VPS fixes are not enough. If a fix matters, it must become code or documentation in this repo.

## Target Users

Small universities that need:

- Moodle online quickly
- identity management through Keycloak
- simple server hardening
- repeatable deployment
- a path for an in-house Moodle plugin

## In Scope

- Ubuntu 24.04 VPS provisioning
- Docker Engine and Docker Compose setup
- host hardening
- PostgreSQL container
- Moodle container
- Keycloak container
- Nginx reverse proxy
- Let's Encrypt HTTPS
- Keycloak realm/client/users from JSON
- Moodle OIDC configuration from JSON
- read-only verification scripts

## Later Scope

- automated Moodle test courses
- automated in-house Moodle plugin install
- plugin configuration
- backup and restore
- stronger end-to-end public verification

## Out Of Scope For Now

- Kubernetes
- Ansible
- native Moodle installation
- multi-server architecture
- local macOS deployment as the target
