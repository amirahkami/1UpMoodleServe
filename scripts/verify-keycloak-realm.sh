#!/usr/bin/env bash
# Read-only verification for the UnrealUni Keycloak realm.

set -uo pipefail

ENV_FILE=".env"
REALM_DEFAULT="unrealuni"
MOODLE_CLIENT_ID_DEFAULT="moodle"
MOODLE_DOMAIN_DEFAULT="moodle.unrealuni.xyz"
EXPECTED_USER_COUNT=130
EXPECTED_GROUP_COUNT=5

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

require_repo_root() {
    if [[ ! -f docker-compose.yml ]]; then
        fail "Run this script from the project root."
        return 1
    fi
}

require_env_file() {
    if [[ ! -f "${ENV_FILE}" ]]; then
        fail "Missing ${ENV_FILE}."
        return 1
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

load_env() {
    KEYCLOAK_ADMIN="$(env_get KEYCLOAK_ADMIN)"
    KEYCLOAK_ADMIN_PASSWORD="$(env_get KEYCLOAK_ADMIN_PASSWORD)"
    KEYCLOAK_REALM="$(env_get KEYCLOAK_REALM "${REALM_DEFAULT}")"
    KEYCLOAK_MOODLE_CLIENT_ID="$(env_get KEYCLOAK_MOODLE_CLIENT_ID "${MOODLE_CLIENT_ID_DEFAULT}")"
    KEYCLOAK_SEED_EMAIL_DOMAIN="$(env_get KEYCLOAK_SEED_EMAIL_DOMAIN "unrealuni.xyz")"
    KEYCLOAK_DOMAIN="$(env_get KEYCLOAK_DOMAIN "iam.unrealuni.xyz")"
    MOODLE_DOMAIN="$(env_get MOODLE_DOMAIN "${MOODLE_DOMAIN_DEFAULT}")"

    MOODLE_BASE_URL="https://${MOODLE_DOMAIN}"
    MOODLE_REDIRECT_URI="${MOODLE_BASE_URL}/*"
    KEYCLOAK_ISSUER="https://${KEYCLOAK_DOMAIN}/realms/${KEYCLOAK_REALM}"
}

require_commands() {
    section "Required commands"

    command -v docker >/dev/null 2>&1 && pass "docker command exists" || fail "docker command not found"
    docker compose version >/dev/null 2>&1 && pass "docker compose plugin exists" || fail "docker compose plugin not found"

    if docker info >/dev/null 2>&1; then
        pass "Current user can access Docker"
    else
        fail "Current user cannot access Docker"
    fi
}

kc() {
    docker compose --env-file "${ENV_FILE}" exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"
}

authenticate() {
    section "Keycloak admin CLI"

    if [[ -z "${KEYCLOAK_ADMIN}" || -z "${KEYCLOAK_ADMIN_PASSWORD}" ]]; then
        fail "KEYCLOAK_ADMIN and KEYCLOAK_ADMIN_PASSWORD are required"
        return
    fi

    if kc config credentials --server http://localhost:8080 --realm master --user "${KEYCLOAK_ADMIN}" --password "${KEYCLOAK_ADMIN_PASSWORD}" >/dev/null 2>&1; then
        pass "Authenticated with Keycloak admin CLI"
    else
        fail "Could not authenticate with Keycloak admin CLI"
    fi
}

json_has_name() {
    local name="$1"
    grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${name}\""
}

check_realm() {
    section "Realm"

    if kc get "realms/${KEYCLOAK_REALM}" >/dev/null 2>&1; then
        pass "Realm exists: ${KEYCLOAK_REALM}"
    else
        fail "Realm missing: ${KEYCLOAK_REALM}"
    fi
}

client_uuid() {
    kc get clients -r "${KEYCLOAK_REALM}" -q "clientId=${KEYCLOAK_MOODLE_CLIENT_ID}" --fields id 2>/dev/null \
        | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1
}

check_client() {
    section "Moodle client"

    MOODLE_CLIENT_UUID="$(client_uuid)"

    if [[ -n "${MOODLE_CLIENT_UUID}" ]]; then
        pass "Moodle client exists: ${KEYCLOAK_MOODLE_CLIENT_ID}"
    else
        fail "Moodle client missing: ${KEYCLOAK_MOODLE_CLIENT_ID}"
        return
    fi

    local client_json
    client_json="$(kc get "clients/${MOODLE_CLIENT_UUID}" -r "${KEYCLOAK_REALM}" 2>/dev/null || true)"

    echo "${client_json}" | grep -Eq '"publicClient"[[:space:]]*:[[:space:]]*false' && pass "Moodle client is confidential" || fail "Moodle client is not confidential"
    echo "${client_json}" | grep -Fq "\"${MOODLE_REDIRECT_URI}\"" && pass "Redirect URI configured: ${MOODLE_REDIRECT_URI}" || fail "Redirect URI missing: ${MOODLE_REDIRECT_URI}"
    echo "${client_json}" | grep -Fq "\"${MOODLE_BASE_URL}\"" && pass "Web origin configured: ${MOODLE_BASE_URL}" || fail "Web origin missing: ${MOODLE_BASE_URL}"
}

check_realm_roles() {
    section "Realm roles"

    local role
    for role in student staff alumni guest; do
        if kc get "roles/${role}" -r "${KEYCLOAK_REALM}" >/dev/null 2>&1; then
            pass "Realm role exists: ${role}"
        else
            fail "Realm role missing: ${role}"
        fi
    done
}

check_client_roles() {
    section "Moodle client roles"

    if [[ -z "${MOODLE_CLIENT_UUID:-}" ]]; then
        warn "Moodle client role checks skipped; client UUID missing"
        return
    fi

    local role
    for role in admin manager course_creator teacher student guest; do
        if kc get "clients/${MOODLE_CLIENT_UUID}/roles/${role}" -r "${KEYCLOAK_REALM}" >/dev/null 2>&1; then
            pass "Moodle client role exists: ${role}"
        else
            fail "Moodle client role missing: ${role}"
        fi
    done
}

check_groups() {
    section "Groups"

    local groups_json
    local group_count
    local group

    groups_json="$(kc get groups -r "${KEYCLOAK_REALM}" 2>/dev/null || true)"
    group_count="$(printf '%s\n' "${groups_json}" | grep -Ec '"name"[[:space:]]*:')"

    if [[ "${group_count}" -eq "${EXPECTED_GROUP_COUNT}" ]]; then
        pass "Group count is ${EXPECTED_GROUP_COUNT}"
    else
        fail "Group count is ${group_count}, expected ${EXPECTED_GROUP_COUNT}"
    fi

    for group in "Faculty of Medicine" "Faculty of Humanities" "Faculty of Engineering" "IT-Services" "Finance"; do
        if printf '%s\n' "${groups_json}" | json_has_name "${group}"; then
            pass "Group exists: ${group}"
        else
            fail "Group missing: ${group}"
        fi
    done
}

check_mappers() {
    section "OIDC claim mappers"

    if [[ -z "${MOODLE_CLIENT_UUID:-}" ]]; then
        warn "Mapper checks skipped; client UUID missing"
        return
    fi

    local mappers_json
    local mapper

    mappers_json="$(kc get "clients/${MOODLE_CLIENT_UUID}/protocol-mappers/models" -r "${KEYCLOAK_REALM}" 2>/dev/null || true)"

    for mapper in groups primary_group university_role moodle_roles; do
        if printf '%s\n' "${mappers_json}" | json_has_name "${mapper}"; then
            pass "OIDC mapper exists: ${mapper}"
        else
            fail "OIDC mapper missing: ${mapper}"
        fi
    done
}

check_users() {
    section "Users"

    local users_json
    local usernames
    local user_count
    local bad_email_count
    local username

    users_json="$(kc get users -r "${KEYCLOAK_REALM}" -q max=200 2>/dev/null || true)"
    usernames="$(printf '%s\n' "${users_json}" | sed -n 's/.*"username"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    user_count="$(printf '%s\n' "${users_json}" | grep -Ec '"username"[[:space:]]*:')"

    if [[ "${user_count}" -eq "${EXPECTED_USER_COUNT}" ]]; then
        pass "User count is ${EXPECTED_USER_COUNT}"
    else
        fail "User count is ${user_count}, expected ${EXPECTED_USER_COUNT}"
    fi

    bad_email_count="$(printf '%s\n' "${users_json}" | grep -E '"email"[[:space:]]*:' | grep -Fvc "@${KEYCLOAK_SEED_EMAIL_DOMAIN}\"" || true)"
    if [[ "${user_count}" -eq 0 ]]; then
        fail "Cannot verify user emails because no users were returned"
    elif [[ "${bad_email_count}" -eq 0 ]]; then
        pass "All listed user emails end with @${KEYCLOAK_SEED_EMAIL_DOMAIN}"
    else
        fail "${bad_email_count} listed user emails do not end with @${KEYCLOAK_SEED_EMAIL_DOMAIN}"
    fi

    for username in sara.shirazi anna.vanbreda amar.lagosi rhea.coimbra; do
        if printf '%s\n' "${usernames}" | grep -Fxq "${username}"; then
            pass "Sample user exists: ${username}"
        else
            fail "Sample user missing: ${username}"
        fi
    done

    if printf '%s\n' "${usernames}" | grep -Eq '^(student|alumni|guest)[0-9]+$'; then
        fail "Numbered placeholder usernames are present"
    else
        pass "No numbered placeholder usernames found"
    fi
}

