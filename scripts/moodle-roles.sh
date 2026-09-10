#!/usr/bin/env bash
# Apply Moodle user role state from data/keycloak-users.json.

set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
KEYCLOAK_USERS_FILE="${KEYCLOAK_USERS_FILE:-data/keycloak-users.json}"
KEYCLOAK_REALM_FILE="${KEYCLOAK_REALM_FILE:-data/keycloak-realm.json}"

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
  bash scripts/moodle-roles.sh apply
  bash scripts/moodle-roles.sh verify

Creates/updates Moodle user shells from data/keycloak-users.json and makes
users with moodleRole=admin Moodle site admins.
EOF
}

require_repo_root() {
    [[ -f docker-compose.yml ]] || die "Run this script from the project root."
}

require_env_file() {
    [[ -f "${ENV_FILE}" ]] || die "Missing ${ENV_FILE}. Create it on the VPS first."
}

require_data_files() {
    [[ -f "${KEYCLOAK_USERS_FILE}" ]] || die "Missing ${KEYCLOAK_USERS_FILE}."
    [[ -f "${KEYCLOAK_REALM_FILE}" ]] || die "Missing ${KEYCLOAK_REALM_FILE}."
}

require_commands() {
    command -v jq >/dev/null 2>&1 || die "jq command not found."
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

load_env() {
    KEYCLOAK_SEED_EMAIL_DOMAIN="$(env_get KEYCLOAK_SEED_EMAIL_DOMAIN "$(json_get "${KEYCLOAK_REALM_FILE}" '.seed.emailDomain')")"
    USERS_JSON="$(jq -c '.users' "${KEYCLOAK_USERS_FILE}")"

    [[ -n "${KEYCLOAK_SEED_EMAIL_DOMAIN}" ]] || die "KEYCLOAK_SEED_EMAIL_DOMAIN is required."
}

validate_data() {
    jq -e '
        (.users | type == "array" and length > 0) and
        all(.users[]; (.username | type == "string" and length > 0) and
                      (.firstName | type == "string" and length > 0) and
                      (.lastName | type == "string" and length > 0) and
                      (.universityRole | type == "string" and length > 0)) and
        (([.users[].username] | length) == ([.users[].username] | unique | length))
    ' "${KEYCLOAK_USERS_FILE}" >/dev/null || die "Invalid ${KEYCLOAK_USERS_FILE}."
}

compose() {
    docker compose --env-file "${ENV_FILE}" "$@"
}

wait_for_moodle() {
    section "Wait for Moodle"

    local attempt

    for attempt in $(seq 1 60); do
        if compose exec -T moodle php -r 'define("CLI_SCRIPT", true); require_once("/var/www/html/config.php"); echo "ok\n";' >/dev/null 2>&1; then
            ok "Moodle is ready."
            return
        fi

        sleep 5
    done

    die "Moodle did not become ready."
}

moodle_php() {
    compose exec -T \
        -e KEYCLOAK_SEED_EMAIL_DOMAIN="${KEYCLOAK_SEED_EMAIL_DOMAIN}" \
        -e MOODLE_USERS_JSON="${USERS_JSON}" \
        moodle php
}

apply_roles() {
    section "Apply Moodle roles"

    moodle_php <<'PHP'
<?php
define('CLI_SCRIPT', true);
require_once('/var/www/html/config.php');
require_once($CFG->dirroot . '/user/lib.php');

global $CFG, $DB;

$users = json_decode(getenv('MOODLE_USERS_JSON') ?: '[]', true);
$emaildomain = getenv('KEYCLOAK_SEED_EMAIL_DOMAIN') ?: '';

if (!is_array($users) || count($users) === 0 || $emaildomain === '') {
    fwrite(STDERR, "Missing Moodle role input.\n");
    exit(1);
}

$created = 0;
$updated = 0;
$adminids = [];

foreach ($users as $row) {
    $username = strtolower($row['username'] ?? '');
    $firstname = $row['firstName'] ?? '';
    $lastname = $row['lastName'] ?? '';
    $moodlerole = $row['moodleRole'] ?? '';

    if ($username === '' || $firstname === '' || $lastname === '') {
        fwrite(STDERR, "Invalid user row.\n");
        exit(1);
    }

    $email = $username . '@' . $emaildomain;
    $existing = $DB->get_record('user', [
        'username' => $username,
        'mnethostid' => $CFG->mnet_localhost_id,
        'deleted' => 0,
    ]);

    if ($existing) {
        $existing->firstname = $firstname;
        $existing->lastname = $lastname;
        $existing->email = $email;
        $existing->confirmed = 1;
        if ($existing->auth !== 'manual') {
            $existing->auth = 'oauth2';
            $existing->password = AUTH_PASSWORD_NOT_CACHED;
        }
        user_update_user($existing, false, false);
        $userid = (int)$existing->id;
        $updated++;
    } else {
        $newuser = (object)[
            'auth' => 'oauth2',
            'confirmed' => 1,
            'mnethostid' => $CFG->mnet_localhost_id,
            'username' => $username,
            'password' => AUTH_PASSWORD_NOT_CACHED,
            'firstname' => $firstname,
            'lastname' => $lastname,
            'email' => $email,
        ];
        $userid = user_create_user($newuser, false, false);
        $created++;
    }

    if ($moodlerole === 'admin') {
        $adminids[] = $userid;
    }
}

$current = array_filter(explode(',', (string)get_config('core', 'siteadmins')), 'strlen');
$merged = array_values(array_unique(array_merge($current, array_map('strval', $adminids))));
set_config('siteadmins', implode(',', $merged));
purge_all_caches();

echo "Created Moodle users: {$created}\n";
echo "Updated Moodle users: {$updated}\n";
echo "Moodle site admins from desired state: " . count($adminids) . "\n";
PHP

    ok "Moodle roles applied."
}

verify_roles() {
    section "Verify Moodle roles"

    moodle_php <<'PHP'
<?php
define('CLI_SCRIPT', true);
require_once('/var/www/html/config.php');

global $CFG, $DB;

$users = json_decode(getenv('MOODLE_USERS_JSON') ?: '[]', true);
$emaildomain = getenv('KEYCLOAK_SEED_EMAIL_DOMAIN') ?: '';
$failures = 0;

$siteadmins = array_filter(explode(',', (string)get_config('core', 'siteadmins')), 'strlen');
$siteadminset = array_flip($siteadmins);

foreach ($users as $row) {
    $username = strtolower($row['username'] ?? '');
    $moodlerole = $row['moodleRole'] ?? '';
    $user = $DB->get_record('user', [
        'username' => $username,
        'mnethostid' => $CFG->mnet_localhost_id,
        'deleted' => 0,
    ]);

    if (!$user) {
        echo "FAIL User missing in Moodle: {$username}\n";
        $failures++;
        continue;
    }

    $expectedemail = $username . '@' . $emaildomain;
    if ($user->email !== $expectedemail) {
        echo "FAIL Email mismatch: {$username}\n";
        $failures++;
    }

    if ($moodlerole === 'admin') {
        if (isset($siteadminset[(string)$user->id])) {
            echo "PASS Moodle site admin: {$username}\n";
        } else {
            echo "FAIL Moodle site admin missing: {$username}\n";
            $failures++;
        }
    }
}

exit($failures);
PHP

    ok "Moodle role verification passed."
}

load_and_validate() {
    require_repo_root
    require_env_file
    require_data_files
    require_commands
    validate_data
    load_env
    wait_for_moodle
}

main() {
    case "${1:-}" in
        apply)
            load_and_validate
            apply_roles
            ;;
        verify)
            load_and_validate
            verify_roles
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
