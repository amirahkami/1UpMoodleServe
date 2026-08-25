#!/usr/bin/env bash
# Read-only verification for a 1UpMoodleServe VPS.

set -uo pipefail

APP_DIR="/opt/1upmoodleserve"
SSH_USER="underroot"
SSH_PORT="44422"
VPS_IP="138.68.64.183"
MOODLE_DOMAIN="moodle.unrealuni.xyz"
KEYCLOAK_DOMAIN="iam.unrealuni.xyz"
ROOT_DOMAIN="unrealuni.xyz"
SSHD_DROP_IN="/etc/ssh/sshd_config.d/01-1upmoodleserve.conf"

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

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

pass() { echo -e "  ${GREEN}PASS${NC}  $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "  ${RED}FAIL${NC}  $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn() { echo -e "  ${YELLOW}WARN${NC}  $*"; WARN_COUNT=$((WARN_COUNT + 1)); }

section() {
    echo ""
    echo -e "${BOLD}${CYAN}==> $*${NC}"
}

pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'
}

check_os() {
    section "Operating system"

    if [[ ! -f /etc/os-release ]]; then
        fail "Cannot read /etc/os-release"
        return
    fi

    # shellcheck source=/dev/null
    . /etc/os-release

    if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]]; then
        pass "Ubuntu 24.04 detected: ${PRETTY_NAME}"
    else
        fail "Expected Ubuntu 24.04, detected: ${PRETTY_NAME:-unknown}"
    fi
}

check_dns() {
    section "DNS"

    if ! command -v dig >/dev/null 2>&1; then
        warn "dig not installed; DNS checks skipped"
        return
    fi

    local domain
    for domain in "${ROOT_DOMAIN}" "${MOODLE_DOMAIN}" "${KEYCLOAK_DOMAIN}"; do
        local result
        result="$(dig @1.1.1.1 +short "${domain}" A | tail -n 1)"
        if [[ "${result}" == "${VPS_IP}" ]]; then
            pass "${domain} resolves to ${VPS_IP}"
        else
            fail "${domain} resolves to '${result:-no result}', expected ${VPS_IP}"
        fi
    done
}

check_project_path() {
    section "Project path"

    if [[ -d "${APP_DIR}" ]]; then
        pass "${APP_DIR} exists"
    else
        fail "${APP_DIR} does not exist"
    fi

    if [[ -f "${APP_DIR}/docker-compose.yml" ]]; then
        pass "docker-compose.yml exists in ${APP_DIR}"
    else
        warn "docker-compose.yml not found in ${APP_DIR}"
    fi

    if [[ -f "${APP_DIR}/.env" ]]; then
        pass ".env exists in ${APP_DIR}"
        if grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=.*CHANGE_ME' "${APP_DIR}/.env"; then
            fail ".env still contains CHANGE_ME placeholders"
        else
            pass ".env contains no CHANGE_ME placeholders"
        fi
    else
        warn ".env not found in ${APP_DIR}"
    fi
}

check_docker() {
    section "Docker"

    if command -v docker >/dev/null 2>&1; then
        pass "docker command exists: $(docker --version)"
    else
        fail "docker command not found"
        return
    fi

    if docker compose version >/dev/null 2>&1; then
        pass "docker compose plugin exists: $(docker compose version)"
    else
        fail "docker compose plugin not available"
    fi

    if systemctl is-active --quiet docker 2>/dev/null; then
        pass "docker service is active"
    else
        fail "docker service is not active"
    fi
}

check_compose() {
    section "Docker Compose project"

    if [[ ! -f "${APP_DIR}/docker-compose.yml" ]]; then
        warn "Compose check skipped; ${APP_DIR}/docker-compose.yml missing"
        return
    fi

    if [[ ! -f "${APP_DIR}/.env" ]]; then
        warn "Compose check skipped; ${APP_DIR}/.env missing"
        return
    fi

    if (cd "${APP_DIR}" && docker compose --env-file .env config >/dev/null 2>&1); then
        pass "docker compose config succeeds"
    else
        fail "docker compose config fails"
    fi

    if (cd "${APP_DIR}" && docker compose --env-file .env ps >/dev/null 2>&1); then
        pass "docker compose ps succeeds"
        (cd "${APP_DIR}" && docker compose --env-file .env ps)
    else
        warn "docker compose ps not available yet"
    fi
}

