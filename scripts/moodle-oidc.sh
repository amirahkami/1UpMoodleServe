#!/usr/bin/env bash
# Configure and verify Moodle's built-in OAuth2 login against Keycloak.

set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
KEYCLOAK_REALM_FILE="${KEYCLOAK_REALM_FILE:-data/keycloak-realm.json}"
MOODLE_OIDC_FILE="${MOODLE_OIDC_FILE:-data/moodle-oidc.json}"

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
fail() { echo -e "${RED}[FAIL]${NC}  $*"; }
die() { fail "$*"; exit 1; }

section() {
    echo ""
    echo -e "${BOLD}${CYAN}==> $*${NC}"
}

usage() {
    cat <<'EOF'
Usage:
  bash scripts/moodle-oidc.sh apply
  bash scripts/moodle-oidc.sh verify

Configures Moodle's built-in OAuth2 authentication for the Keycloak realm.
Run after deploy, HTTPS, and keycloak-realm.sh apply.
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
    [[ -f "${MOODLE_OIDC_FILE}" ]] || die "Missing ${MOODLE_OIDC_FILE}."
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

bool_to_int() {
    case "$1" in
        1|true|TRUE|yes|YES) printf '1\n' ;;
        0|false|FALSE|no|NO) printf '0\n' ;;
        *) die "Expected boolean value, got: $1" ;;
    esac
}

validate_data() {
    jq -e '
        (.issuer.name | type == "string" and length > 0) and
        (.issuer.loginName | type == "string" and length > 0) and
        (.issuer.scopes | type == "string" and length > 0) and
        (.issuer.requireConfirmation | type == "boolean") and
        (.issuer.allowAccountCreation | type == "boolean") and
        (.fieldMappings | type == "array" and length > 0) and
        all(.fieldMappings[]; (.external | type == "string" and length > 0) and
                              (.internal | type == "string" and length > 0))
    ' "${MOODLE_OIDC_FILE}" >/dev/null || die "Invalid ${MOODLE_OIDC_FILE}."
}

load_env() {
    KEYCLOAK_REALM="$(env_get KEYCLOAK_REALM "$(json_get "${KEYCLOAK_REALM_FILE}" '.realm.name')")"
    KEYCLOAK_DOMAIN="$(env_get KEYCLOAK_DOMAIN "iam.example.edu")"
    KEYCLOAK_MOODLE_CLIENT_ID="$(json_get "${KEYCLOAK_REALM_FILE}" '.client.clientId')"
    KEYCLOAK_MOODLE_CLIENT_SECRET="$(env_get KEYCLOAK_MOODLE_CLIENT_SECRET)"
    KEYCLOAK_SEED_EMAIL_DOMAIN="$(env_get KEYCLOAK_SEED_EMAIL_DOMAIN "$(json_get "${KEYCLOAK_REALM_FILE}" '.seed.emailDomain')")"
    MOODLE_DOMAIN="$(env_get MOODLE_DOMAIN)"
    MOODLE_OAUTH2_ISSUER_NAME="$(env_get MOODLE_OAUTH2_ISSUER_NAME "$(json_get "${MOODLE_OIDC_FILE}" '.issuer.name')")"
    MOODLE_OAUTH2_LOGIN_NAME="$(env_get MOODLE_OAUTH2_LOGIN_NAME "$(json_get "${MOODLE_OIDC_FILE}" '.issuer.loginName')")"
    MOODLE_OAUTH2_ISSUER_URL="$(env_get MOODLE_OAUTH2_ISSUER_URL "https://${KEYCLOAK_DOMAIN}/realms/${KEYCLOAK_REALM}")"
    MOODLE_OAUTH2_SCOPES="$(env_get MOODLE_OAUTH2_SCOPES "$(json_get "${MOODLE_OIDC_FILE}" '.issuer.scopes')")"
    MOODLE_OAUTH2_ALLOWED_DOMAINS="$(env_get MOODLE_OAUTH2_ALLOWED_DOMAINS "${KEYCLOAK_SEED_EMAIL_DOMAIN}")"
    MOODLE_OAUTH2_REQUIRE_CONFIRMATION="$(bool_to_int "$(env_get MOODLE_OAUTH2_REQUIRE_CONFIRMATION "$(json_get "${MOODLE_OIDC_FILE}" '.issuer.requireConfirmation')")")"
    MOODLE_OAUTH2_ALLOW_ACCOUNT_CREATION="$(bool_to_int "$(env_get MOODLE_OAUTH2_ALLOW_ACCOUNT_CREATION "$(json_get "${MOODLE_OIDC_FILE}" '.issuer.allowAccountCreation')")")"
    MOODLE_OAUTH2_FIELD_MAPPINGS_JSON="$(jq -c '.fieldMappings' "${MOODLE_OIDC_FILE}")"
    [[ -n "${KEYCLOAK_MOODLE_CLIENT_SECRET}" ]] || die "KEYCLOAK_MOODLE_CLIENT_SECRET is required in ${ENV_FILE}."
    [[ "${KEYCLOAK_MOODLE_CLIENT_SECRET}" != *CHANGE_ME* ]] || die "KEYCLOAK_MOODLE_CLIENT_SECRET still contains CHANGE_ME."
    [[ -n "${MOODLE_DOMAIN}" ]] || die "MOODLE_DOMAIN is required in ${ENV_FILE}."
    [[ -n "${MOODLE_OAUTH2_ISSUER_URL}" ]] || die "MOODLE_OAUTH2_ISSUER_URL is required."
    [[ -n "${MOODLE_OAUTH2_SCOPES}" ]] || die "MOODLE_OAUTH2_SCOPES is required."
}

