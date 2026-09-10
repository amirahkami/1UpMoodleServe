#!/usr/bin/env bash
# Interactive bootstrap installer for a fresh VPS.

set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
DEFAULT_DEMO_PASSWORD="ChangeMe-2026!"

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
  bash scripts/bootstrap.sh

Run from the repo root on a fresh Ubuntu 24.04 VPS.
EOF
}

require_repo_root() {
    [[ -f docker-compose.yml ]] || die "Run this script from the project root."
    [[ -d scripts ]] || die "Missing scripts/ directory."
    [[ -d data ]] || die "Missing data/ directory."
}

require_root() {
    [[ "${EUID}" -eq 0 ]] || die "Run as root on the fresh VPS."
}

require_not_root() {
    [[ "${EUID}" -ne 0 ]] || die "Application deploy must run as the SSH/app user, not root."
}

prompt() {
    local label="$1"
    local default="$2"
    local value

    read -r -p "${label} [${default}]: " value
    printf '%s\n' "${value:-${default}}"
}

prompt_required() {
    local label="$1"
    local value

    while true; do
        read -r -p "${label}: " value
        [[ -n "${value}" ]] && { printf '%s\n' "${value}"; return; }
        warn "Value is required." >&2
    done
}

prompt_secret() {
    local label="$1"
    local first
    local second

    while true; do
        read -r -s -p "${label}: " first
        echo "" >&2
        read -r -s -p "Confirm ${label}: " second
        echo "" >&2
        [[ -n "${first}" ]] || { warn "Password cannot be empty." >&2; continue; }
        [[ "${first}" == "${second}" ]] || { warn "Passwords do not match." >&2; continue; }
        [[ "${#first}" -ge 12 ]] || { warn "Use at least 12 characters." >&2; continue; }
        printf '%s\n' "${first}"
        return
    done
}

confirm_exact() {
    local prompt_text="$1"
    local expected="$2"
    local answer

    read -r -p "${prompt_text} Type '${expected}' to continue: " answer
    [[ "${answer}" == "${expected}" ]] || die "Confirmation failed."
}

