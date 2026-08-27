#!/usr/bin/env bash
# Create/update the Moodle-focused UnrealUni Keycloak realm.

set -euo pipefail

ENV_FILE=".env"
REALM_DEFAULT="unrealuni"
MOODLE_CLIENT_ID_DEFAULT="moodle"
MOODLE_DOMAIN_DEFAULT="moodle.unrealuni.xyz"

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

Creates/updates:
  realm: unrealuni
  client: moodle
  groups: Faculty of Medicine, Faculty of Humanities, Faculty of Engineering, IT-Services, Finance
  realm roles: student, staff, alumni, guest
  Moodle client roles: admin, manager, course_creator, teacher, student, guest
  OIDC claims: groups, primary_group, university_role, moodle_roles
  seeded users: 50 students, 20 staff, 50 alumni, 10 guests

Required .env values:
  KEYCLOAK_ADMIN
  KEYCLOAK_ADMIN_PASSWORD
  KEYCLOAK_MOODLE_CLIENT_SECRET
  KEYCLOAK_SEED_USER_PASSWORD
EOF
}

require_repo_root() {
    [[ -f docker-compose.yml ]] || die "Run this script from the project root."
}

require_env_file() {
    [[ -f "${ENV_FILE}" ]] || die "Missing ${ENV_FILE}. Create it on the VPS first."
}

load_env() {
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a

    KEYCLOAK_REALM="${KEYCLOAK_REALM:-${REALM_DEFAULT}}"
    KEYCLOAK_MOODLE_CLIENT_ID="${KEYCLOAK_MOODLE_CLIENT_ID:-${MOODLE_CLIENT_ID_DEFAULT}}"
    MOODLE_DOMAIN="${MOODLE_DOMAIN:-${MOODLE_DOMAIN_DEFAULT}}"

    : "${KEYCLOAK_ADMIN:?KEYCLOAK_ADMIN is required in .env}"
    : "${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD is required in .env}"
    : "${KEYCLOAK_MOODLE_CLIENT_SECRET:?KEYCLOAK_MOODLE_CLIENT_SECRET is required in .env}"
    : "${KEYCLOAK_SEED_USER_PASSWORD:?KEYCLOAK_SEED_USER_PASSWORD is required in .env}"

    [[ "${KEYCLOAK_MOODLE_CLIENT_SECRET}" != *CHANGE_ME* ]] || die "KEYCLOAK_MOODLE_CLIENT_SECRET still contains CHANGE_ME."
    [[ "${KEYCLOAK_SEED_USER_PASSWORD}" != *CHANGE_ME* ]] || die "KEYCLOAK_SEED_USER_PASSWORD still contains CHANGE_ME."

    MOODLE_BASE_URL="https://${MOODLE_DOMAIN}"
    MOODLE_REDIRECT_URI="${MOODLE_BASE_URL}/*"
}

