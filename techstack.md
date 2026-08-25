# Tech Stack

This file records the technical decisions that are currently locked for the project.
Items marked as undecided will be resolved during implementation.

## Target Environment

- Target machine: generic Virtual Machine / VPS
- Example provider: DigitalOcean
- Operating system: Ubuntu Server 24.04 LTS
- Deployment scope: one university per VM
- Moodle scope: one Moodle instance per VM
- Environment scope: production only

## Runtime Model

- Runtime: Docker Compose
- Services run on a single VM due to resource constraints.
- Services should still be separated into containers so they can be moved apart later if needed.
- Native installation, Ansible, Podman, and Kubernetes are out of scope for the first implementation.

## Global Execution Rule

- Project commands must not be run directly on macOS.
- Project work should run through Docker / Docker Compose.
- Docker Desktop is already installed on macOS, and the Docker daemon is running.

## Core Services

- Moodle: Moodle LTS version
- Moodle image: custom production Docker image built by this project
- Moodle runtime: PHP-FPM
- Moodle web server: Nginx
- Database: PostgreSQL long-supported major version
- Identity provider: Keycloak stable supported version

## Container Layout

The first milestone should start these core services with Docker Compose:

- PostgreSQL container
- Keycloak container
- Moodle PHP-FPM container
- Nginx container

## Database Layout

- One PostgreSQL server/container
- Separate PostgreSQL database and user for Moodle
- Separate PostgreSQL database and user for Keycloak
- PostgreSQL data must be persisted in a Docker volume

## Moodle Data

- Moodle data must be persisted in a Docker volume
- Backup support is required later, but not part of the first milestone

## Domains And DNS

- DNS is managed through Cloudflare nameservers
- Moodle has its own subdomain
- Keycloak has its own subdomain
- HTTPS, reverse proxy strategy, and certificate handling are parked for later decision

## Custom Moodle Plugin

- The project uses an in-house Moodle block plugin
- The plugin source is stored in a private GitHub repository
- A GitHub token or similar credential will be provided later to access the plugin repository
- The plugin sends Moodle data to an external university REST API
- Course data is included, and other request types may also be included
- Moodle initiates outbound requests to the external API
- The external API does not initiate callbacks to Moodle
- External API communication must use HTTPS
- Authentication is token-based using the `X-API-KEY` header
- The token is stored in the plugin configuration inside Moodle
- Plugin installation and configuration may be automated or manual; this is undecided

## Test Courses

- Three Moodle courses are needed to test the in-house block plugin
- The block plugin must be added into courses for testing
- Whether courses are created manually or automatically is undecided

## Hardening

- A hardening script is required
- The hardening script is responsible for security and resilience basics
- SSH should be moved away from port `22` to reduce SSH noise
- Firewall configuration is required
- The exact execution order for hardening versus service deployment is undecided

## First Milestone

The first milestone is to create the repo structure needed to start the core services with Docker Compose on the provided VM:

- `docker-compose.yml`
- Moodle PHP-FPM Dockerfile and image files
- Nginx configuration
- PostgreSQL configuration / environment structure as needed
- Keycloak service configuration

Out of scope for the first milestone:

- hardening
- plugin automation
- course automation
- final execution order
- backup support
- domain / HTTPS finalization