check_public_discovery() {
    section "Public OIDC discovery"

    if ! command -v curl >/dev/null 2>&1; then
        warn "curl not installed; public discovery skipped"
        return
    fi

    local discovery
    discovery="$(curl -fsS "${KEYCLOAK_ISSUER}/.well-known/openid-configuration" 2>/dev/null || true)"

    if [[ -n "${discovery}" ]]; then
        pass "Discovery endpoint responds"
    else
        fail "Discovery endpoint does not respond: ${KEYCLOAK_ISSUER}/.well-known/openid-configuration"
        return
    fi

    printf '%s\n' "${discovery}" | grep -Fq "\"issuer\":\"${KEYCLOAK_ISSUER}\"" && pass "Discovery issuer matches ${KEYCLOAK_ISSUER}" || fail "Discovery issuer mismatch"
}

summary() {
    section "Summary"

    echo -e "  ${GREEN}Pass:${NC} ${PASS_COUNT}"
    echo -e "  ${YELLOW}Warn:${NC} ${WARN_COUNT}"
    echo -e "  ${RED}Fail:${NC} ${FAIL_COUNT}"

    if [[ "${FAIL_COUNT}" -gt 0 ]]; then
        exit 1
    fi
}

main() {
    echo -e "${BOLD}${CYAN}UnrealUni Keycloak Realm Verification${NC}"

    require_repo_root || true
    require_env_file || true
    load_env
    require_commands
    authenticate
    check_realm
    check_client
    check_realm_roles
    check_client_roles
    check_groups
    check_mappers
    check_users
    check_public_discovery
    summary
}

main "$@"
