#!/usr/bin/env bash
# Deploy or update the 1UpMoodleServe Docker Compose stack.

set -euo pipefail

APP_DIR="${APP_DIR:-/opt/1upmoodleserve}"
ENV_FILE="${ENV_FILE:-.env}"
GENERATED_HTTP_CONF_DIR="./.generated/nginx/http.d"
GENERATED_HTTPS_CONF_DIR="./.generated/nginx/https.d"

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

env_get() {
    local key="$1"
    local default="${2:-}"
    local value

    value="$(awk -F= -v key="${key}" '$1 == key { sub(/^[^=]*=/, ""); print; found=1 } END { if (!found) exit 1 }' "${ENV_FILE}" 2>/dev/null || true)"
    value="${value%\"}"
    value="${value#\"}"

    if [[ -z "${value}" ]]; then
        printf '%s\n' "${default}"
    else
        printf '%s\n' "${value}"
    fi
}

env_set() {
    local key="$1"
    local value="$2"
    local tmp

    tmp="$(mktemp)"
    awk -v key="${key}" -v value="${value}" '
        BEGIN { done=0 }
        $0 ~ "^" key "=" {
            if (!done) {
                print key "=" value
                done=1
            }
            next
        }
        { print }
        END {
            if (!done) {
                print key "=" value
            }
        }
    ' "${ENV_FILE}" > "${tmp}"
    mv "${tmp}" "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
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

configure_nginx() {
    section "Generate Nginx configuration"

    local conf_dir
    local mode
    conf_dir="$(env_get NGINX_CONF_DIR "${GENERATED_HTTP_CONF_DIR}")"

    case "${conf_dir}" in
        *https.d) mode="https" ;;
        *) mode="http" ;;
    esac

    bash scripts/nginx-config.sh generate "${mode}"

    if [[ "${mode}" == "https" ]]; then
        env_set NGINX_CONF_DIR "${GENERATED_HTTPS_CONF_DIR}"
    else
        env_set NGINX_CONF_DIR "${GENERATED_HTTP_CONF_DIR}"
    fi

    ok "Nginx ${mode} configuration is selected."
}

build_images() {
    section "Build application images"

    COMPOSE_PROGRESS=plain docker compose --env-file "${ENV_FILE}" build moodle

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

    local moodle_domain
    local keycloak_domain
    local moodle_wwwroot
    local keycloak_scheme
    moodle_domain="$(env_get MOODLE_DOMAIN)"
    keycloak_domain="$(env_get KEYCLOAK_DOMAIN)"
    moodle_wwwroot="$(env_get MOODLE_WWWROOT "http://${moodle_domain}")"
    keycloak_scheme="http"
    if [[ "${moodle_wwwroot}" == https://* ]]; then
        keycloak_scheme="https"
    fi

    echo ""
    info "Configured endpoints:"
    info "  ${moodle_wwwroot}"
    info "  ${keycloak_scheme}://${keycloak_domain}"
}

main() {
    require_repo_root
    warn_if_not_app_dir
    require_env_file
    require_commands
    configure_nginx
    compose_config
    build_images
    start_stack
    show_status
}

main "$@"
