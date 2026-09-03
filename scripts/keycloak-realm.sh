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
trace_seed() {
    [[ "${KEYCLOAK_RESEED_TRACE:-0}" == "1" ]] || return 0
    info "$*"
}

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
    command -v curl >/dev/null 2>&1 || die "curl command not found. Run scripts/provision.sh first."
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
    jq -r "${expression}" "${file}"
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
    KEYCLOAK_BASE_URL="https://${KEYCLOAK_DOMAIN}"
}

kc() {
    docker compose --env-file "${ENV_FILE}" exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"
}

kc_with_json() {
    docker compose --env-file "${ENV_FILE}" exec -T keycloak sh -c '
        tmp="$(mktemp)"
        cat > "${tmp}"
        /opt/keycloak/bin/kcadm.sh "$@" -f "${tmp}"
        status=$?
        rm -f "${tmp}"
        exit "${status}"
    ' kcadm "$@"
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

urlencode() {
    jq -rn --arg value "$1" '$value | @uri'
}

authenticate_rest() {
    KC_ADMIN_TOKEN="$(
        curl -fsS \
            -X POST "${KEYCLOAK_BASE_URL}/realms/master/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "grant_type=password" \
            --data-urlencode "client_id=admin-cli" \
            --data-urlencode "username=${KEYCLOAK_ADMIN}" \
            --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}" \
            | jq -r '.access_token // empty'
    )"

    [[ -n "${KC_ADMIN_TOKEN}" ]] || die "Could not get Keycloak admin REST token."
}

kc_api() {
    local method="$1"
    local path="$2"
    local payload="${3:-}"
    local args=(-fsS -X "${method}" "${KEYCLOAK_BASE_URL}${path}" -H "Authorization: Bearer ${KC_ADMIN_TOKEN}")

    if [[ -n "${payload}" ]]; then
        args+=(-H "Content-Type: application/json" --data "${payload}")
    fi

    curl "${args[@]}"
}

