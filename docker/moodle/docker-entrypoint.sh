#!/usr/bin/env bash
set -euo pipefail

required_env() {
    local name="$1"

    if [[ -z "${!name:-}" ]]; then
        echo "Missing required environment variable: ${name}" >&2
        exit 1
    fi
}

write_moodle_config() {
    required_env MOODLE_DB_HOST
    required_env MOODLE_DB_NAME
    required_env MOODLE_DB_USER
    required_env MOODLE_DB_PASSWORD
    required_env MOODLE_WWWROOT

    php <<'PHP'
<?php
$required = [
    'MOODLE_DB_HOST',
    'MOODLE_DB_NAME',
    'MOODLE_DB_USER',
    'MOODLE_DB_PASSWORD',
    'MOODLE_WWWROOT',
];

foreach ($required as $name) {
    if (getenv($name) === false || getenv($name) === '') {
        fwrite(STDERR, "Missing required environment variable: {$name}\n");
        exit(1);
    }
}

$wwwroot = rtrim(getenv('MOODLE_WWWROOT'), '/');
$sslproxy = str_starts_with($wwwroot, 'https://') ? 'true' : 'false';

$config = <<<'PHP_CONFIG'
<?php
unset($CFG);
global $CFG;
$CFG = new stdClass();

$CFG->dbtype    = 'pgsql';
$CFG->dblibrary = 'native';
$CFG->dbhost    = %%MOODLE_DB_HOST%%;
$CFG->dbname    = %%MOODLE_DB_NAME%%;
$CFG->dbuser    = %%MOODLE_DB_USER%%;
$CFG->dbpass    = %%MOODLE_DB_PASSWORD%%;
$CFG->prefix    = 'mdl_';
$CFG->dboptions = [
    'dbpersist' => false,
    'dbsocket' => false,
    'dbport' => '',
];

$CFG->wwwroot   = %%MOODLE_WWWROOT%%;
$CFG->dataroot  = '/var/moodledata';
$CFG->directorypermissions = 02777;
$CFG->admin = 'admin';
$CFG->reverseproxy = true;
$CFG->sslproxy = %%MOODLE_SSLPROXY%%;
$CFG->routerconfigured = false;

require_once(__DIR__ . '/lib/setup.php');
PHP_CONFIG;

$replacements = [
    '%%MOODLE_DB_HOST%%' => var_export(getenv('MOODLE_DB_HOST'), true),
    '%%MOODLE_DB_NAME%%' => var_export(getenv('MOODLE_DB_NAME'), true),
    '%%MOODLE_DB_USER%%' => var_export(getenv('MOODLE_DB_USER'), true),
    '%%MOODLE_DB_PASSWORD%%' => var_export(getenv('MOODLE_DB_PASSWORD'), true),
    '%%MOODLE_WWWROOT%%' => var_export($wwwroot, true),
    '%%MOODLE_SSLPROXY%%' => $sslproxy,
];

file_put_contents('/var/www/html/config.php', strtr($config, $replacements));
PHP
}

wait_for_moodle_database() {
    local attempt

    for attempt in {1..60}; do
        if php <<'PHP'
<?php
try {
    $dsn = sprintf('pgsql:host=%s;dbname=%s', getenv('MOODLE_DB_HOST'), getenv('MOODLE_DB_NAME'));
    new PDO($dsn, getenv('MOODLE_DB_USER'), getenv('MOODLE_DB_PASSWORD'), [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
    exit(0);
} catch (Throwable $e) {
    fwrite(STDERR, $e->getMessage() . "\n");
    exit(1);
}
PHP
        then
            return 0
        fi

        sleep 2
    done

    echo "Timed out waiting for Moodle database." >&2
    exit 1
}

moodle_database_has_tables() {
    php <<'PHP'
<?php
try {
    $dsn = sprintf('pgsql:host=%s;dbname=%s', getenv('MOODLE_DB_HOST'), getenv('MOODLE_DB_NAME'));
    $pdo = new PDO($dsn, getenv('MOODLE_DB_USER'), getenv('MOODLE_DB_PASSWORD'), [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
    $statement = $pdo->query(
        "select count(*) from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE'"
    );
    exit(((int) $statement->fetchColumn()) > 0 ? 0 : 1);
} catch (Throwable $e) {
    fwrite(STDERR, $e->getMessage() . "\n");
    exit(2);
}
PHP
}

install_moodle_if_needed() {
    required_env MOODLE_ADMIN_USER
    required_env MOODLE_ADMIN_PASSWORD
    required_env MOODLE_ADMIN_EMAIL
    required_env MOODLE_FULLNAME
    required_env MOODLE_SHORTNAME

    wait_for_moodle_database

    if moodle_database_has_tables; then
        echo "Moodle database already has tables; skipping initial install."
        return 0
    fi

    php /var/www/html/admin/cli/install_database.php \
        --agree-license \
        --adminuser="${MOODLE_ADMIN_USER}" \
        --adminpass="${MOODLE_ADMIN_PASSWORD}" \
        --adminemail="${MOODLE_ADMIN_EMAIL}" \
        --fullname="${MOODLE_FULLNAME}" \
        --shortname="${MOODLE_SHORTNAME}" \
        --supportemail="${MOODLE_ADMIN_EMAIL}" \
        --noreplyemail="${MOODLE_ADMIN_EMAIL}"
}

if [[ ! -f /var/www/html/version.php ]]; then
    cp -a /usr/src/moodle/. /var/www/html/
fi

mkdir -p /var/moodledata
if [[ ! -f /var/www/html/config.php ]]; then
    write_moodle_config
fi

install_moodle_if_needed
chown -R www-data:www-data /var/moodledata /var/www/html

exec "$@"
