#!/usr/bin/env bash
# Manage Let's Encrypt certificates and HTTPS mode for 1UpMoodleServe.

set -euo pipefail

ENV_FILE=".env"
DEFAULT_CERT_NAME="1upmoodleserve"
HTTP_CONF_DIR="./docker/nginx/http.d"
HTTPS_CONF_DIR="./docker/nginx/https.d"

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

usage() {
    cat <<'EOF'
Usage:
  bash scripts/https.sh issue    Issue initial Let's Encrypt certs and enable HTTPS
  bash scripts/https.sh renew    Renew existing certs and reload Nginx
  bash scripts/https.sh status   Show Certbot certificate status

Run from the project root on the VPS after the HTTP bootstrap stack works.
EOF
}

require_repo_root() {
    [[ -f docker-compose.yml ]] || die "Run this script from the project root."
    [[ -d docker/nginx/http.d ]] || die "Missing docker/nginx/http.d."
    [[ -d docker/nginx/https.d ]] || die "Missing docker/nginx/https.d."
}

require_env_file() {
    [[ -f "${ENV_FILE}" ]] || die "Missing ${ENV_FILE}. Create it on the VPS first."
}

require_commands() {
    command -v docker >/dev/null 2>&1 || die "docker command not found."
    docker compose version >/dev/null 2>&1 || die "docker compose plugin not found."
    docker info >/dev/null 2>&1 || die "Current user cannot access Docker."
}

env_get() {
    local key="$1"
    local default="${2:-}"
    local value

    value="$(awk -F= -v key="${key}" '$1 == key { sub(/^[^=]*=/, ""); print; found=1 } END { if (!found) exit 1 }' "${ENV_FILE}" 2>/dev/null || true)"
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

compose() {
    docker compose --env-file "${ENV_FILE}" "$@"
}

load_required_env() {
    MOODLE_DOMAIN="$(env_get MOODLE_DOMAIN)"
    KEYCLOAK_DOMAIN="$(env_get KEYCLOAK_DOMAIN)"
    LETSENCRYPT_EMAIL="$(env_get LETSENCRYPT_EMAIL)"
    LETSENCRYPT_CERT_NAME="$(env_get LETSENCRYPT_CERT_NAME "${DEFAULT_CERT_NAME}")"

    [[ -n "${MOODLE_DOMAIN}" ]] || die "MOODLE_DOMAIN is missing in ${ENV_FILE}."
    [[ -n "${KEYCLOAK_DOMAIN}" ]] || die "KEYCLOAK_DOMAIN is missing in ${ENV_FILE}."
    [[ -n "${LETSENCRYPT_EMAIL}" ]] || die "LETSENCRYPT_EMAIL is missing in ${ENV_FILE}."
    [[ "${LETSENCRYPT_CERT_NAME}" == "${DEFAULT_CERT_NAME}" ]] || die "LETSENCRYPT_CERT_NAME must be ${DEFAULT_CERT_NAME}; Nginx configs reference this certificate path."
}

enable_http_mode_for_challenge() {
    section "Prepare HTTP challenge mode"

    env_set NGINX_CONF_DIR "${HTTP_CONF_DIR}"
    compose config >/dev/null
    compose up -d nginx

    ok "Nginx is running with HTTP challenge configuration."
}

issue_certificates() {
    section "Issue Let's Encrypt certificate"

    compose run --rm certbot certonly \
        --webroot \
        --webroot-path /var/www/certbot \
        --cert-name "${LETSENCRYPT_CERT_NAME}" \
        --email "${LETSENCRYPT_EMAIL}" \
        --agree-tos \
        --no-eff-email \
        --keep-until-expiring \
        -d "${MOODLE_DOMAIN}" \
        -d "${KEYCLOAK_DOMAIN}"

    compose run --rm --entrypoint sh certbot -c "test -s /etc/letsencrypt/live/${LETSENCRYPT_CERT_NAME}/fullchain.pem && test -s /etc/letsencrypt/live/${LETSENCRYPT_CERT_NAME}/privkey.pem"

    ok "Certificate files exist in the certbot_conf Docker volume."
}

enable_https_mode() {
    section "Enable HTTPS mode"

    env_set LETSENCRYPT_CERT_NAME "${LETSENCRYPT_CERT_NAME}"
    env_set NGINX_CONF_DIR "${HTTPS_CONF_DIR}"
    env_set MOODLE_WWWROOT "https://${MOODLE_DOMAIN}"

    compose config >/dev/null
    compose up -d --force-recreate moodle nginx

    ok "Moodle and Nginx were recreated with HTTPS configuration."
}

renew_certificates() {
    section "Renew certificates"

    compose run --rm certbot renew --webroot --webroot-path /var/www/certbot
    compose exec nginx nginx -s reload

    ok "Renewal check completed and Nginx reloaded."
}

show_status() {
    section "Certificate status"

    compose run --rm certbot certificates
}

issue() {
    require_repo_root
    require_env_file
    require_commands
    load_required_env
    enable_http_mode_for_challenge
    issue_certificates
    enable_https_mode

    echo ""
    info "HTTPS endpoints:"
    info "  https://${MOODLE_DOMAIN}"
    info "  https://${KEYCLOAK_DOMAIN}"
}

main() {
    local command="${1:-}"

    case "${command}" in
        issue)
            issue
            ;;
        renew)
            require_repo_root
            require_env_file
            require_commands
            renew_certificates
            ;;
        status)
            require_repo_root
            require_env_file
            require_commands
            show_status
            ;;
        -h|--help|help|'')
            usage
            ;;
        *)
            usage
            die "Unknown command: ${command}"
            ;;
    esac
}

main "$@"