require_commands() {
    command -v docker >/dev/null 2>&1 || die "docker command not found."
    docker compose version >/dev/null 2>&1 || die "docker compose plugin not found."
    docker info >/dev/null 2>&1 || die "Current user cannot access Docker."
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

ensure_realm() {
    section "Realm"

    if realm_exists; then
        kc update "realms/${KEYCLOAK_REALM}" \
            -s enabled=true \
            -s registrationAllowed=false \
            -s resetPasswordAllowed=true \
            -s rememberMe=true \
            -s sslRequired=external >/dev/null
        ok "Realm ${KEYCLOAK_REALM} updated."
    else
        kc create realms \
            -s realm="${KEYCLOAK_REALM}" \
            -s enabled=true \
            -s registrationAllowed=false \
            -s resetPasswordAllowed=true \
            -s rememberMe=true \
            -s sslRequired=external >/dev/null
        ok "Realm ${KEYCLOAK_REALM} created."
    fi
}

ensure_realm_role() {
    local role="$1"

    if kc get "roles/${role}" -r "${KEYCLOAK_REALM}" >/dev/null 2>&1; then
        return
    fi

    kc create roles -r "${KEYCLOAK_REALM}" -s name="${role}" >/dev/null
}

ensure_group() {
    local group="$1"

    if kc get groups -r "${KEYCLOAK_REALM}" -q "search=${group}" | grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${group}\""; then
        return
    fi

    kc create groups -r "${KEYCLOAK_REALM}" -s name="${group}" >/dev/null
}

client_uuid() {
    kc get clients -r "${KEYCLOAK_REALM}" -q "clientId=${KEYCLOAK_MOODLE_CLIENT_ID}" --fields id --format csv \
        | awk 'NR == 2 { gsub(/"/, "", $1); print $1 }'
}

ensure_client() {
    section "Moodle client"

    local uuid
    uuid="$(client_uuid)"

    if [[ -z "${uuid}" ]]; then
        kc create clients -r "${KEYCLOAK_REALM}" \
            -s clientId="${KEYCLOAK_MOODLE_CLIENT_ID}" \
            -s name="${KEYCLOAK_MOODLE_CLIENT_ID}" \
            -s enabled=true \
            -s protocol=openid-connect \
            -s publicClient=false \
            -s bearerOnly=false \
            -s standardFlowEnabled=true \
            -s implicitFlowEnabled=false \
            -s directAccessGrantsEnabled=true \
            -s serviceAccountsEnabled=false \
            -s secret="${KEYCLOAK_MOODLE_CLIENT_SECRET}" \
            -s "redirectUris=[\"${MOODLE_REDIRECT_URI}\"]" \
            -s "webOrigins=[\"${MOODLE_BASE_URL}\"]" >/dev/null
        uuid="$(client_uuid)"
        ok "Moodle client created."
    else
        kc update "clients/${uuid}" -r "${KEYCLOAK_REALM}" \
            -s enabled=true \
            -s secret="${KEYCLOAK_MOODLE_CLIENT_SECRET}" \
            -s "redirectUris=[\"${MOODLE_REDIRECT_URI}\"]" \
            -s "webOrigins=[\"${MOODLE_BASE_URL}\"]" >/dev/null
        ok "Moodle client updated."
    fi

    MOODLE_CLIENT_UUID="${uuid}"
}

ensure_client_role() {
    local role="$1"

    if kc get "clients/${MOODLE_CLIENT_UUID}/roles/${role}" -r "${KEYCLOAK_REALM}" >/dev/null 2>&1; then
        return
    fi

    kc create "clients/${MOODLE_CLIENT_UUID}/roles" -r "${KEYCLOAK_REALM}" -s name="${role}" >/dev/null
}

mapper_exists() {
    local mapper="$1"

    kc get "clients/${MOODLE_CLIENT_UUID}/protocol-mappers/models" -r "${KEYCLOAK_REALM}" \
        | grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${mapper}\""
}

create_mapper_from_json() {
    local mapper="$1"
    shift

    if mapper_exists "${mapper}"; then
        return
    fi

    kc create "clients/${MOODLE_CLIENT_UUID}/protocol-mappers/models" -r "${KEYCLOAK_REALM}" "$@" >/dev/null
}

ensure_mappers() {
    section "OIDC claim mappers"

    create_mapper_from_json "groups" \
        -s name=groups \
        -s protocol=openid-connect \
        -s protocolMapper=oidc-group-membership-mapper \
        -s consentRequired=false \
        -s 'config."full.path"=false' \
        -s 'config."id.token.claim"=true' \
        -s 'config."access.token.claim"=true' \
        -s 'config."userinfo.token.claim"=true' \
        -s 'config."claim.name"=groups' \
        -s 'config."jsonType.label"=String'

    create_mapper_from_json "primary_group" \
        -s name=primary_group \
        -s protocol=openid-connect \
        -s protocolMapper=oidc-usermodel-attribute-mapper \
        -s consentRequired=false \
        -s 'config."user.attribute"=primary_group' \
        -s 'config."claim.name"=primary_group' \
        -s 'config."jsonType.label"=String' \
        -s 'config."id.token.claim"=true' \
        -s 'config."access.token.claim"=true' \
        -s 'config."userinfo.token.claim"=true'

    create_mapper_from_json "university_role" \
        -s name=university_role \
        -s protocol=openid-connect \
        -s protocolMapper=oidc-usermodel-attribute-mapper \
        -s consentRequired=false \
        -s 'config."user.attribute"=university_role' \
        -s 'config."claim.name"=university_role' \
        -s 'config."jsonType.label"=String' \
        -s 'config."id.token.claim"=true' \
        -s 'config."access.token.claim"=true' \
        -s 'config."userinfo.token.claim"=true'

    create_mapper_from_json "moodle_roles" \
        -s name=moodle_roles \
        -s protocol=openid-connect \
        -s protocolMapper=oidc-usermodel-client-role-mapper \
        -s consentRequired=false \
        -s "config.\"usermodel.clientRoleMapping.clientId\"=${KEYCLOAK_MOODLE_CLIENT_ID}" \
        -s 'config."claim.name"=moodle_roles' \
        -s 'config."jsonType.label"=String' \
        -s 'config."multivalued"=true' \
        -s 'config."id.token.claim"=true' \
        -s 'config."access.token.claim"=true' \
        -s 'config."userinfo.token.claim"=true' \
        -s 'config."introspection.token.claim"=true'

    ok "OIDC claim mappers ensured."
}

ensure_roles_and_groups() {
    section "Roles and groups"

    for role in student staff alumni guest; do
        ensure_realm_role "${role}"
    done

    for role in admin manager course_creator teacher student guest; do
        ensure_client_role "${role}"
    done

    ensure_group "Faculty of Medicine"
    ensure_group "Faculty of Humanities"
    ensure_group "Faculty of Engineering"
    ensure_group "IT-Services"
    ensure_group "Finance"

    ok "Realm roles, Moodle roles, and groups ensured."
}

user_exists() {
    local username="$1"

    kc get users -r "${KEYCLOAK_REALM}" -q "username=${username}" \
        | grep -Eq "\"username\"[[:space:]]*:[[:space:]]*\"${username}\""
}

ensure_user() {
    local username="$1"
    local first_name="$2"
    local last_name="$3"
    local university_role="$4"
    local primary_group="$5"
    local moodle_role="${6:-}"
    local email="${username}@unrealuni.edu"

    if ! user_exists "${username}"; then
        if [[ -n "${primary_group}" ]]; then
            kc create users -r "${KEYCLOAK_REALM}" \
                -s username="${username}" \
                -s enabled=true \
                -s emailVerified=true \
                -s firstName="${first_name}" \
                -s lastName="${last_name}" \
                -s email="${email}" \
                -s "groups=[\"/${primary_group}\"]" \
                -s "attributes.university_role=${university_role}" \
                -s "attributes.primary_group=${primary_group}" >/dev/null
        else
            kc create users -r "${KEYCLOAK_REALM}" \
                -s username="${username}" \
                -s enabled=true \
                -s emailVerified=true \
                -s firstName="${first_name}" \
                -s lastName="${last_name}" \
                -s email="${email}" \
                -s "attributes.university_role=${university_role}" >/dev/null
        fi

        kc set-password -r "${KEYCLOAK_REALM}" --username "${username}" --new-password "${KEYCLOAK_SEED_USER_PASSWORD}" --temporary >/dev/null
    fi

    kc add-roles -r "${KEYCLOAK_REALM}" --uusername "${username}" --rolename "${university_role}" >/dev/null 2>&1 || true

    if [[ -n "${moodle_role}" ]]; then
        kc add-roles -r "${KEYCLOAK_REALM}" --uusername "${username}" --cclientid "${KEYCLOAK_MOODLE_CLIENT_ID}" --rolename "${moodle_role}" >/dev/null 2>&1 || true
    fi
}

faculty_for_index() {
    local index="$1"

    case $((index % 3)) in
        1) echo "Faculty of Medicine" ;;
        2) echo "Faculty of Humanities" ;;
        *) echo "Faculty of Engineering" ;;
    esac
}