kc_api_empty() {
    local method="$1"
    local path="$2"

    curl -fsS \
        -X "${method}" \
        "${KEYCLOAK_BASE_URL}${path}" \
        -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        --data ''
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

ensure_realm() {
    section "Realm"

    if realm_exists; then
        realm_payload | kc_with_json update "realms/${KEYCLOAK_REALM}" >/dev/null
        ok "Realm ${KEYCLOAK_REALM} updated."
    else
        realm_payload | kc_with_json create realms >/dev/null
        ok "Realm ${KEYCLOAK_REALM} created."
    fi
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

    local uuid
    uuid="$(client_uuid)"

    if [[ -z "${uuid}" ]]; then
        client_payload | kc_with_json create clients -r "${KEYCLOAK_REALM}" >/dev/null
        uuid="$(client_uuid)"
        ok "Moodle client created."
    else
        client_payload | kc_with_json update "clients/${uuid}" -r "${KEYCLOAK_REALM}" >/dev/null
        ok "Moodle client updated."
    fi

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
    local id="${2:-}"
    jq \
        --arg mapper "${mapper}" \
        --arg id "${id}" \
        --arg clientid "${KEYCLOAK_MOODLE_CLIENT_ID}" \
        '.protocolMappers[]
         | select(.name == $mapper)
         | if $id != "" then . + {id: $id} else . end
         | if (.config | has("usermodel.clientRoleMapping.clientId"))
           then .config["usermodel.clientRoleMapping.clientId"] = $clientid
           else .
           end' \
        "${KEYCLOAK_REALM_FILE}"
}

ensure_mapper() {
    local mapper="$1"
    local id

    id="$(mapper_id "${mapper}")"
    if [[ -z "${id}" ]]; then
        mapper_payload "${mapper}" | kc_with_json create "clients/${MOODLE_CLIENT_UUID}/protocol-mappers/models" -r "${KEYCLOAK_REALM}" >/dev/null
    else
        mapper_payload "${mapper}" "${id}" | kc_with_json update "clients/${MOODLE_CLIENT_UUID}/protocol-mappers/models/${id}" -r "${KEYCLOAK_REALM}" >/dev/null
    fi
}

ensure_mappers() {
    section "OIDC claim mappers"

    local mappers mapper
    mapfile -t mappers < <(jq -r '.protocolMappers[].name' "${KEYCLOAK_REALM_FILE}")

    for mapper in "${mappers[@]}"; do
        ensure_mapper "${mapper}"
    done

    ok "OIDC claim mappers ensured."
}

ensure_roles_and_groups() {
    section "Roles and groups"

    local realm_roles client_roles groups role group
    mapfile -t realm_roles < <(jq -r '.realmRoles[]' "${KEYCLOAK_REALM_FILE}")
    mapfile -t client_roles < <(jq -r '.clientRoles[]' "${KEYCLOAK_REALM_FILE}")
    mapfile -t groups < <(jq -r '.groups[]' "${KEYCLOAK_REALM_FILE}")

    for role in "${realm_roles[@]}"; do
        ensure_realm_role "${role}"
    done

    for role in "${client_roles[@]}"; do
        ensure_client_role "${role}"
    done

    for group in "${groups[@]}"; do
        ensure_group "${group}"
    done

    ok "Realm roles, Moodle roles, and groups ensured."
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

rest_user_id() {
    local username="$1"
    local encoded_username

    encoded_username="$(urlencode "${username}")"
    kc_api GET "/admin/realms/${KEYCLOAK_REALM}/users?exact=true&username=${encoded_username}" \
        | jq -r --arg username "${username}" 'map(select(.username == $username))[0].id // empty'
}

rest_client_uuid() {
    local encoded_client_id

    encoded_client_id="$(urlencode "${KEYCLOAK_MOODLE_CLIENT_ID}")"
    kc_api GET "/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${encoded_client_id}" \
        | jq -r --arg clientid "${KEYCLOAK_MOODLE_CLIENT_ID}" 'map(select(.clientId == $clientid))[0].id // empty'
}

rest_group_id() {
    local group="$1"
    local encoded_group

    encoded_group="$(urlencode "${group}")"
    kc_api GET "/admin/realms/${KEYCLOAK_REALM}/groups?search=${encoded_group}&max=100" \
        | jq -r --arg group "${group}" 'map(select(.name == $group))[0].id // empty'
}

rest_role_payload() {
    local role="$1"
    local encoded_role

    encoded_role="$(urlencode "${role}")"
    kc_api GET "/admin/realms/${KEYCLOAK_REALM}/roles/${encoded_role}"
}

rest_client_role_payload() {
    local role="$1"
    local encoded_role

    encoded_role="$(urlencode "${role}")"
    kc_api GET "/admin/realms/${KEYCLOAK_REALM}/clients/${REST_MOODLE_CLIENT_UUID}/roles/${encoded_role}"
}

rest_user_payload() {
    local username="$1"
    local first_name="$2"
    local last_name="$3"
    local university_role="$4"
    local primary_group="$5"
    local email="${username}@${KEYCLOAK_SEED_EMAIL_DOMAIN}"

    jq -n \
        --arg username "${username}" \
        --arg first_name "${first_name}" \
        --arg last_name "${last_name}" \
        --arg email "${email}" \
        --arg university_role "${university_role}" \
        --arg primary_group "${primary_group}" \
        '{
            username: $username,
            enabled: true,
            emailVerified: true,
            firstName: $first_name,
            lastName: $last_name,
            email: $email,
            attributes: {
                university_role: [$university_role]
            }
        }
        | if $primary_group != "" then
            . + {
                groups: ["/" + $primary_group],
                attributes: (.attributes + {primary_group: [$primary_group]})
            }
          else .
          end'
}

rest_reset_password_payload() {
    local password="$1"

    jq -n \
        --arg password "${password}" \
        --argjson temporary "${KEYCLOAK_SEED_PASSWORD_TEMPORARY}" \
        '{type: "password", value: $password, temporary: $temporary}'
}

rest_assign_role() {
    local userid="$1"
    local role="$2"
    local role_payload

    role_payload="$(rest_role_payload "${role}")"
    kc_api POST "/admin/realms/${KEYCLOAK_REALM}/users/${userid}/role-mappings/realm" "[$role_payload]" >/dev/null || true
}

rest_assign_client_role() {
    local userid="$1"
    local role="$2"
    local role_payload

    [[ -n "${role}" ]] || return 0
    role_payload="$(rest_client_role_payload "${role}")"
    kc_api POST "/admin/realms/${KEYCLOAK_REALM}/users/${userid}/role-mappings/clients/${REST_MOODLE_CLIENT_UUID}" "[$role_payload]" >/dev/null || true
}

rest_assign_group() {
    local userid="$1"
    local group="$2"
    local groupid

    [[ -n "${group}" ]] || return 0
    groupid="$(rest_group_id "${group}")"
    [[ -n "${groupid}" ]] || die "Group missing while assigning user: ${group}"
    kc_api_empty PUT "/admin/realms/${KEYCLOAK_REALM}/users/${userid}/groups/${groupid}" >/dev/null
}

rest_ensure_user() {
    local username="$1"
    local first_name="$2"
    local last_name="$3"
    local university_role="$4"
    local primary_group="$5"
    local moodle_role="${6:-}"
    local userid payload password

    trace_seed "Resolving user: ${username}"
    userid="$(rest_user_id "${username}")"
    trace_seed "Rendering user payload: ${username}"
    payload="$(rest_user_payload "${username}" "${first_name}" "${last_name}" "${university_role}" "${primary_group}")"

    if [[ -z "${userid}" ]]; then
        trace_seed "Creating user: ${username}"
        kc_api POST "/admin/realms/${KEYCLOAK_REALM}/users" "${payload}" >/dev/null
        userid="$(rest_user_id "${username}")"
    else
        trace_seed "Updating user: ${username}"
        kc_api PUT "/admin/realms/${KEYCLOAK_REALM}/users/${userid}" "${payload}" >/dev/null
    fi

    [[ -n "${userid}" ]] || die "Could not resolve user ID for ${username}."

    trace_seed "Assigning group: ${username}"
    rest_assign_group "${userid}" "${primary_group}"

    trace_seed "Resetting password: ${username}"
    password="$(render_seed_password "${username}" "${first_name}" "${last_name}")"
    kc_api PUT "/admin/realms/${KEYCLOAK_REALM}/users/${userid}/reset-password" "$(rest_reset_password_payload "${password}")" >/dev/null

    trace_seed "Assigning realm role: ${username}"
    rest_assign_role "${userid}" "${university_role}"
    trace_seed "Assigning Moodle role: ${username}"
    rest_assign_client_role "${userid}" "${moodle_role}"
}

seed_users_rest() {
    local rows row username first_name last_name university_role primary_group moodle_role count

    info "Authenticating to Keycloak Admin REST..."
    authenticate_rest
    info "Resolving Moodle client for role mapping..."
    REST_MOODLE_CLIENT_UUID="$(rest_client_uuid)"
    [[ -n "${REST_MOODLE_CLIENT_UUID}" ]] || die "Could not resolve Keycloak client UUID for ${KEYCLOAK_MOODLE_CLIENT_ID}."

    info "Preparing seed user rows..."
    mapfile -t rows < <(jq -r '.users[] | [.username, .firstName, .lastName, .universityRole, (.primaryGroup // ""), (.moodleRole // "")] | join("\u001f")' "${KEYCLOAK_USERS_FILE}")

    count=0
    for row in "${rows[@]}"; do
        if (( count > 0 && count % 20 == 0 )); then
            trace_seed "Refreshing Keycloak Admin REST token..."
            authenticate_rest
        fi
        IFS=$'\037' read -r username first_name last_name university_role primary_group moodle_role <<< "${row}"
        rest_ensure_user "${username}" "${first_name}" "${last_name}" "${university_role}" "${primary_group}" "${moodle_role}"
        count=$((count + 1))
        if (( count % 25 == 0 )); then
            info "Seeded ${count} users..."
        fi
    done
}

seed_users() {
    section "Seed university users"

    local existing_users_json existing_usernames expected_usernames

    existing_users_json="$(kc get users -r "${KEYCLOAK_REALM}" -q max=500 --fields username 2>/dev/null || true)"
    existing_usernames="$(printf '%s\n' "${existing_users_json}" | jq -r '.[].username' | sort)"
    expected_usernames="$(jq -r '.users[].username' "${KEYCLOAK_USERS_FILE}" | sort)"

    if [[ "${KEYCLOAK_FORCE_RESEED:-0}" != "1" && "${existing_usernames}" == "${expected_usernames}" ]]; then
        ok "Expected seed users already exist; skipping user reapply. Set KEYCLOAK_FORCE_RESEED=1 to repair users or reset passwords."
        return
    fi

    seed_users_rest
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
