#!/usr/bin/env bash
# Create/update the Keycloak realm from repo-owned JSON desired state.

set -euo pipefail

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
  bash scripts/keycloak-realm.sh apply
  CONFIRM_KEYCLOAK_REALM_RESET=<realm-name> bash scripts/keycloak-realm.sh reset

Reads desired state from:
  data/keycloak-realm.json
  data/keycloak-users.json

Secrets still come from .env:
  KEYCLOAK_ADMIN
  KEYCLOAK_ADMIN_PASSWORD
  KEYCLOAK_MOODLE_CLIENT_SECRET
EOF
}

require_repo_root() {
    [[ -f docker-compose.yml ]] || die "Run this script from the project root."
}

require_env_file() {
    [[ -f "${ENV_FILE}" ]] || die "Missing ${ENV_FILE}. Create it on the VPS first."
}

require_data_files() {
    [[ -f "${KEYCLOAK_REALM_FILE}" ]] || die "Missing ${KEYCLOAK_REALM_FILE}."
    [[ -f "${KEYCLOAK_USERS_FILE}" ]] || die "Missing ${KEYCLOAK_USERS_FILE}."
}

require_commands() {
    command -v jq >/dev/null 2>&1 || die "jq command not found. Run scripts/provision.sh first."
    command -v docker >/dev/null 2>&1 || die "docker command not found."
    docker compose version >/dev/null 2>&1 || die "docker compose plugin not found."
    docker info >/dev/null 2>&1 || die "Current user cannot access Docker."
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
    jq -er "${expression}" "${file}"
}

validate_data() {
    section "Validate desired state"

    jq -e '
        (.realm.name | type == "string" and length > 0) and
        (.client.clientId | type == "string" and length > 0) and
        (.realmRoles | type == "array" and length > 0) and
        (.clientRoles | type == "array" and length > 0) and
        (.groups | type == "array" and length > 0) and
        (.protocolMappers | type == "array" and length > 0) and
        (.seed.emailDomain | type == "string" and length > 0) and
        (.seed.passwordPattern | type == "string" and contains("{username}")) and
        (.seed.temporaryPassword | type == "boolean")
    ' "${KEYCLOAK_REALM_FILE}" >/dev/null || die "Invalid ${KEYCLOAK_REALM_FILE}."

    jq -e '
        (.users | type == "array" and length > 0) and
        all(.users[]; (.username | type == "string" and length > 0) and
                      (.firstName | type == "string" and length > 0) and
                      (.lastName | type == "string" and length > 0) and
                      (.universityRole | type == "string" and length > 0)) and
        (([.users[].username] | length) == ([.users[].username] | unique | length))
    ' "${KEYCLOAK_USERS_FILE}" >/dev/null || die "Invalid ${KEYCLOAK_USERS_FILE}."

    ok "Desired-state JSON is valid."
}

load_env() {
    KEYCLOAK_ADMIN="$(env_get KEYCLOAK_ADMIN)"
    KEYCLOAK_ADMIN_PASSWORD="$(env_get KEYCLOAK_ADMIN_PASSWORD)"
    KEYCLOAK_MOODLE_CLIENT_SECRET="$(env_get KEYCLOAK_MOODLE_CLIENT_SECRET)"
    KEYCLOAK_DOMAIN="$(env_get KEYCLOAK_DOMAIN)"
    MOODLE_DOMAIN="$(env_get MOODLE_DOMAIN)"
    MOODLE_OAUTH2_CALLBACK_PATH="$(env_get MOODLE_OAUTH2_CALLBACK_PATH "/admin/oauth2callback.php")"

    KEYCLOAK_REALM="$(json_get "${KEYCLOAK_REALM_FILE}" '.realm.name')"
    KEYCLOAK_MOODLE_CLIENT_ID="$(json_get "${KEYCLOAK_REALM_FILE}" '.client.clientId')"
    KEYCLOAK_SEED_EMAIL_DOMAIN="$(json_get "${KEYCLOAK_REALM_FILE}" '.seed.emailDomain')"
    KEYCLOAK_SEED_PASSWORD_PATTERN="$(json_get "${KEYCLOAK_REALM_FILE}" '.seed.passwordPattern')"
    KEYCLOAK_SEED_PASSWORD_TEMPORARY="$(json_get "${KEYCLOAK_REALM_FILE}" '.seed.temporaryPassword')"
    EXPECTED_USER_COUNT="$(jq -r '.users | length' "${KEYCLOAK_USERS_FILE}")"

    [[ -n "${KEYCLOAK_ADMIN}" ]] || die "KEYCLOAK_ADMIN is required in ${ENV_FILE}."
    [[ -n "${KEYCLOAK_ADMIN_PASSWORD}" ]] || die "KEYCLOAK_ADMIN_PASSWORD is required in ${ENV_FILE}."
    [[ -n "${KEYCLOAK_MOODLE_CLIENT_SECRET}" ]] || die "KEYCLOAK_MOODLE_CLIENT_SECRET is required in ${ENV_FILE}."
    [[ -n "${KEYCLOAK_DOMAIN}" ]] || die "KEYCLOAK_DOMAIN is required in ${ENV_FILE}."
    [[ -n "${MOODLE_DOMAIN}" ]] || die "MOODLE_DOMAIN is required in ${ENV_FILE}."

    [[ "${KEYCLOAK_MOODLE_CLIENT_SECRET}" != *CHANGE_ME* ]] || die "KEYCLOAK_MOODLE_CLIENT_SECRET still contains CHANGE_ME."

    MOODLE_BASE_URL="https://${MOODLE_DOMAIN}"
    MOODLE_REDIRECT_URI="${MOODLE_BASE_URL}${MOODLE_OAUTH2_CALLBACK_PATH}"
}