seed_staff_users() {
    ensure_user "anna.meyer" "Anna" "Meyer" "staff" "IT-Services" "admin"
    ensure_user "rami.youssef" "Rami" "Youssef" "staff" "IT-Services" "admin"
    ensure_user "clara.dubois" "Clara" "Dubois" "staff" "IT-Services" "admin"
    ensure_user "mark.stone" "Mark" "Stone" "staff" "IT-Services" "admin"

    ensure_user "owen.clark" "Owen" "Clark" "staff" "Faculty of Medicine" "manager"
    ensure_user "julia.fischer" "Julia" "Fischer" "staff" "Faculty of Humanities" "manager"
    ensure_user "alex.morgan" "Alex" "Morgan" "staff" "Faculty of Engineering" "manager"

    ensure_user "sara.keller" "Sara" "Keller" "staff" "Faculty of Medicine" "course_creator"
    ensure_user "victor.hugo" "Victor" "Hugo" "staff" "Faculty of Humanities" "course_creator"
    ensure_user "fatima.bello" "Fatima" "Bello" "staff" "Faculty of Engineering" "course_creator"

    ensure_user "david.nolan" "David" "Nolan" "staff" "Faculty of Medicine" "teacher"
    ensure_user "miriam.hoffmann" "Miriam" "Hoffmann" "staff" "Faculty of Medicine" "teacher"
    ensure_user "nadia.saleh" "Nadia" "Saleh" "staff" "Faculty of Humanities" "teacher"
    ensure_user "peter.weber" "Peter" "Weber" "staff" "Faculty of Humanities" "teacher"
    ensure_user "simon.reed" "Simon" "Reed" "staff" "Faculty of Engineering" "teacher"
    ensure_user "elena.marin" "Elena" "Marin" "staff" "Faculty of Engineering" "teacher"

    ensure_user "daniel.wolf" "Daniel" "Wolf" "staff" "IT-Services"
    ensure_user "olga.sokolov" "Olga" "Sokolov" "staff" "IT-Services"
    ensure_user "priya.shah" "Priya" "Shah" "staff" "Finance"
    ensure_user "hassan.karim" "Hassan" "Karim" "staff" "Finance"
}