require_commands() {
    command -v jq >/dev/null 2>&1 || die "jq command not found. Run scripts/provision.sh first."
    command -v docker >/dev/null 2>&1 || die "docker command not found."
    docker compose version >/dev/null 2>&1 || die "docker compose plugin not found."
    docker info >/dev/null 2>&1 || die "Current user cannot access Docker."
}

compose() {
    docker compose --env-file "${ENV_FILE}" "$@"
}

moodle_php() {
    compose exec -T \
        -e MOODLE_OAUTH2_ISSUER_NAME="${MOODLE_OAUTH2_ISSUER_NAME}" \
        -e MOODLE_OAUTH2_LOGIN_NAME="${MOODLE_OAUTH2_LOGIN_NAME}" \
        -e MOODLE_OAUTH2_ISSUER_URL="${MOODLE_OAUTH2_ISSUER_URL}" \
        -e MOODLE_OAUTH2_CLIENT_ID="${KEYCLOAK_MOODLE_CLIENT_ID}" \
        -e MOODLE_OAUTH2_CLIENT_SECRET="${KEYCLOAK_MOODLE_CLIENT_SECRET}" \
        -e MOODLE_OAUTH2_SCOPES="${MOODLE_OAUTH2_SCOPES}" \
        -e MOODLE_OAUTH2_ALLOWED_DOMAINS="${MOODLE_OAUTH2_ALLOWED_DOMAINS}" \
        -e MOODLE_OAUTH2_REQUIRE_CONFIRMATION="${MOODLE_OAUTH2_REQUIRE_CONFIRMATION}" \
        -e MOODLE_OAUTH2_ALLOW_ACCOUNT_CREATION="${MOODLE_OAUTH2_ALLOW_ACCOUNT_CREATION}" \
        -e MOODLE_OAUTH2_FIELD_MAPPINGS_JSON="${MOODLE_OAUTH2_FIELD_MAPPINGS_JSON}" \
        moodle php
}