kc() {
    docker compose --env-file "${ENV_FILE}" exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"
}

authenticate() {
    section "Authenticate to Keycloak"

    kc config credentials \
        --server http://localhost:8080 \
        --realm master \
        --user "${KEYCLOAK_ADMIN}" \
        --password "${KEYCLOAK_ADMIN_PASSWORD}" >/dev/null

    ok "Authenticated with the Keycloak admin CLI."
}

realm_exists() {
    kc get "realms/${KEYCLOAK_REALM}" >/dev/null 2>&1
}

realm_payload() {
    jq '{
        realm: .realm.name,
        enabled: .realm.enabled,
        registrationAllowed: .realm.registrationAllowed,
        resetPasswordAllowed: .realm.resetPasswordAllowed,
        rememberMe: .realm.rememberMe,
        sslRequired: .realm.sslRequired
    }' "${KEYCLOAK_REALM_FILE}"
}

write_tmp_json() {
    local tmp
    tmp="$(mktemp)"
    cat > "${tmp}"
    printf '%s\n' "${tmp}"
}

ensure_realm() {
    section "Realm"

    local tmp
    tmp="$(realm_payload | write_tmp_json)"
    if realm_exists; then
        kc update "realms/${KEYCLOAK_REALM}" -f "${tmp}" >/dev/null
        ok "Realm ${KEYCLOAK_REALM} updated."
    else
        kc create realms -f "${tmp}" >/dev/null
        ok "Realm ${KEYCLOAK_REALM} created."
    fi
    rm -f "${tmp}"
}

delete_realm() {
    section "Delete realm"

    if realm_exists; then
        kc delete "realms/${KEYCLOAK_REALM}" >/dev/null
        ok "Realm ${KEYCLOAK_REALM} deleted."
    else
        warn "Realm ${KEYCLOAK_REALM} does not exist."
    fi
}

ensure_realm_role() {
    local role="$1"

    if kc get "roles/${role}" -r "${KEYCLOAK_REALM}" >/dev/null 2>&1; then
        return
    fi

    kc create roles -r "${KEYCLOAK_REALM}" -s name="${role}" >/dev/null
}

group_id() {
    local group="$1"
    kc get groups -r "${KEYCLOAK_REALM}" -q "search=${group}" --fields id,name 2>/dev/null \
        | jq -r --arg group "${group}" '.[] | select(.name == $group) | .id' \
        | head -n 1
}

ensure_group() {
    local group="$1"

    if [[ -n "$(group_id "${group}")" ]]; then
        return
    fi

    kc create groups -r "${KEYCLOAK_REALM}" -s name="${group}" >/dev/null
}

client_uuid() {
    kc get clients -r "${KEYCLOAK_REALM}" -q "clientId=${KEYCLOAK_MOODLE_CLIENT_ID}" --fields id,clientId 2>/dev/null \
        | jq -r --arg clientid "${KEYCLOAK_MOODLE_CLIENT_ID}" '.[] | select(.clientId == $clientid) | .id' \
        | head -n 1
}

client_payload() {
    jq \
        --arg secret "${KEYCLOAK_MOODLE_CLIENT_SECRET}" \
        --arg redirect_uri "${MOODLE_REDIRECT_URI}" \
        --arg web_origin "${MOODLE_BASE_URL}" \
        '.client + {secret: $secret, redirectUris: [$redirect_uri], webOrigins: [$web_origin]}' \
        "${KEYCLOAK_REALM_FILE}"
}

