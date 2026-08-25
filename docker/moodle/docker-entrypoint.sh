#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /var/www/html/version.php ]]; then
    cp -a /usr/src/moodle/. /var/www/html/
fi

mkdir -p /var/moodledata
chown -R www-data:www-data /var/moodledata /var/www/html

exec "$@"

