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
  CONFIRM_KEYCLOAK_REALM_RESET=unrealuni bash scripts/keycloak-realm.sh reset

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
    KEYCLOAK_MOODLE_CLIENT_SECRET="$(env_get KEYCLOAK_MOODLE_CLIENT_SECRET)"
    KEYCLOAK_SEED_USER_PASSWORD="$(env_get KEYCLOAK_SEED_USER_PASSWORD)"
    KEYCLOAK_SEED_EMAIL_DOMAIN="$(env_get KEYCLOAK_SEED_EMAIL_DOMAIN "unrealuni.xyz")"
    KEYCLOAK_DOMAIN="$(env_get KEYCLOAK_DOMAIN "iam.unrealuni.xyz")"
    MOODLE_DOMAIN="$(env_get MOODLE_DOMAIN "${MOODLE_DOMAIN_DEFAULT}")"

    [[ -n "${KEYCLOAK_ADMIN}" ]] || die "KEYCLOAK_ADMIN is required in .env."
    [[ -n "${KEYCLOAK_ADMIN_PASSWORD}" ]] || die "KEYCLOAK_ADMIN_PASSWORD is required in .env."
    [[ -n "${KEYCLOAK_MOODLE_CLIENT_SECRET}" ]] || die "KEYCLOAK_MOODLE_CLIENT_SECRET is required in .env."
    [[ -n "${KEYCLOAK_SEED_USER_PASSWORD}" ]] || die "KEYCLOAK_SEED_USER_PASSWORD is required in .env."

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

ensure_group() {
    local group="$1"

    if kc get groups -r "${KEYCLOAK_REALM}" -q "search=${group}" | grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${group}\""; then
        return
    fi

    kc create groups -r "${KEYCLOAK_REALM}" -s name="${group}" >/dev/null
}