ensure_client() {
    section "Moodle client"

    local uuid tmp
    uuid="$(client_uuid)"
    tmp="$(client_payload | write_tmp_json)"

    if [[ -z "${uuid}" ]]; then
        kc create clients -r "${KEYCLOAK_REALM}" -f "${tmp}" >/dev/null
        uuid="$(client_uuid)"
        ok "Moodle client created."
    else
        kc update "clients/${uuid}" -r "${KEYCLOAK_REALM}" -f "${tmp}" >/dev/null
        ok "Moodle client updated."
    fi
    rm -f "${tmp}"

    [[ -n "${uuid}" ]] || die "Could not resolve Keycloak client UUID for ${KEYCLOAK_MOODLE_CLIENT_ID}."
    MOODLE_CLIENT_UUID="${uuid}"
}

ensure_client_role() {
    local role="$1"

    if kc get "clients/${MOODLE_CLIENT_UUID}/roles/${role}" -r "${KEYCLOAK_REALM}" >/dev/null 2>&1; then
        return
    fi

    kc create "clients/${MOODLE_CLIENT_UUID}/roles" -r "${KEYCLOAK_REALM}" -s name="${role}" >/dev/null
}

mapper_id() {
    local mapper="$1"
    kc get "clients/${MOODLE_CLIENT_UUID}/protocol-mappers/models" -r "${KEYCLOAK_REALM}" 2>/dev/null \
        | jq -r --arg mapper "${mapper}" '.[] | select(.name == $mapper) | .id' \
        | head -n 1
}

mapper_payload() {
    local mapper="$1"
    jq \
        --arg mapper "${mapper}" \
        --arg clientid "${KEYCLOAK_MOODLE_CLIENT_ID}" \
        '.protocolMappers[]
         | select(.name == $mapper)
         | if (.config | has("usermodel.clientRoleMapping.clientId"))
           then .config["usermodel.clientRoleMapping.clientId"] = $clientid
           else .
           end' \
        "${KEYCLOAK_REALM_FILE}"
}

ensure_mapper() {
    local mapper="$1"
    local id tmp

    id="$(mapper_id "${mapper}")"
    tmp="$(mapper_payload "${mapper}" | write_tmp_json)"
    if [[ -z "${id}" ]]; then
        kc create "clients/${MOODLE_CLIENT_UUID}/protocol-mappers/models" -r "${KEYCLOAK_REALM}" -f "${tmp}" >/dev/null
    else
        kc update "clients/${MOODLE_CLIENT_UUID}/protocol-mappers/models/${id}" -r "${KEYCLOAK_REALM}" -f "${tmp}" >/dev/null
    fi
    rm -f "${tmp}"
}

ensure_mappers() {
    section "OIDC claim mappers"

    while IFS= read -r mapper; do
        ensure_mapper "${mapper}"
    done < <(jq -r '.protocolMappers[].name' "${KEYCLOAK_REALM_FILE}")

    ok "OIDC claim mappers ensured."
}

ensure_roles_and_groups() {
    section "Roles and groups"

    local role group
    while IFS= read -r role; do
        ensure_realm_role "${role}"
    done < <(jq -r '.realmRoles[]' "${KEYCLOAK_REALM_FILE}")

    while IFS= read -r role; do
        ensure_client_role "${role}"
    done < <(jq -r '.clientRoles[]' "${KEYCLOAK_REALM_FILE}")

    while IFS= read -r group; do
        ensure_group "${group}"
    done < <(jq -r '.groups[]' "${KEYCLOAK_REALM_FILE}")

    ok "Realm roles, Moodle roles, and groups ensured."
}

user_id() {
    local username="$1"
    kc get users -r "${KEYCLOAK_REALM}" -q exact=true -q "username=${username}" --fields id,username 2>/dev/null \
        | jq -r --arg username "${username}" '.[] | select(.username == $username) | .id' \
        | head -n 1
}

render_seed_password() {
    local username="$1"
    local first_name="$2"
    local last_name="$3"
    local password first_lower last_lower

    first_lower="${first_name,,}"
    last_lower="${last_name,,}"
    password="${KEYCLOAK_SEED_PASSWORD_PATTERN}"
    password="${password//\{username\}/${username}}"
    password="${password//\{firstName\}/${first_name}}"
    password="${password//\{lastName\}/${last_name}}"
    password="${password//\{firstname\}/${first_lower}}"
    password="${password//\{lastname\}/${last_lower}}"
    printf '%s\n' "${password}"
}

set_seed_password() {
    local username="$1"
    local first_name="$2"
    local last_name="$3"
    local password
    local args=()

    password="$(render_seed_password "${username}" "${first_name}" "${last_name}")"
    if [[ "${KEYCLOAK_SEED_PASSWORD_TEMPORARY}" == "true" ]]; then
        args+=(--temporary)
    fi

    kc set-password -r "${KEYCLOAK_REALM}" --username "${username}" --new-password "${password}" "${args[@]}" >/dev/null
}