check_ssh() {
    section "SSH"

    if [[ -f "${SSHD_DROP_IN}" ]]; then
        pass "SSH drop-in exists: ${SSHD_DROP_IN}"

        grep -qE "^Port[[:space:]]+${SSH_PORT}$" "${SSHD_DROP_IN}" && pass "SSH port configured as ${SSH_PORT}" || fail "SSH port is not ${SSH_PORT}"
        grep -qE '^PasswordAuthentication[[:space:]]+yes$' "${SSHD_DROP_IN}" && pass "PasswordAuthentication yes" || fail "PasswordAuthentication is not yes"

        if grep -qE '^PermitRootLogin[[:space:]]+no$' "${SSHD_DROP_IN}"; then
            pass "PermitRootLogin no"
        elif grep -qE '^PermitRootLogin[[:space:]]+yes$' "${SSHD_DROP_IN}"; then
            warn "PermitRootLogin still yes; expected before ssh-step2, not after"
        else
            fail "PermitRootLogin not explicitly configured"
        fi

        grep -qE "^AllowUsers.*\b${SSH_USER}\b" "${SSHD_DROP_IN}" && pass "AllowUsers includes ${SSH_USER}" || fail "AllowUsers does not include ${SSH_USER}"
    else
        warn "SSH hardening drop-in not found; ssh-step1 may not have run"
    fi

    if ss -tln 2>/dev/null | grep -q ":${SSH_PORT} "; then
        pass "SSH appears to listen on ${SSH_PORT}"
    else
        warn "Could not confirm SSH listener on ${SSH_PORT}"
    fi
}

check_firewall_and_fail2ban() {
    section "Firewall and fail2ban"

    if command -v nft >/dev/null 2>&1; then
        pass "nft command exists"

        local ruleset
        ruleset="$(nft list ruleset 2>/dev/null || true)"

        echo "${ruleset}" | grep -q "policy drop" && pass "nftables has a default drop policy" || warn "nftables default drop policy not detected"
        echo "${ruleset}" | grep -qE "tcp dport ${SSH_PORT}\b" && pass "nftables allows SSH ${SSH_PORT}/tcp" || warn "nftables SSH ${SSH_PORT}/tcp rule not detected"
        echo "${ruleset}" | grep -qE "tcp dport.*80" && pass "nftables allows HTTP 80/tcp" || warn "nftables HTTP 80/tcp rule not detected"
        echo "${ruleset}" | grep -qE "tcp dport.*443" && pass "nftables allows HTTPS 443/tcp" || warn "nftables HTTPS 443/tcp rule not detected"
        echo "${ruleset}" | grep -qE 'iifname "br-\*"|oifname "br-\*"' && pass "nftables allows Docker Compose bridge forwarding" || warn "nftables Docker Compose bridge forwarding rule not detected"
    else
        warn "nft command not found; system hardening may not have run"
    fi

    if pkg_installed fail2ban; then
        pass "fail2ban installed"
        systemctl is-active --quiet fail2ban 2>/dev/null && pass "fail2ban active" || fail "fail2ban not active"
    else
        warn "fail2ban not installed"
    fi
}

check_security_basics() {
    section "Security basics"

    pkg_installed unattended-upgrades && pass "unattended-upgrades installed" || warn "unattended-upgrades not installed"

    local ip_forward
    ip_forward="$(sysctl -n net.ipv4.ip_forward 2>/dev/null || true)"
    [[ "${ip_forward}" == "1" ]] && pass "net.ipv4.ip_forward = 1 for Docker networking" || warn "net.ipv4.ip_forward = ${ip_forward:-unknown}; Docker networking expects 1"

    if grep -q '/dev/shm.*noexec' /etc/fstab 2>/dev/null; then
        pass "/dev/shm noexec configured in fstab"
    else
        warn "/dev/shm noexec not configured in fstab"
    fi
}

main() {
    echo ""
    echo -e "${BOLD}${CYAN}1UpMoodleServe Server Verification${NC}"

    check_os
    check_dns
    check_project_path
    check_docker
    check_compose
    check_ssh
    check_firewall_and_fail2ban
    check_security_basics

    echo ""
    echo -e "${BOLD}${CYAN}Summary${NC}"
    echo -e "  ${GREEN}Pass:${NC} ${PASS_COUNT}"
    echo -e "  ${YELLOW}Warn:${NC} ${WARN_COUNT}"
    echo -e "  ${RED}Fail:${NC} ${FAIL_COUNT}"
    echo ""

    exit "${FAIL_COUNT}"
}

main "$@"
