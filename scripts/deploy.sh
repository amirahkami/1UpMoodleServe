#!/usr/bin/env bash
# Deploy or update the 1UpMoodleServe Docker Compose stack.

set -euo pipefail

APP_DIR="/opt/1upmoodleserve"
ENV_FILE=".env"

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    BOLD=''
    NC=''
fi

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; }
die() { fail "$*"; exit 1; }

section() {
    echo ""
    echo -e "${BOLD}${CYAN}==> $*${NC}"
}

require_repo_root() {
    [[ -f docker-compose.yml ]] || die "Run this script from the project root."
    [[ -d docker ]] || die "Missing docker/ directory. Run from the project root."
}

warn_if_not_app_dir() {
    local current_dir
    current_dir="$(pwd)"

    if [[ "${current_dir}" != "${APP_DIR}" ]]; then
        warn "Current directory is ${current_dir}, not ${APP_DIR}."
        warn "This is acceptable for development, but VPS deployment should run from ${APP_DIR}."
    fi
}

require_env_file() {
    section "Validate environment file"

    [[ -f "${ENV_FILE}" ]] || die "Missing ${ENV_FILE}. Copy .env.example to .env and fill real values on the VPS."

    if grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=.*CHANGE_ME' "${ENV_FILE}"; then
        die "${ENV_FILE} still contains CHANGE_ME placeholders."
    fi

    ok "${ENV_FILE} exists and contains no CHANGE_ME placeholders."
}

require_commands() {
    section "Validate required commands"

    command -v docker >/dev/null 2>&1 || die "docker command not found. Run scripts/provision.sh first."
    docker compose version >/dev/null 2>&1 || die "docker compose plugin not found. Run scripts/provision.sh first."
    docker info >/dev/null 2>&1 || die "Current user cannot access Docker. Add the user to the docker group, then log out and back in."

    ok "Docker available: $(docker --version)"
    ok "Compose available: $(docker compose version)"
}

compose_config() {
    section "Validate Docker Compose configuration"

    docker compose --env-file "${ENV_FILE}" config >/dev/null

    ok "Docker Compose configuration is valid."
}

build_images() {
    section "Build application images"

    docker compose --env-file "${ENV_FILE}" build moodle

    ok "Application images built."
}

start_stack() {
    section "Start HTTP bootstrap stack"

    docker compose --env-file "${ENV_FILE}" up -d postgres keycloak moodle nginx

    ok "Stack start requested."
}

show_status() {
    section "Service status"

    docker compose --env-file "${ENV_FILE}" ps

    echo ""
    info "HTTP bootstrap endpoints:"
    info "  http://moodle.unrealuni.xyz"
    info "  http://iam.unrealuni.xyz"
    warn "HTTPS is not configured by this script yet."
}

main() {
    require_repo_root
    warn_if_not_app_dir
    require_env_file
    require_commands
    compose_config
    build_images
    start_stack
    show_status
}

main "$@"