random_secret() {
    openssl rand -hex 32
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

require_env_file() {
    [[ -f "${ENV_FILE}" ]] || die "Missing ${ENV_FILE}. Run root bootstrap first."

    if grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=.*CHANGE_ME' "${ENV_FILE}"; then
        die "${ENV_FILE} still contains CHANGE_ME placeholders."
    fi
}

collect_config() {
    section "Installer questions"

    ROOT_DOMAIN="$(prompt "Root domain" "example.edu")"
    VPS_IP="$(prompt_required "VPS public IP")"
    MOODLE_DOMAIN="$(prompt "Moodle domain" "moodle.${ROOT_DOMAIN}")"
    KEYCLOAK_DOMAIN="$(prompt "Keycloak domain" "iam.${ROOT_DOMAIN}")"
    LETSENCRYPT_EMAIL="$(prompt "Let's Encrypt email" "admin@${ROOT_DOMAIN}")"

    SSH_USER="$(prompt "SSH admin user" "underroot")"
    SSH_PORT="$(prompt "SSH port" "44422")"

    KEYCLOAK_REALM="$(prompt "Keycloak realm" "university")"
    KEYCLOAK_ADMIN="$(prompt "Keycloak master admin username" "admin")"

    MOODLE_ADMIN_USER="$(prompt "Moodle local admin username" "admin")"
    MOODLE_ADMIN_EMAIL="$(prompt "Moodle local admin email" "admin@${ROOT_DOMAIN}")"
    MOODLE_ADMIN_PASSWORD="$(prompt_secret "Moodle local admin password")"

    KEYCLOAK_SEED_USER_TEMP_PASSWORD="$(prompt "Temporary password for 130 demo users" "${DEFAULT_DEMO_PASSWORD}")"
}

write_env_file() {
    section "Create .env"

    if [[ -f "${ENV_FILE}" ]]; then
        confirm_exact "${ENV_FILE} already exists. Overwrite it?" "yes"
    fi

    umask 077
    {
        printf 'PROJECT_NAME=1upmoodleserve\n'
        printf 'ROOT_DOMAIN=%s\n' "${ROOT_DOMAIN}"
        printf 'VPS_IP=%s\n' "${VPS_IP}"
        printf 'SSH_USER=%s\n' "${SSH_USER}"
        printf 'SSH_PORT=%s\n' "${SSH_PORT}"
        printf '\n'
        printf 'MOODLE_DOMAIN=%s\n' "${MOODLE_DOMAIN}"
        printf 'MOODLE_WWWROOT=http://%s\n' "${MOODLE_DOMAIN}"
        printf 'KEYCLOAK_DOMAIN=%s\n' "${KEYCLOAK_DOMAIN}"
        printf 'LETSENCRYPT_EMAIL=%s\n' "${LETSENCRYPT_EMAIL}"
        printf 'LETSENCRYPT_CERT_NAME=1upmoodleserve\n'
        printf 'NGINX_CONF_DIR=./.generated/nginx/http.d\n'
        printf '\n'
        printf 'MOODLE_BRANCH=MOODLE_502_STABLE\n'
        printf 'MOODLE_ADMIN_USER=%s\n' "${MOODLE_ADMIN_USER}"
        printf 'MOODLE_ADMIN_PASSWORD=%s\n' "${MOODLE_ADMIN_PASSWORD}"
        printf 'MOODLE_ADMIN_EMAIL=%s\n' "${MOODLE_ADMIN_EMAIL}"
        printf 'MOODLE_FULLNAME=Example University Moodle\n'
        printf 'MOODLE_SHORTNAME=ExampleUni\n'
        printf '\n'
        printf 'POSTGRES_IMAGE=postgres:18\n'
        printf 'NGINX_IMAGE=nginx:1.27-alpine\n'
        printf 'CERTBOT_IMAGE=certbot/certbot:v3.1.0\n'
        printf 'POSTGRES_SUPERUSER=postgres\n'
        printf 'POSTGRES_SUPERUSER_PASSWORD=%s\n' "$(random_secret)"
        printf 'MOODLE_DB_NAME=moodle\n'
        printf 'MOODLE_DB_USER=moodle\n'
        printf 'MOODLE_DB_PASSWORD=%s\n' "$(random_secret)"
        printf 'KEYCLOAK_DB_NAME=keycloak\n'
        printf 'KEYCLOAK_DB_USER=keycloak\n'
        printf 'KEYCLOAK_DB_PASSWORD=%s\n' "$(random_secret)"
        printf '\n'
        printf 'KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.7.2\n'
        printf 'KEYCLOAK_ADMIN=%s\n' "${KEYCLOAK_ADMIN}"
        printf 'KEYCLOAK_ADMIN_PASSWORD=%s\n' "$(random_secret)"
        printf 'KEYCLOAK_REALM=%s\n' "${KEYCLOAK_REALM}"
        printf 'KEYCLOAK_SEED_EMAIL_DOMAIN=%s\n' "${ROOT_DOMAIN}"
        printf 'KEYCLOAK_SEED_USER_TEMP_PASSWORD=%s\n' "${KEYCLOAK_SEED_USER_TEMP_PASSWORD}"
        printf 'KEYCLOAK_MOODLE_CLIENT_SECRET=%s\n' "$(random_secret)"
        printf '\n'
        printf 'MOODLE_OAUTH2_ISSUER_URL=\n'
        printf 'MOODLE_OAUTH2_CALLBACK_PATH=/admin/oauth2callback.php\n'
    } > "${ENV_FILE}"

    chmod 600 "${ENV_FILE}"
    ok "Created ${ENV_FILE}. Machine secrets were generated automatically."
}

load_env() {
    ROOT_DOMAIN="$(env_get ROOT_DOMAIN)"
    VPS_IP="$(env_get VPS_IP)"
    SSH_USER="$(env_get SSH_USER "underroot")"
    SSH_PORT="$(env_get SSH_PORT "44422")"
    MOODLE_DOMAIN="$(env_get MOODLE_DOMAIN)"
    KEYCLOAK_DOMAIN="$(env_get KEYCLOAK_DOMAIN)"
}

require_dns_ready() {
    section "DNS check"

    local domain result

    command -v dig >/dev/null 2>&1 || die "dig command not found. Provisioning did not install dnsutils."

    for domain in "${ROOT_DOMAIN}" "${MOODLE_DOMAIN}" "${KEYCLOAK_DOMAIN}"; do
        [[ -n "${domain}" ]] || continue
        result="$(dig @1.1.1.1 +short "${domain}" A | tail -n 1)"
        [[ "${result}" == "${VPS_IP}" ]] || die "${domain} resolves to '${result:-no result}', expected ${VPS_IP}."
        ok "${domain} resolves to ${VPS_IP}."
    done
}

deploy_app() {
    section "Deploy application stack"
    bash scripts/deploy.sh

    section "Issue HTTPS certificates"
    bash scripts/https.sh issue

    section "Restart stack in HTTPS mode"
    bash scripts/deploy.sh

    section "Apply Keycloak desired state"
    KEYCLOAK_FORCE_RESEED=1 bash scripts/keycloak-realm.sh apply

    section "Apply Moodle OIDC desired state"
    bash scripts/moodle-oidc.sh apply

    section "Apply Moodle role desired state"
    bash scripts/moodle-roles.sh apply

    section "Verify platform state"
    bash scripts/verify-keycloak-realm.sh
    bash scripts/moodle-oidc.sh verify
    bash scripts/moodle-roles.sh verify

    ok "Bootstrap complete."
    info "Home: https://${ROOT_DOMAIN}"
    info "Moodle: https://${MOODLE_DOMAIN}"
    info "Keycloak: https://${KEYCLOAK_DOMAIN}"
}

app_flow() {
    require_repo_root
    require_not_root
    require_env_file
    load_env
    require_dns_ready
    deploy_app
}

root_flow() {
    local app_dir_quoted

    require_repo_root
    require_root

    section "Provision server"
    bash scripts/provision.sh

    collect_config
    write_env_file
    load_env

    section "Configure SSH"
    SSH_USER="${SSH_USER}" SSH_PORT="${SSH_PORT}" bash scripts/harden.sh ssh-step1

    warn "Open a new terminal and test this login before continuing:"
    warn "ssh -p ${SSH_PORT} ${SSH_USER}@${VPS_IP}"
    confirm_exact "Did the new SSH login work?" "yes"

    SSH_USER="${SSH_USER}" SSH_PORT="${SSH_PORT}" CONFIRM_SSH_READY=yes bash scripts/harden.sh system
    SSH_USER="${SSH_USER}" SSH_PORT="${SSH_PORT}" SERVER_HOST="${VPS_IP}" CONFIRM_DISABLE_ROOT_SSH=yes bash scripts/harden.sh ssh-step2

    section "Prepare app user ownership"
    chown -R "${SSH_USER}:${SSH_USER}" "$(pwd)"
    ok "Project files owned by ${SSH_USER}."

    section "Continue deployment as ${SSH_USER}"
    app_dir_quoted="$(printf '%q' "$(pwd)")"
    sudo -iu "${SSH_USER}" bash -lc "cd ${app_dir_quoted} && bash scripts/bootstrap.sh app"
}

main() {
    case "${1:-}" in
        app)
            app_flow
            ;;
        -h|--help|help)
            usage
            ;;
        '')
            if [[ "${EUID}" -eq 0 ]]; then
                root_flow
            else
                app_flow
            fi
            ;;
        *)
            usage
            die "Unknown command: ${1}"
            ;;
    esac
}

main "$@"
