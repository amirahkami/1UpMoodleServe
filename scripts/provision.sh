#!/usr/bin/env bash
# Provision a fresh Ubuntu 24.04 VPS so it can run the 1UpMoodleServe
# Docker Compose deployment.

set -euo pipefail

APP_NAME="1upmoodleserve"
APP_DIR="/opt/${APP_NAME}"
DOCKER_GPG="/etc/apt/keyrings/docker.asc"
DOCKER_SOURCE="/etc/apt/sources.list.d/docker.sources"

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

require_root() {
    [[ "${EUID}" -eq 0 ]] || die "Run as root: sudo bash scripts/provision.sh"
}

require_ubuntu_2404() {
    [[ -f /etc/os-release ]] || die "Cannot detect operating system."
    # shellcheck source=/dev/null
    . /etc/os-release

    [[ "${ID:-}" == "ubuntu" ]] || die "Expected Ubuntu 24.04. Detected: ${PRETTY_NAME:-unknown}"
    [[ "${VERSION_ID:-}" == "24.04" ]] || die "Expected Ubuntu 24.04. Detected: ${PRETTY_NAME:-unknown}"

    ok "Detected ${PRETTY_NAME}"
}

apt_noninteractive() {
    DEBIAN_FRONTEND=noninteractive apt-get "$@" \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
}

update_system() {
    section "Update system packages"

    apt-get update
    apt_noninteractive upgrade -y
    apt_noninteractive autoremove -y
    apt-get autoclean

    ok "System packages updated."
}

install_base_tools() {
    section "Install base tools"

    local tools=(
        ca-certificates
        curl
        dnsutils
        git
        gnupg
        htop
        jq
        lsof
        nano
        ncdu
        openssl
        rsync
        tmux
        tree
        unzip
        wget
        zip
    )

    apt_noninteractive install -y "${tools[@]}"

    ok "Base tools installed."
}

remove_conflicting_docker_packages() {
    section "Remove conflicting Docker packages"

    local packages=(
        docker.io
        docker-compose
        docker-compose-v2
        docker-doc
        docker-buildx
        podman-docker
        containerd
        runc
    )

    apt_noninteractive remove -y "${packages[@]}" || true

    ok "Conflicting Docker packages removed or absent."
}

configure_docker_repository() {
    section "Configure official Docker apt repository"

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "${DOCKER_GPG}"
    chmod a+r "${DOCKER_GPG}"

    local codename
    local arch
    # shellcheck source=/dev/null
    . /etc/os-release
    codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    arch="$(dpkg --print-architecture)"

    [[ -n "${codename}" ]] || die "Could not determine Ubuntu codename."
    [[ -n "${arch}" ]] || die "Could not determine system architecture."

    cat > "${DOCKER_SOURCE}" <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: ${DOCKER_GPG}
EOF

    apt-get update

    ok "Docker apt repository configured for ${codename}/${arch}."
}

install_docker() {
    section "Install Docker Engine and Compose plugin"

    apt_noninteractive install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    ok "Docker Engine and Compose plugin installed."
}

prepare_app_directory() {
    section "Prepare deployment directory"

    install -d -m 0755 "${APP_DIR}"

    ok "Deployment directory ready: ${APP_DIR}"
}

verify_installation() {
    section "Verify provisioned state"

    command -v docker >/dev/null 2>&1 || die "docker command not found."
    docker compose version >/dev/null 2>&1 || die "docker compose plugin not available."
    systemctl is-active --quiet docker || die "docker service is not active."

    ok "Docker: $(docker --version)"
    ok "Compose: $(docker compose version)"
    ok "Docker service is active."
}

main() {
    echo ""
    echo -e "${BOLD}${CYAN}1UpMoodleServe VPS Provisioning${NC}"
    echo ""

    require_root
    require_ubuntu_2404
    update_system
    install_base_tools
    remove_conflicting_docker_packages
    configure_docker_repository
    install_docker
    prepare_app_directory
    verify_installation

    echo ""
    ok "Provisioning complete."
    info "Next step after repository setup: clone/pull the project into ${APP_DIR}."
}

main "$@"