assign_group() {
    local userid="$1"
    local group="$2"
    local groupid

    [[ -n "${group}" ]] || return
    groupid="$(group_id "${group}")"
    [[ -n "${groupid}" ]] || die "Group missing while assigning user: ${group}"
    kc update "users/${userid}/groups/${groupid}" -r "${KEYCLOAK_REALM}" -s realm="${KEYCLOAK_REALM}" -s userId="${userid}" -s groupId="${groupid}" -n >/dev/null 2>&1 || true
}

ensure_user() {
    local username="$1"
    local first_name="$2"
    local last_name="$3"
    local university_role="$4"
    local primary_group="$5"
    local moodle_role="${6:-}"
    local email="${username}@${KEYCLOAK_SEED_EMAIL_DOMAIN}"
    local userid
    local create_args

    userid="$(user_id "${username}")"
    if [[ -z "${userid}" ]]; then
        create_args=(
            -s username="${username}" \
            -s enabled=true \
            -s emailVerified=true \
            -s firstName="${first_name}" \
            -s lastName="${last_name}" \
            -s email="${email}" \
            -s "attributes.university_role=${university_role}"
        )
        if [[ -n "${primary_group}" ]]; then
            create_args+=(
                -s "groups=[\"/${primary_group}\"]"
                -s "attributes.primary_group=${primary_group}"
            )
        fi
        kc create users -r "${KEYCLOAK_REALM}" "${create_args[@]}" >/dev/null
        userid="$(user_id "${username}")"
    else
        kc update "users/${userid}" -r "${KEYCLOAK_REALM}" \
            -s enabled=true \
            -s emailVerified=true \
            -s firstName="${first_name}" \
            -s lastName="${last_name}" \
            -s email="${email}" \
            -s "attributes.university_role=${university_role}" \
            -s "attributes.primary_group=${primary_group}" >/dev/null
    fi

    [[ -n "${userid}" ]] || die "Could not resolve user ID for ${username}."
    assign_group "${userid}" "${primary_group}"
    set_seed_password "${username}" "${first_name}" "${last_name}"

    kc add-roles -r "${KEYCLOAK_REALM}" --uusername "${username}" --rolename "${university_role}" >/dev/null 2>&1 || true

    if [[ -n "${moodle_role}" ]]; then
        kc add-roles -r "${KEYCLOAK_REALM}" --uusername "${username}" --cclientid "${KEYCLOAK_MOODLE_CLIENT_ID}" --rolename "${moodle_role}" >/dev/null 2>&1 || true
    fi
}

seed_users() {
    section "Seed university users"

    local row username first_name last_name university_role primary_group moodle_role
    while IFS=$'\t' read -r username first_name last_name university_role primary_group moodle_role; do
        ensure_user "${username}" "${first_name}" "${last_name}" "${university_role}" "${primary_group}" "${moodle_role}"
    done < <(jq -r '.users[] | [.username, .firstName, .lastName, .universityRole, (.primaryGroup // ""), (.moodleRole // "")] | @tsv' "${KEYCLOAK_USERS_FILE}")

    ok "Seed users ensured: ${EXPECTED_USER_COUNT}."
}

show_summary() {
    section "Summary"

    info "Realm: ${KEYCLOAK_REALM}"
    info "Client: ${KEYCLOAK_MOODLE_CLIENT_ID}"
    info "Issuer: https://${KEYCLOAK_DOMAIN}/realms/${KEYCLOAK_REALM}"
    info "Moodle redirect URI: ${MOODLE_REDIRECT_URI}"
    info "Seed user email domain: ${KEYCLOAK_SEED_EMAIL_DOMAIN}"
    info "Seed password pattern: ${KEYCLOAK_SEED_PASSWORD_PATTERN}"
    info "Seed passwords temporary: ${KEYCLOAK_SEED_PASSWORD_TEMPORARY}"
}

load_and_validate() {
    require_repo_root
    require_env_file
    require_data_files
    require_commands
    validate_data
    load_env
}

apply_realm() {
    load_and_validate
    authenticate
    ensure_realm
    ensure_client
    ensure_roles_and_groups
    ensure_mappers
    seed_users
    show_summary
}

reset_realm() {
    load_and_validate

    [[ "${CONFIRM_KEYCLOAK_REALM_RESET:-}" == "${KEYCLOAK_REALM}" ]] || die "Set CONFIRM_KEYCLOAK_REALM_RESET=${KEYCLOAK_REALM} to reset this realm."

    authenticate
    delete_realm
    ensure_realm
    ensure_client
    ensure_roles_and_groups
    ensure_mappers
    seed_users
    show_summary
}

main() {
    case "${1:-}" in
        apply)
            apply_realm
            ;;
        reset)
            reset_realm
            ;;
        -h|--help|help|'')
            usage
            ;;
        *)
            usage
            die "Unknown command: ${1}"
            ;;
    esac
}

main "$@"
