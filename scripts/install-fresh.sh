#!/usr/bin/env bash
# Fresh VPS orchestration entrypoint.
#
# This script coordinates existing repo-owned scripts. It does not replace them.

set -euo pipefail

APP_DIR="${APP_DIR:-/opt/1upmoodleserve}"
ENV_FILE="${ENV_FILE:-.env}"

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
  sudo bash scripts/install-fresh.sh root
  bash scripts/install-fresh.sh app
  bash scripts/install-fresh.sh verify

Phases:
  root    Run as root on a fresh Ubuntu 24.04 VPS. Installs packages, Docker,
          creates the SSH user, keeps password auth, applies host hardening.
  app     Run as the SSH/app user from /opt/1upmoodleserve after .env exists.
          Deploys HTTP, issues HTTPS, applies Keycloak/Moodle desired state.
  verify  Run read-only checks for server, Keycloak, and Moodle OIDC state.

Required before app:
  - repo copied to /opt/1upmoodleserve
  - /opt/1upmoodleserve/.env created from .env.example with real values
  - DNS A records point to VPS_IP from .env
EOF
}

require_repo_root() {
    [[ -f docker-compose.yml ]] || die "Run this script from the project root."
    [[ -d scripts ]] || die "Missing scripts/ directory."
    [[ -d data ]] || die "Missing data/ directory."
}

require_root() {
    [[ "${EUID}" -eq 0 ]] || die "Run this phase as root: sudo bash scripts/install-fresh.sh root"
}

require_not_root() {
    [[ "${EUID}" -ne 0 ]] || die "Run this phase as the SSH/app user, not root."
}

require_app_dir() {
    local current_dir
    current_dir="$(pwd)"
    [[ "${current_dir}" == "${APP_DIR}" ]] || die "Run from ${APP_DIR}. Current directory: ${current_dir}"
}

require_env_file() {
    [[ -f "${ENV_FILE}" ]] || die "Missing ${ENV_FILE}. Copy .env.example to .env and fill real values."

    if grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=.*CHANGE_ME' "${ENV_FILE}"; then
        die "${ENV_FILE} still contains CHANGE_ME placeholders."
    fi
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

require_dns_ready() {
    section "DNS preflight"

    local vps_ip root_domain moodle_domain keycloak_domain domain result

    command -v dig >/dev/null 2>&1 || die "dig command not found. Run the root phase first."

    vps_ip="$(env_get VPS_IP)"
    root_domain="$(env_get ROOT_DOMAIN)"
    moodle_domain="$(env_get MOODLE_DOMAIN)"
    keycloak_domain="$(env_get KEYCLOAK_DOMAIN)"

    [[ -n "${vps_ip}" ]] || die "VPS_IP is required in ${ENV_FILE}."

    for domain in "${root_domain}" "${moodle_domain}" "${keycloak_domain}"; do
        [[ -n "${domain}" ]] || continue
        result="$(dig @1.1.1.1 +short "${domain}" A | tail -n 1)"
        [[ "${result}" == "${vps_ip}" ]] || die "${domain} resolves to '${result:-no result}', expected ${vps_ip}."
        ok "${domain} resolves to ${vps_ip}."
    done
}

root_phase() {
    require_repo_root
    require_root

    section "Root phase"
    bash scripts/provision.sh
    bash scripts/harden.sh ssh-step1
    bash scripts/harden.sh system

    ok "Root phase complete."
    warn "Open a new terminal and verify password SSH before disabling root SSH:"
    warn "  ssh -p \${SSH_PORT:-44422} \${SSH_USER:-underroot}@<server-ip>"
    warn "Then run:"
    warn "  sudo bash scripts/harden.sh ssh-step2"
    warn "  cd ${APP_DIR} && bash scripts/install-fresh.sh app"
}

app_phase() {
    require_repo_root
    require_not_root
    require_app_dir
    require_env_file
    require_dns_ready

    section "Deploy application stack"
    bash scripts/deploy.sh

    section "Issue HTTPS certificates"
    bash scripts/https.sh issue

    section "Restart stack in final HTTPS mode"
    bash scripts/deploy.sh

    section "Apply Keycloak desired state"
    KEYCLOAK_FORCE_RESEED=1 bash scripts/keycloak-realm.sh apply

    section "Apply Moodle OIDC desired state"
    bash scripts/moodle-oidc.sh apply

    section "Verify desired state"
    bash scripts/verify-keycloak-realm.sh
    bash scripts/moodle-oidc.sh verify

    ok "Application phase complete."
    info "Final manual check: browser login to Moodle with one seeded user."
}

verify_phase() {
    require_repo_root
    require_env_file

    section "Verify server"
    if [[ "${EUID}" -eq 0 ]]; then
        bash scripts/verify-server.sh
    else
        warn "Skipping scripts/verify-server.sh because it should be run with sudo for full host checks."
        warn "Run separately: sudo bash scripts/verify-server.sh"
    fi

    section "Verify Keycloak and Moodle"
    bash scripts/verify-keycloak-realm.sh
    bash scripts/moodle-oidc.sh verify
}

main() {
    local command="${1:-}"

    case "${command}" in
        root)
            root_phase
            ;;
        app)
            app_phase
            ;;
        verify)
            verify_phase
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