seed_numbered_users() {
    local type="$1"
    local count="$2"
    local realm_role="$3"
    local moodle_role="$4"
    local i
    local username
    local last_name
    local first_name
    local faculty

    for i in $(seq 1 "${count}"); do
        username="$(printf '%s%03d' "${type}" "${i}")"
        last_name="$(printf '%03d' "${i}")"
        first_name="$(printf '%s' "${type}" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')"

        if [[ "${realm_role}" == "guest" ]]; then
            ensure_user "${username}" "${first_name}" "${last_name}" "${realm_role}" "" "${moodle_role}"
        else
            faculty="$(faculty_for_index "${i}")"
            ensure_user "${username}" "${first_name}" "${last_name}" "${realm_role}" "${faculty}" "${moodle_role}"
        fi
    done
}

seed_users() {
    section "Seed university users"

    seed_staff_users
    seed_numbered_users "student" 50 "student" "student"
    seed_numbered_users "alumni" 50 "alumni" "student"
    seed_numbered_users "guest" 10 "guest" "guest"

    ok "Seed users ensured: 50 students, 20 staff, 50 alumni, 10 guests."
}

show_summary() {
    section "Summary"

    info "Realm: ${KEYCLOAK_REALM}"
    info "Client: ${KEYCLOAK_MOODLE_CLIENT_ID}"
    info "Issuer: https://${KEYCLOAK_DOMAIN:-iam.unrealuni.xyz}/realms/${KEYCLOAK_REALM}"
    info "Moodle redirect URI: ${MOODLE_REDIRECT_URI}"
    info "Seeded user password is temporary and must be changed on first login."
}

apply_realm() {
    require_repo_root
    require_env_file
    load_env
    require_commands
    authenticate
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
