#!/usr/bin/env bash
# Generate Nginx virtual host configs from .env-driven templates.

set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
TEMPLATE_ROOT="docker/nginx/templates"
GENERATED_ROOT=".generated/nginx"
DEFAULT_CERT_NAME="1upmoodleserve"

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    CYAN=''
    BOLD=''
    NC=''
fi

ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; }
die() { fail "$*"; exit 1; }

usage() {
    cat <<'EOF'
Usage:
  bash scripts/nginx-config.sh generate http
  bash scripts/nginx-config.sh generate https
  bash scripts/nginx-config.sh path http
  bash scripts/nginx-config.sh path https

Generates .generated/nginx/<mode>.d from docker/nginx/templates/<mode>.d.
EOF
}

require_repo_root() {
    [[ -f docker-compose.yml ]] || die "Run this script from the project root."
    [[ -d "${TEMPLATE_ROOT}" ]] || die "Missing ${TEMPLATE_ROOT}."
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
    ROOT_DOMAIN="$(env_get ROOT_DOMAIN)"
    MOODLE_DOMAIN="$(env_get MOODLE_DOMAIN)"
    KEYCLOAK_DOMAIN="$(env_get KEYCLOAK_DOMAIN)"
    LETSENCRYPT_CERT_NAME="$(env_get LETSENCRYPT_CERT_NAME "${DEFAULT_CERT_NAME}")"

    [[ -n "${ROOT_DOMAIN}" ]] || die "ROOT_DOMAIN is missing in ${ENV_FILE}."
    [[ -n "${MOODLE_DOMAIN}" ]] || die "MOODLE_DOMAIN is missing in ${ENV_FILE}."
    [[ -n "${KEYCLOAK_DOMAIN}" ]] || die "KEYCLOAK_DOMAIN is missing in ${ENV_FILE}."
    [[ -n "${LETSENCRYPT_CERT_NAME}" ]] || die "LETSENCRYPT_CERT_NAME is missing in ${ENV_FILE}."
}

generated_path() {
    local mode="$1"
    printf '%s/%s.d\n' "${GENERATED_ROOT}" "${mode}"
}

render_template() {
    local template="$1"
    local output="$2"

    awk \
        -v root_domain="${ROOT_DOMAIN}" \
        -v moodle_domain="${MOODLE_DOMAIN}" \
        -v keycloak_domain="${KEYCLOAK_DOMAIN}" \
        -v cert_name="${LETSENCRYPT_CERT_NAME}" '
            {
                gsub(/%%ROOT_DOMAIN%%/, root_domain)
                gsub(/%%MOODLE_DOMAIN%%/, moodle_domain)
                gsub(/%%KEYCLOAK_DOMAIN%%/, keycloak_domain)
                gsub(/%%LETSENCRYPT_CERT_NAME%%/, cert_name)
                print
            }
        ' "${template}" > "${output}"
}

generate_mode() {
    local mode="$1"
    local source_dir="${TEMPLATE_ROOT}/${mode}.d"
    local target_dir
    local template
    local basename

    [[ "${mode}" == "http" || "${mode}" == "https" ]] || die "Mode must be http or https."
    [[ -d "${source_dir}" ]] || die "Missing template directory: ${source_dir}"

    target_dir="$(generated_path "${mode}")"
    mkdir -p "${target_dir}"

    for template in "${source_dir}"/*.template; do
        [[ -f "${template}" ]] || die "No templates found in ${source_dir}."
        basename="$(basename "${template}" .template)"
        render_template "${template}" "${target_dir}/${basename}"
    done

    ok "Generated Nginx ${mode} config: ${target_dir}"
}

main() {
    local command="${1:-}"
    local mode="${2:-}"

    case "${command}" in
        generate)
            require_repo_root
            require_env_file
            load_env
            generate_mode "${mode}"
            ;;
        path)
            [[ "${mode}" == "http" || "${mode}" == "https" ]] || die "Mode must be http or https."
            generated_path "${mode}"
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