client_uuid() {
    kc get clients -r "${KEYCLOAK_REALM}" -q "clientId=${KEYCLOAK_MOODLE_CLIENT_ID}" --fields id \
        | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1
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
    local email="${username}@${KEYCLOAK_SEED_EMAIL_DOMAIN}"

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

seed_staff_users() {
    local users=(
        "anna.vanbreda|Anna|Vanbreda|IT-Services|admin"
        "hass.lagosi|Hass|Lagosi|IT-Services|admin"
        "priy.delhiwala|Priy|Delhiwala|IT-Services|admin"
        "dave.vonmainz|Dave|Vonmainz|IT-Services|admin"
        "simo.torinese|Simo|Torinese|Faculty of Engineering|manager"
        "sara.kermani|Sara|Kermani|Faculty of Medicine|manager"
        "cleo.parisien|Cleo|Parisien|Faculty of Humanities|manager"
        "rami.lisboeta|Rami|Lisboeta|Faculty of Medicine|course_creator"
        "mark.oxford|Mark|Oxford|Faculty of Humanities|course_creator"
        "fati.granadino|Fati|Granadino|Faculty of Engineering|course_creator"
        "yuki.kobe|Yuki|Kobe|Faculty of Medicine|teacher"
        "omar.valenciano|Omar|Valenciano|Faculty of Humanities|teacher"
        "miri.vonbonn|Miri|Vonbonn|Faculty of Engineering|teacher"
        "lina.vandelft|Lina|Vandelft|Faculty of Medicine|teacher"
        "alex.berliner|Alex|Berliner|Faculty of Humanities|teacher"
        "nadi.marseillais|Nadi|Marseillais|Faculty of Engineering|teacher"
        "dani.york|Dani|York|IT-Services|"
        "mei.nara|Mei|Nara|Finance|"
        "reza.kashani|Reza|Kashani|IT-Services|"
        "rita.sevillano|Rita|Sevillano|Finance|"
    )
    local record username first_name last_name primary_group moodle_role

    for record in "${users[@]}"; do
        IFS='|' read -r username first_name last_name primary_group moodle_role <<< "${record}"
        ensure_user "${username}" "${first_name}" "${last_name}" "staff" "${primary_group}" "${moodle_role}"
    done
}

seed_named_users() {
    local university_role="$1"
    local moodle_role="$2"
    shift 2

    local record username first_name last_name primary_group

    for record in "$@"; do
        IFS='|' read -r username first_name last_name primary_group <<< "${record}"
        ensure_user "${username}" "${first_name}" "${last_name}" "${university_role}" "${primary_group}" "${moodle_role}"
    done
}

seed_users() {
    section "Seed university users"

    local students=(
        "sara.shirazi|Sara|Shirazi|Faculty of Medicine"
        "omar.vandelft|Omar|Vandelft|Faculty of Humanities"
        "ravi.delhiwala|Ravi|Delhiwala|Faculty of Engineering"
        "yuki.osaka|Yuki|Osaka|Faculty of Medicine"
        "lea.vonessen|Lea|Vonessen|Faculty of Humanities"
        "tom.york|Tom|York|Faculty of Engineering"
        "mina.milanese|Mina|Milanese|Faculty of Medicine"
        "zara.lyonnais|Zara|Lyonnais|Faculty of Humanities"
        "nima.tehrani|Nima|Tehrani|Faculty of Engineering"
        "hana.kyoto|Hana|Kyoto|Faculty of Medicine"
        "aria.valenciano|Aria|Valenciano|Faculty of Humanities"
        "kai.tokyo|Kai|Tokyo|Faculty of Engineering"
        "lina.vanbreda|Lina|Vanbreda|Faculty of Medicine"
        "amir.lahori|Amir|Lahori|Faculty of Humanities"
        "nora.bath|Nora|Bath|Faculty of Engineering"
        "maya.vanleiden|Maya|Vanleiden|Faculty of Medicine"
        "noor.kermani|Noor|Kermani|Faculty of Humanities"
        "luca.romano|Luca|Romano|Faculty of Engineering"
        "sana.hyderabadi|Sana|Hyderabadi|Faculty of Medicine"
        "ivan.vanburen|Ivan|Vanburen|Faculty of Humanities"
        "rosa.sevillano|Rosa|Sevillano|Faculty of Engineering"
        "ali.ankarali|Ali|Ankarali|Faculty of Medicine"
        "mei.kobe|Mei|Kobe|Faculty of Humanities"
        "emma.london|Emma|London|Faculty of Engineering"
        "reza.yazdi|Reza|Yazdi|Faculty of Medicine"
        "mila.vonkoln|Mila|Vonkoln|Faculty of Humanities"
        "pavi.madurai|Pavi|Madurai|Faculty of Engineering"
        "luc.parisien|Luc|Parisien|Faculty of Medicine"
        "dara.tabrizi|Dara|Tabrizi|Faculty of Humanities"
        "yara.izmirli|Yara|Izmirli|Faculty of Engineering"
        "hugo.vontrier|Hugo|Vontrier|Faculty of Medicine"
        "ines.lisboeta|Ines|Lisboeta|Faculty of Humanities"
        "sami.lagosi|Sami|Lagosi|Faculty of Engineering"
        "ruby.kent|Ruby|Kent|Faculty of Medicine"
        "tara.genovese|Tara|Genovese|Faculty of Humanities"
        "adam.prager|Adam|Prager|Faculty of Engineering"
        "lila.kashani|Lila|Kashani|Faculty of Medicine"
        "pino.napolitano|Pino|Napolitano|Faculty of Humanities"
        "timo.vankampen|Timo|Vankampen|Faculty of Engineering"
        "eda.istanbullu|Eda|Istanbullu|Faculty of Medicine"
        "rami.torinese|Rami|Torinese|Faculty of Humanities"
        "eva.toledano|Eva|Toledano|Faculty of Engineering"
        "yuna.nara|Yuna|Nara|Faculty of Medicine"
        "alma.granadino|Alma|Granadino|Faculty of Humanities"
        "zain.coimbra|Zain|Coimbra|Faculty of Engineering"
        "nina.nicois|Nina|Nicois|Faculty of Medicine"
        "olga.vonbonn|Olga|Vonbonn|Faculty of Humanities"
        "mona.alexandri|Mona|Alexandri|Faculty of Engineering"
        "jona.dubliner|Jona|Dubliner|Faculty of Medicine"
        "fari.isfahani|Fari|Isfahani|Faculty of Humanities"
    )
    local alumni=(
        "amar.lagosi|Amar|Lagosi|Faculty of Medicine"
        "tara.shirazi|Tara|Shirazi|Faculty of Humanities"
        "kian.dubliner|Kian|Dubliner|Faculty of Engineering"
        "jin.osaka|Jin|Osaka|Faculty of Medicine"
        "mara.granadino|Mara|Granadino|Faculty of Humanities"
        "ali.tehrani|Ali|Tehrani|Faculty of Engineering"
        "lynn.london|Lynn|London|Faculty of Medicine"
        "sana.lahori|Sana|Lahori|Faculty of Humanities"
        "idri.vankampen|Idri|Vankampen|Faculty of Engineering"
        "lila.vonessen|Lila|Vonessen|Faculty of Medicine"
        "eva.napolitano|Eva|Napolitano|Faculty of Humanities"
        "nadi.tabrizi|Nadi|Tabrizi|Faculty of Engineering"
        "andi.coimbra|Andi|Coimbra|Faculty of Medicine"
        "aya.kyoto|Aya|Kyoto|Faculty of Humanities"
        "amin.lagosi|Amin|Lagosi|Faculty of Engineering"
        "niko.vontrier|Niko|Vontrier|Faculty of Medicine"
        "seli.ankarali|Seli|Ankarali|Faculty of Humanities"
        "mate.valenciano|Mate|Valenciano|Faculty of Engineering"
        "ivy.canton|Ivy|Canton|Faculty of Medicine"
        "ola.kashani|Ola|Kashani|Faculty of Humanities"
        "rani.vanleiden|Rani|Vanleiden|Faculty of Engineering"
        "marc.romano|Marc|Romano|Faculty of Medicine"
        "brun.lisboeta|Brun|Lisboeta|Faculty of Humanities"
        "nour.kermani|Nour|Kermani|Faculty of Engineering"
        "erik.vankampen|Erik|Vankampen|Faculty of Medicine"
        "dali.vandelft|Dali|Vandelft|Faculty of Humanities"
        "theo.parisien|Theo|Parisien|Faculty of Engineering"
        "nia.bath|Nia|Bath|Faculty of Medicine"
        "muna.alexandri|Muna|Alexandri|Faculty of Humanities"
        "kira.vanburen|Kira|Vanburen|Faculty of Engineering"
        "jan.prager|Jan|Prager|Faculty of Medicine"
        "yusu.istanbullu|Yusu|Istanbullu|Faculty of Humanities"
        "reem.bergen|Reem|Bergen|Faculty of Engineering"
        "liam.kent|Liam|Kent|Faculty of Medicine"
        "anik.kermani|Anik|Kermani|Faculty of Humanities"
        "toma.vonulm|Toma|Vonulm|Faculty of Engineering"
        "ines.nicois|Ines|Nicois|Faculty of Medicine"
        "jami.vonkoln|Jami|Vonkoln|Faculty of Humanities"
        "raya.lyonnais|Raya|Lyonnais|Faculty of Engineering"
        "lina.vanleiden|Lina|Vanleiden|Faculty of Medicine"
        "nola.camden|Nola|Camden|Faculty of Humanities"
        "ema.milanese|Ema|Milanese|Faculty of Engineering"
        "maks.berliner|Maks|Berliner|Faculty of Medicine"
        "alan.toledano|Alan|Toledano|Faculty of Humanities"
        "zara.torinese|Zara|Torinese|Faculty of Engineering"
        "paru.madurai|Paru|Madurai|Faculty of Medicine"
        "mila.vonmainz|Mila|Vonmainz|Faculty of Humanities"
        "rafi.delhiwala|Rafi|Delhiwala|Faculty of Engineering"
        "hana.tokyo|Hana|Tokyo|Faculty of Medicine"
        "sara.hyderabadi|Sara|Hyderabadi|Faculty of Humanities"
    )
    local guests=(
        "rhea.coimbra|Rhea|Coimbra|"
        "alan.york|Alan|York|"
        "mia.parisien|Mia|Parisien|"
        "ilan.vandelft|Ilan|Vandelft|"
        "sia.toledo|Sia|Toledo|"
        "tim.kent|Tim|Kent|"
        "una.bath|Una|Bath|"
        "max.bergen|Max|Bergen|"
        "lia.nara|Lia|Nara|"
        "ian.kobe|Ian|Kobe|"
    )

    seed_staff_users
    seed_named_users "student" "student" "${students[@]}"
    seed_named_users "alumni" "student" "${alumni[@]}"
    seed_named_users "guest" "guest" "${guests[@]}"

    ok "Seed users ensured: 50 students, 20 staff, 50 alumni, 10 guests."
}

show_summary() {
    section "Summary"

    info "Realm: ${KEYCLOAK_REALM}"
    info "Client: ${KEYCLOAK_MOODLE_CLIENT_ID}"
    info "Issuer: https://${KEYCLOAK_DOMAIN}/realms/${KEYCLOAK_REALM}"
    info "Moodle redirect URI: ${MOODLE_REDIRECT_URI}"
    info "Seed user email domain: ${KEYCLOAK_SEED_EMAIL_DOMAIN}"
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

reset_realm() {
    require_repo_root
    require_env_file
    load_env
    require_commands

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
