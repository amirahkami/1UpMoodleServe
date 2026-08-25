#!/usr/bin/env bash
# Host hardening for the 1UpMoodleServe VPS.
#
# Usage:
#   sudo bash scripts/harden.sh ssh-step1
#   sudo bash scripts/harden.sh ssh-step2
#   sudo bash scripts/harden.sh system

set -euo pipefail

SSH_USER="underroot"
SSH_PORT="44422"
SSHD_DROP_IN="/etc/ssh/sshd_config.d/01-1upmoodleserve.conf"
NFTABLES_CONF="/etc/nftables.conf"
FAIL2BAN_JAIL="/etc/fail2ban/jail.local"

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
    cat <<EOF
Usage:
  sudo bash scripts/harden.sh ssh-step1
  sudo bash scripts/harden.sh ssh-step2
  sudo bash scripts/harden.sh system

Subcommands:
  ssh-step1  Create/configure ${SSH_USER}, keep password SSH, move SSH to ${SSH_PORT}, keep root SSH temporarily.
  ssh-step2  Disable direct root SSH after ${SSH_USER} login on port ${SSH_PORT} has been verified.
  system     Apply host hardening: nftables, fail2ban, unattended security updates, sysctl, banner, /dev/shm.
EOF
}

require_root() {
    [[ "${EUID}" -eq 0 ]] || die "Run as root with sudo."
}

require_ubuntu_2404() {
    [[ -f /etc/os-release ]] || die "Cannot detect operating system."
    # shellcheck source=/dev/null
    . /etc/os-release

    [[ "${ID:-}" == "ubuntu" ]] || die "Expected Ubuntu 24.04. Detected: ${PRETTY_NAME:-unknown}"
    [[ "${VERSION_ID:-}" == "24.04" ]] || die "Expected Ubuntu 24.04. Detected: ${PRETTY_NAME:-unknown}"
}

apt_noninteractive() {
    DEBIAN_FRONTEND=noninteractive apt-get "$@" \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
}

confirm_exact() {
    local prompt="$1"
    local expected="$2"
    local answer

    read -r -p "${prompt} Type '${expected}' to continue: " answer
    [[ "${answer}" == "${expected}" ]] || die "Confirmation failed."
}

read_password_twice() {
    local first
    local second

    while true; do
        read -r -s -p "New password for ${SSH_USER}: " first
        echo ""
        read -r -s -p "Confirm password for ${SSH_USER}: " second
        echo ""

        [[ -n "${first}" ]] || { warn "Password cannot be empty."; continue; }
        [[ "${first}" == "${second}" ]] || { warn "Passwords do not match."; continue; }
        [[ "${#first}" -ge 16 ]] || { warn "Use at least 16 characters."; continue; }

        UNDERROOT_PASSWORD="${first}"
        break
    done
}

backup_ssh_config() {
    section "Back up SSH configuration"

    local stamp
    stamp="$(date +%Y%m%d%H%M%S)"

    cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.${stamp}"
    if [[ -d /etc/ssh/sshd_config.d ]]; then
        cp -a /etc/ssh/sshd_config.d "/etc/ssh/sshd_config.d.bak.${stamp}"
    fi

    ok "SSH configuration backed up."
}

restart_ssh_safely() {
    section "Validate and restart SSH"

    mkdir -p /run/sshd

    if ! /usr/sbin/sshd -t; then
        die "sshd configuration validation failed. SSH was not restarted."
    fi

    # Ubuntu 24.04 may use ssh.socket. Disable it so Port in sshd config applies.
    if systemctl is-active --quiet ssh.socket 2>/dev/null; then
        info "Disabling ssh.socket so ssh.service owns port ${SSH_PORT}."
        systemctl disable --now ssh.socket 2>/dev/null || true
        systemctl enable ssh.service 2>/dev/null || true
    fi

    systemctl restart ssh

    ok "SSH restarted."
}

ssh_step1() {
    section "SSH hardening step 1"
    info "This step creates/configures ${SSH_USER}, sets password auth, moves SSH to ${SSH_PORT}, and keeps root SSH temporarily."

    read_password_twice
    confirm_exact "Have you saved the new ${SSH_USER} password outside this repo?" "yes"

    backup_ssh_config

    section "Create or update ${SSH_USER}"
    if id "${SSH_USER}" >/dev/null 2>&1; then
        info "User ${SSH_USER} already exists."
    else
        adduser --gecos "" --disabled-password "${SSH_USER}"
        ok "Created user ${SSH_USER}."
    fi

    usermod -aG sudo "${SSH_USER}"
    echo "${SSH_USER}:${UNDERROOT_PASSWORD}" | chpasswd
    ok "Password set and sudo group granted for ${SSH_USER}."

    section "Write temporary SSH step-1 policy"
    install -d -m 0755 /etc/ssh/sshd_config.d
    rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf
    rm -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf

    cat > "${SSHD_DROP_IN}" <<EOF
# 1UpMoodleServe SSH policy - step 1
Port ${SSH_PORT}
PasswordAuthentication yes
PermitRootLogin yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 60
X11Forwarding no
AllowUsers root ${SSH_USER}
EOF

    restart_ssh_safely

    ok "SSH step 1 complete."
    warn "Before running ssh-step2, verify from a new terminal:"
    warn "  ssh -p ${SSH_PORT} ${SSH_USER}@<server-ip>"
}

