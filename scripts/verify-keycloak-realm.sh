#!/usr/bin/env bash
# Read-only verification for the Keycloak realm against repo-owned JSON desired state.

set -uo pipefail

ENV_FILE="${ENV_FILE:-.env}"
KEYCLOAK_REALM_FILE="${KEYCLOAK_REALM_FILE:-data/keycloak-realm.json}"
KEYCLOAK_USERS_FILE="${KEYCLOAK_USERS_FILE:-data/keycloak-users.json}"

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

json_get() {
    local file="$1"
    local expression="$2"
    jq -r "${expression}" "${file}"
}

require_repo_root() {
    if [[ -f docker-compose.yml ]]; then
        pass "Repository root detected"
    else
        fail "Run this script from the project root"
        return 1
    fi
}

require_env_file() {
    if [[ -f "${ENV_FILE}" ]]; then
        pass "Environment file exists: ${ENV_FILE}"
    else
        fail "Missing ${ENV_FILE}"
        return 1
    fi
}

require_data_files() {
    [[ -f "${KEYCLOAK_REALM_FILE}" ]] && pass "Realm data exists: ${KEYCLOAK_REALM_FILE}" || fail "Missing ${KEYCLOAK_REALM_FILE}"
    [[ -f "${KEYCLOAK_USERS_FILE}" ]] && pass "User data exists: ${KEYCLOAK_USERS_FILE}" || fail "Missing ${KEYCLOAK_USERS_FILE}"
}

require_commands() {
    section "Required commands"

    command -v jq >/dev/null 2>&1 && pass "jq command exists" || fail "jq command not found"
    command -v docker >/dev/null 2>&1 && pass "docker command exists" || fail "docker command not found"
    docker compose version >/dev/null 2>&1 && pass "docker compose plugin exists" || fail "docker compose plugin not found"

    if docker info >/dev/null 2>&1; then
        pass "Current user can access Docker"
    else
        fail "Current user cannot access Docker"
    fi
}

validate_data() {
    section "Desired state files"

    if jq -e '
        (.realm.name | type == "string" and length > 0) and
        (.client.clientId | type == "string" and length > 0) and
        (.realmRoles | type == "array" and length > 0) and
        (.clientRoles | type == "array" and length > 0) and
        (.groups | type == "array" and length > 0) and
        (.protocolMappers | type == "array" and length > 0) and
        (.seed.emailDomain | type == "string" and length > 0) and
        (.seed.passwordPattern | type == "string" and contains("{username}")) and
        (.seed.temporaryPassword | type == "boolean")
    ' "${KEYCLOAK_REALM_FILE}" >/dev/null 2>&1; then
        pass "Realm JSON schema is valid"
    else
        fail "Realm JSON schema is invalid"
        return 1
    fi

    if jq -e '
        (.users | type == "array" and length > 0) and
        all(.users[]; (.username | type == "string" and length > 0) and
                      (.firstName | type == "string" and length > 0) and
                      (.lastName | type == "string" and length > 0) and
                      (.universityRole | type == "string" and length > 0)) and
        (([.users[].username] | length) == ([.users[].username] | unique | length))
    ' "${KEYCLOAK_USERS_FILE}" >/dev/null 2>&1; then
        pass "Users JSON schema is valid"
    else
        fail "Users JSON schema is invalid"
        return 1
    fi
}