apply_oidc() {
    section "Configure Moodle OAuth2 issuer"

    moodle_php <<'PHP'
<?php
define('CLI_SCRIPT', true);
require_once('/var/www/html/config.php');
require_once($CFG->libdir . '/filelib.php');

$issuerurl = rtrim(getenv('MOODLE_OAUTH2_ISSUER_URL') ?: '', '/');
$clientid = getenv('MOODLE_OAUTH2_CLIENT_ID') ?: '';
$clientsecret = getenv('MOODLE_OAUTH2_CLIENT_SECRET') ?: '';
$issuername = getenv('MOODLE_OAUTH2_ISSUER_NAME') ?: 'Keycloak';
$loginname = getenv('MOODLE_OAUTH2_LOGIN_NAME') ?: $issuername;
$scopes = getenv('MOODLE_OAUTH2_SCOPES') ?: 'openid profile email';
$alloweddomains = getenv('MOODLE_OAUTH2_ALLOWED_DOMAINS') ?: '';
$requireconfirmation = (int)(getenv('MOODLE_OAUTH2_REQUIRE_CONFIRMATION') ?: 0);
$allowaccountcreation = (int)(getenv('MOODLE_OAUTH2_ALLOW_ACCOUNT_CREATION') ?: 1);
$mappingsjson = getenv('MOODLE_OAUTH2_FIELD_MAPPINGS_JSON') ?: '[]';
$mappings = json_decode($mappingsjson, true);

foreach ([
    'MOODLE_OAUTH2_ISSUER_URL' => $issuerurl,
    'MOODLE_OAUTH2_CLIENT_ID' => $clientid,
    'MOODLE_OAUTH2_CLIENT_SECRET' => $clientsecret,
] as $name => $value) {
    if ($value === '') {
        fwrite(STDERR, "{$name} is required.\n");
        exit(1);
    }
}
if (!is_array($mappings) || count($mappings) === 0) {
    fwrite(STDERR, "MOODLE_OAUTH2_FIELD_MAPPINGS_JSON must contain mappings.\n");
    exit(1);
}

$discoveryurl = $issuerurl . '/.well-known/openid-configuration';
$discoveryjson = @file_get_contents($discoveryurl);
if ($discoveryjson === false || json_decode($discoveryjson) === null) {
    fwrite(STDERR, "Moodle cannot read Keycloak discovery: {$discoveryurl}\n");
    exit(1);
}

$issuer = \core\oauth2\issuer::get_record([
    'baseurl' => $issuerurl,
    'clientid' => $clientid,
]);
if (!$issuer) {
    $issuer = \core\oauth2\issuer::get_record(['name' => $issuername]);
}

$record = (object)[
    'name' => $issuername,
    'image' => '',
    'baseurl' => $issuerurl,
    'clientid' => $clientid,
    'clientsecret' => $clientsecret,
    'loginscopes' => $scopes,
    'loginscopesoffline' => $scopes,
    'loginparams' => '',
    'loginparamsoffline' => '',
    'alloweddomains' => $alloweddomains,
    'enabled' => 1,
    'showonloginpage' => \core\oauth2\issuer::LOGINONLY,
    'basicauth' => 0,
    'requireconfirmation' => $requireconfirmation ? 1 : 0,
    'servicetype' => 'custom',
    'loginpagename' => $loginname,
];

if ($issuer) {
    foreach ($record as $field => $value) {
        $issuer->set($field, $value);
    }
    $issuer->update();
    echo "Updated issuer: {$issuername}\n";
} else {
    $issuer = new \core\oauth2\issuer(0, $record);
    $issuer->create();
    echo "Created issuer: {$issuername}\n";
}

\core\oauth2\service\custom::create_endpoints($issuer);

foreach ($mappings as $mappingrecord) {
    $external = $mappingrecord['external'] ?? '';
    $internal = $mappingrecord['internal'] ?? '';
    if ($external === '' || $internal === '') {
        fwrite(STDERR, "Invalid Moodle OAuth2 field mapping.\n");
        exit(1);
    }

    $mapping = \core\oauth2\user_field_mapping::get_record([
        'issuerid' => $issuer->get('id'),
        'internalfield' => $internal,
    ]);
    if ($mapping) {
        $mapping->set('externalfield', $external);
        $mapping->update();
    } else {
        $mapping = new \core\oauth2\user_field_mapping(0, (object)[
            'issuerid' => $issuer->get('id'),
            'externalfield' => $external,
            'internalfield' => $internal,
        ]);
        $mapping->create();
    }
}

$auths = array_values(array_filter(explode(',', get_config('core', 'auth') ?: '')));
if (!in_array('oauth2', $auths, true)) {
    $auths[] = 'oauth2';
    set_config('auth', implode(',', $auths));
}

set_config('authpreventaccountcreation', $allowaccountcreation ? 0 : 1);
purge_all_caches();

echo "OAuth2 auth enabled.\n";
echo "OAuth2 account creation " . ($allowaccountcreation ? "allowed" : "blocked") . ".\n";
PHP

    ok "Moodle OAuth2 issuer configured."
}

