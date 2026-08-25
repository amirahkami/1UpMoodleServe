#!/usr/bin/env bash
set -euo pipefail

psql \
    -v ON_ERROR_STOP=1 \
    --username "${POSTGRES_USER}" \
    --set=moodle_db="${MOODLE_DB_NAME}" \
    --set=moodle_user="${MOODLE_DB_USER}" \
    --set=moodle_password="${MOODLE_DB_PASSWORD}" \
    --set=keycloak_db="${KEYCLOAK_DB_NAME}" \
    --set=keycloak_user="${KEYCLOAK_DB_USER}" \
    --set=keycloak_password="${KEYCLOAK_DB_PASSWORD}" <<'EOSQL'
CREATE USER :"moodle_user" WITH PASSWORD :'moodle_password';
CREATE DATABASE :"moodle_db" OWNER :"moodle_user" ENCODING 'UTF8' TEMPLATE template0;

CREATE USER :"keycloak_user" WITH PASSWORD :'keycloak_password';
CREATE DATABASE :"keycloak_db" OWNER :"keycloak_user" ENCODING 'UTF8' TEMPLATE template0;
EOSQL