load_env() {
    KEYCLOAK_ADMIN="$(env_get KEYCLOAK_ADMIN)"
    KEYCLOAK_ADMIN_PASSWORD="$(env_get KEYCLOAK_ADMIN_PASSWORD)"
    KEYCLOAK_DOMAIN="$(env_get KEYCLOAK_DOMAIN)"
    MOODLE_DOMAIN="$(env_get MOODLE_DOMAIN)"
    MOODLE_OAUTH2_CALLBACK_PATH="$(env_get MOODLE_OAUTH2_CALLBACK_PATH "/admin/oauth2callback.php")"

    KEYCLOAK_REALM="$(json_get "${KEYCLOAK_REALM_FILE}" '.realm.name')"
    KEYCLOAK_MOODLE_CLIENT_ID="$(json_get "${KEYCLOAK_REALM_FILE}" '.client.clientId')"
    KEYCLOAK_SEED_EMAIL_DOMAIN="$(json_get "${KEYCLOAK_REALM_FILE}" '.seed.emailDomain')"
    EXPECTED_USER_COUNT="$(jq -r '.users | length' "${KEYCLOAK_USERS_FILE}")"
    EXPECTED_GROUP_COUNT="$(jq -r '.groups | length' "${KEYCLOAK_REALM_FILE}")"

    MOODLE_BASE_URL="https://${MOODLE_DOMAIN}"
    MOODLE_REDIRECT_URI="${MOODLE_BASE_URL}${MOODLE_OAUTH2_CALLBACK_PATH}"
    KEYCLOAK_ISSUER="https://${KEYCLOAK_DOMAIN}/realms/${KEYCLOAK_REALM}"
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

check_realm() {
    section "Realm"

    local realm_json key expected actual
    realm_json="$(kc get "realms/${KEYCLOAK_REALM}" 2>/dev/null || true)"
    if [[ -z "${realm_json}" ]]; then
        fail "Realm missing: ${KEYCLOAK_REALM}"
        return
    fi
    pass "Realm exists: ${KEYCLOAK_REALM}"

    while IFS=$'\t' read -r key expected; do
        actual="$(printf '%s\n' "${realm_json}" | jq -r --arg key "${key}" '.[$key] | tostring')"
        [[ "${actual}" == "${expected}" ]] && pass "Realm ${key} matches" || fail "Realm ${key} is ${actual}, expected ${expected}"
    done < <(jq -r '.realm | to_entries[] | select(.key != "name") | [.key, (.value | tostring)] | @tsv' "${KEYCLOAK_REALM_FILE}")
}

client_uuid() {
    kc get clients -r "${KEYCLOAK_REALM}" -q "clientId=${KEYCLOAK_MOODLE_CLIENT_ID}" --fields id,clientId 2>/dev/null \
        | jq -r --arg clientid "${KEYCLOAK_MOODLE_CLIENT_ID}" '.[] | select(.clientId == $clientid) | .id' \
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

    local client_json key expected actual
    client_json="$(kc get "clients/${MOODLE_CLIENT_UUID}" -r "${KEYCLOAK_REALM}" 2>/dev/null || true)"

    while IFS=$'\t' read -r key expected; do
        actual="$(printf '%s\n' "${client_json}" | jq -r --arg key "${key}" '.[$key] | tostring')"
        [[ "${actual}" == "${expected}" ]] && pass "Client ${key} matches" || fail "Client ${key} is ${actual}, expected ${expected}"
    done < <(jq -r '.client | to_entries[] | [.key, (.value | tostring)] | @tsv' "${KEYCLOAK_REALM_FILE}")

    printf '%s\n' "${client_json}" | jq -e --arg uri "${MOODLE_REDIRECT_URI}" '.redirectUris | index($uri)' >/dev/null 2>&1 \
        && pass "Redirect URI configured: ${MOODLE_REDIRECT_URI}" \
        || fail "Redirect URI missing: ${MOODLE_REDIRECT_URI}"
    printf '%s\n' "${client_json}" | jq -e --arg origin "${MOODLE_BASE_URL}" '.webOrigins | index($origin)' >/dev/null 2>&1 \
        && pass "Web origin configured: ${MOODLE_BASE_URL}" \
        || fail "Web origin missing: ${MOODLE_BASE_URL}"
}

check_realm_roles() {
    section "Realm roles"

    local roles role
    mapfile -t roles < <(jq -r '.realmRoles[]' "${KEYCLOAK_REALM_FILE}")

    for role in "${roles[@]}"; do
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

    local roles role
    mapfile -t roles < <(jq -r '.clientRoles[]' "${KEYCLOAK_REALM_FILE}")

    for role in "${roles[@]}"; do
        if kc get "clients/${MOODLE_CLIENT_UUID}/roles/${role}" -r "${KEYCLOAK_REALM}" >/dev/null 2>&1; then
            pass "Moodle client role exists: ${role}"
        else
            fail "Moodle client role missing: ${role}"
        fi
    done
}

check_groups() {
    section "Groups"

    local groups_json group_count group
    groups_json="$(kc get groups -r "${KEYCLOAK_REALM}" 2>/dev/null || true)"
    group_count="$(printf '%s\n' "${groups_json}" | jq -r 'length')"

    [[ "${group_count}" -eq "${EXPECTED_GROUP_COUNT}" ]] \
        && pass "Group count is ${EXPECTED_GROUP_COUNT}" \
        || fail "Group count is ${group_count}, expected ${EXPECTED_GROUP_COUNT}"

    while IFS= read -r group; do
        if printf '%s\n' "${groups_json}" | jq -e --arg group "${group}" 'any(.[]; .name == $group)' >/dev/null; then
            pass "Group exists: ${group}"
        else
            fail "Group missing: ${group}"
        fi
    done < <(jq -r '.groups[]' "${KEYCLOAK_REALM_FILE}")
}

check_mappers() {
    section "OIDC claim mappers"

    if [[ -z "${MOODLE_CLIENT_UUID:-}" ]]; then
        warn "Mapper checks skipped; client UUID missing"
        return
    fi

    local mappers_json mapper
    mappers_json="$(kc get "clients/${MOODLE_CLIENT_UUID}/protocol-mappers/models" -r "${KEYCLOAK_REALM}" 2>/dev/null || true)"

    while IFS= read -r mapper; do
        if printf '%s\n' "${mappers_json}" | jq -e --arg mapper "${mapper}" 'any(.[]; .name == $mapper)' >/dev/null; then
            pass "OIDC mapper exists: ${mapper}"
        else
            fail "OIDC mapper missing: ${mapper}"
        fi
    done < <(jq -r '.protocolMappers[].name' "${KEYCLOAK_REALM_FILE}")
}

check_users() {
    section "Users"

    local users_json user_count username expected_email actual_email actual_first actual_last first_name last_name
    users_json="$(kc get users -r "${KEYCLOAK_REALM}" -q max=500 2>/dev/null || true)"
    user_count="$(printf '%s\n' "${users_json}" | jq -r 'length')"

    [[ "${user_count}" -eq "${EXPECTED_USER_COUNT}" ]] \
        && pass "User count is ${EXPECTED_USER_COUNT}" \
        || fail "User count is ${user_count}, expected ${EXPECTED_USER_COUNT}"

    while IFS=$'\t' read -r username first_name last_name; do
        expected_email="${username}@${KEYCLOAK_SEED_EMAIL_DOMAIN}"
        actual_email="$(printf '%s\n' "${users_json}" | jq -r --arg username "${username}" '.[] | select(.username == $username) | .email // empty')"
        actual_first="$(printf '%s\n' "${users_json}" | jq -r --arg username "${username}" '.[] | select(.username == $username) | .firstName // empty')"
        actual_last="$(printf '%s\n' "${users_json}" | jq -r --arg username "${username}" '.[] | select(.username == $username) | .lastName // empty')"

        if [[ -z "${actual_email}" ]]; then
            fail "User missing: ${username}"
            continue
        fi
        [[ "${actual_email}" == "${expected_email}" ]] && pass "User email matches: ${username}" || fail "User email mismatch: ${username}"
        [[ "${actual_first}" == "${first_name}" && "${actual_last}" == "${last_name}" ]] && pass "User name matches: ${username}" || fail "User name mismatch: ${username}"
    done < <(jq -r '.users[] | [.username, .firstName, .lastName] | @tsv' "${KEYCLOAK_USERS_FILE}")
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

    printf '%s\n' "${discovery}" | jq -e --arg issuer "${KEYCLOAK_ISSUER}" '.issuer == $issuer' >/dev/null 2>&1 \
        && pass "Discovery issuer matches ${KEYCLOAK_ISSUER}" \
        || fail "Discovery issuer mismatch"
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
    echo -e "${BOLD}${CYAN}Keycloak Realm Verification${NC}"

    require_repo_root || true
    require_env_file || true
    require_data_files
    require_commands
    validate_data || true
    load_env
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