ssh_step2() {
    section "SSH hardening step 2"
    warn "This step disables direct root SSH and allows only ${SSH_USER} on port ${SSH_PORT}."
    confirm_exact "Have you successfully logged in with: ssh -p ${SSH_PORT} ${SSH_USER}@138.68.64.183 ?" "yes"

    backup_ssh_config

    cat > "${SSHD_DROP_IN}" <<EOF
# 1UpMoodleServe SSH policy - step 2
Port ${SSH_PORT}
PasswordAuthentication yes
PermitRootLogin no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 60
X11Forwarding no
AllowUsers ${SSH_USER}
EOF

    restart_ssh_safely

    ok "SSH step 2 complete. Direct root SSH is disabled."
}

configure_unattended_upgrades() {
    section "Configure unattended security updates"

    apt-get update
    apt_noninteractive install -y unattended-upgrades apt-listchanges

    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    systemctl enable unattended-upgrades
    systemctl restart unattended-upgrades

    ok "Unattended security updates configured."
}

configure_sysctl() {
    section "Configure kernel/network hardening"

    cat > /etc/sysctl.d/70-1upmoodleserve-hardening.conf <<'EOF'
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.ip_forward = 0
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
EOF

    sysctl --system >/dev/null

    ok "Kernel/network hardening applied."
}

configure_shared_memory() {
    section "Harden /dev/shm"

    if grep -qE '^[^#].*\s/dev/shm\s' /etc/fstab; then
        if ! grep -E '^[^#].*\s/dev/shm\s' /etc/fstab | grep -q 'noexec'; then
            sed -i '/[[:space:]]\/dev\/shm[[:space:]]/ s/defaults/defaults,noexec,nosuid,nodev/' /etc/fstab
        fi
    else
        echo "tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0" >> /etc/fstab
    fi

    mount -o remount /dev/shm 2>/dev/null || warn "/dev/shm remount failed; reboot will apply fstab settings."

    ok "/dev/shm hardening configured."
}

configure_login_banner() {
    section "Configure login warning banner"

    cat > /etc/issue.net <<'EOF'
************************************************************
*  WARNING: Unauthorized access to this system is prohibited.
*  All connections are monitored and recorded. Disconnect
*  immediately if you are not an authorized user.
************************************************************
EOF

    sed -i '/^#\?Banner/d' /etc/ssh/sshd_config
    echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config

    restart_ssh_safely

    ok "Login banner configured."
}

configure_nftables() {
    section "Configure nftables firewall"

    apt_noninteractive install -y nftables
    systemctl enable nftables

    cat > "${NFTABLES_CONF}" <<EOF
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        iifname "lo" accept
        ct state established,related accept
        ct state invalid drop

        ip protocol icmp icmp type { echo-request, destination-unreachable, time-exceeded } limit rate 10/second accept

        tcp dport ${SSH_PORT} ct state new limit rate 10/minute accept
        tcp dport { 80, 443 } accept

        counter log prefix "nft-drop: " drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
        ct state invalid drop
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

    nft -c -f "${NFTABLES_CONF}"
    nft -f "${NFTABLES_CONF}"
    systemctl restart nftables

    ok "nftables configured: inbound ${SSH_PORT}, 80, and 443 allowed."
}

configure_fail2ban() {
    section "Configure fail2ban"

    apt_noninteractive install -y fail2ban

    cat > "${FAIL2BAN_JAIL}" <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
banaction = nftables-multiport

[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
backend = systemd
maxretry = 3
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban

    ok "fail2ban configured for SSH on port ${SSH_PORT}."
}

disable_unused_services() {
    section "Disable unused services"

    local services=(avahi-daemon cups cups-browsed)
    local packages=(avahi-daemon cups cups-browsed)

    for service in "${services[@]}"; do
        systemctl stop "${service}" 2>/dev/null || true
        systemctl disable "${service}" 2>/dev/null || true
    done

    apt_noninteractive purge -y "${packages[@]}" || true
    apt_noninteractive autoremove -y || true

    ok "Unused services removed or absent."
}

restrict_su() {
    section "Restrict su access"

    local pam_su="/etc/pam.d/su"
    local pam_line="auth       required   pam_wheel.so use_uid group=sudo"

    sed -i '/pam_wheel\.so/d' "${pam_su}"
    sed -i "/^auth[[:space:]]*sufficient[[:space:]]*pam_rootok.so/a ${pam_line}" "${pam_su}"

    ok "su restricted to sudo group members."
}

system_hardening() {
    warn "System hardening will configure nftables. SSH must already work on port ${SSH_PORT}."
    confirm_exact "Have you confirmed SSH access on port ${SSH_PORT}?" "yes"

    configure_unattended_upgrades
    configure_sysctl
    configure_shared_memory
    configure_login_banner
    configure_nftables
    configure_fail2ban
    disable_unused_services
    restrict_su

    ok "System hardening complete."
}

main() {
    local command="${1:-}"

    if [[ -z "${command}" || "${command}" == "--help" || "${command}" == "-h" ]]; then
        usage
        exit 0
    fi

    require_root
    require_ubuntu_2404

    case "${command}" in
        ssh-step1) ssh_step1 ;;
        ssh-step2) ssh_step2 ;;
        system) system_hardening ;;
        *) usage; die "Unknown subcommand: ${command}" ;;
    esac
}

main "$@"