verify_oidc() {
    section "Verify Moodle OAuth2 issuer"

    moodle_php <<'PHP'
<?php
define('CLI_SCRIPT', true);
require_once('/var/www/html/config.php');
require_once($CFG->libdir . '/filelib.php');

$failures = 0;
$issuerurl = rtrim(getenv('MOODLE_OAUTH2_ISSUER_URL') ?: '', '/');
$clientid = getenv('MOODLE_OAUTH2_CLIENT_ID') ?: '';
$issuername = getenv('MOODLE_OAUTH2_ISSUER_NAME') ?: 'Keycloak';
$scopes = getenv('MOODLE_OAUTH2_SCOPES') ?: 'openid profile email';
$alloweddomains = getenv('MOODLE_OAUTH2_ALLOWED_DOMAINS') ?: '';
$requireconfirmation = (int)(getenv('MOODLE_OAUTH2_REQUIRE_CONFIRMATION') ?: 0);
$allowaccountcreation = (int)(getenv('MOODLE_OAUTH2_ALLOW_ACCOUNT_CREATION') ?: 1);
$mappingsjson = getenv('MOODLE_OAUTH2_FIELD_MAPPINGS_JSON') ?: '[]';
$expectedmappings = json_decode($mappingsjson, true);

$pass = function(string $message) {
    echo "  PASS  {$message}\n";
};
$fail = function(string $message) use (&$failures) {
    $failures++;
    echo "  FAIL  {$message}\n";
};

if (!is_array($expectedmappings) || count($expectedmappings) === 0) {
    $fail('Moodle OAuth2 field mapping config is invalid');
    exit($failures);
}

$discoveryurl = $issuerurl . '/.well-known/openid-configuration';
$discoveryjson = @file_get_contents($discoveryurl);
if ($discoveryjson !== false && json_decode($discoveryjson) !== null) {
    $pass("Moodle can read Keycloak discovery");
} else {
    $fail("Moodle cannot read Keycloak discovery: {$discoveryurl}");
}

$auths = array_values(array_filter(explode(',', get_config('core', 'auth') ?: '')));
in_array('oauth2', $auths, true) ? $pass('auth_oauth2 is enabled') : $fail('auth_oauth2 is not enabled');

$accountcreation = (int)(get_config('core', 'authpreventaccountcreation') ?: 0);
if ($allowaccountcreation && $accountcreation === 0) {
    $pass('OAuth2 account creation is allowed');
} else if (!$allowaccountcreation && $accountcreation === 1) {
    $pass('OAuth2 account creation is blocked');
} else {
    $fail('OAuth2 account creation setting does not match .env');
}

$issuer = \core\oauth2\issuer::get_record([
    'baseurl' => $issuerurl,
    'clientid' => $clientid,
]);
if (!$issuer) {
    $fail("Issuer missing for {$issuerurl}");
    exit($failures);
}

$pass("Issuer exists: {$issuername}");
$issuer->get('enabled') ? $pass('Issuer is enabled') : $fail('Issuer is disabled');
$issuer->get('showonloginpage') != \core\oauth2\issuer::SERVICEONLY ? $pass('Issuer is available on login page') : $fail('Issuer is not available on login page');
$issuer->get('clientid') === $clientid ? $pass('Client ID matches') : $fail('Client ID mismatch');
$issuer->get('loginscopes') === $scopes ? $pass('Login scopes match') : $fail('Login scopes mismatch');
$issuer->get('alloweddomains') === $alloweddomains ? $pass('Allowed domains match') : $fail('Allowed domains mismatch');
(int)$issuer->get('requireconfirmation') === ($requireconfirmation ? 1 : 0) ? $pass('Confirmation setting matches') : $fail('Confirmation setting mismatch');

foreach (['authorization', 'token', 'userinfo', 'discovery'] as $endpoint) {
    $issuer->get_endpoint_url($endpoint) ? $pass("Endpoint exists: {$endpoint}") : $fail("Endpoint missing: {$endpoint}");
}

foreach ($expectedmappings as $mappingrecord) {
    $external = $mappingrecord['external'] ?? '';
    $internal = $mappingrecord['internal'] ?? '';
    $mapping = \core\oauth2\user_field_mapping::get_record([
        'issuerid' => $issuer->get('id'),
        'internalfield' => $internal,
    ]);
    if ($mapping && $mapping->get('externalfield') === $external) {
        $pass("Mapping exists: {$external} -> {$internal}");
    } else {
        $fail("Mapping missing: {$external} -> {$internal}");
    }
}

exit($failures);
PHP

    ok "Moodle OAuth2 issuer verification passed."
}

main() {
    local command="${1:-}"

    case "${command}" in
        apply)
            require_repo_root
            require_env_file
            require_data_files
            require_commands
            validate_data
            load_env
            apply_oidc
            ;;
        verify)
            require_repo_root
            require_env_file
            require_data_files
            require_commands
            validate_data
            load_env
            verify_oidc
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
