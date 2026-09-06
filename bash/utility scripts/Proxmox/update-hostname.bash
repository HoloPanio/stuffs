#!/usr/bin/env bash
# Written by HoloPanio (https://github.com/HoloPanio)
#
# Updates a standalone Proxmox VE node hostname by rewriting
# /etc/hostname and /etc/hosts, then reporting any local references
# that may still need review before rebooting.

set -euo pipefail

HOSTNAME_FILE="/etc/hostname"
HOSTS_FILE="/etc/hosts"
POSTFIX_FILE="/etc/postfix/main.cf"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"

usage() {
    cat <<'EOF'
Usage: update-hostname.bash <new-short-hostname> <new-fqdn> <management-ip>

Example:
  sudo bash update-hostname.bash pve01 pve01.lab.example 192.168.10.10

This script is only for standalone Proxmox VE nodes.
Do not use it on a node that belongs to a Proxmox cluster.
EOF
}

backup_file() {
    local file_path="$1"

    if [[ -e "${file_path}" ]]; then
        cp -a -- "${file_path}" "${file_path}.bak.${BACKUP_SUFFIX}"
        echo "Backup created: ${file_path}.bak.${BACKUP_SUFFIX}"
    fi
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "Error: Run this script as root (for example: sudo bash $0 ...)." >&2
        exit 1
    fi
}

require_standalone_node() {
    local cluster_output

    if [[ -f "/etc/pve/corosync.conf" ]]; then
        echo "Error: /etc/pve/corosync.conf exists. This node appears to be clustered." >&2
        echo "Proxmox does not support renaming a node after cluster creation." >&2
        exit 1
    fi

    cluster_output="$(pvecm status 2>&1 || true)"
    if grep -qiE 'Quorate|Votequorum|Nodes:[[:space:]]+[0-9]+|Node ID:' <<<"${cluster_output}"; then
        echo "Error: pvecm status indicates this node is part of a cluster." >&2
        echo "Proxmox does not support renaming a node after cluster creation." >&2
        exit 1
    fi
}

if [[ "$#" -ne 3 ]]; then
    usage
    exit 1
fi

NEW_SHORT_HOSTNAME="$1"
NEW_FQDN="$2"
MANAGEMENT_IP="$3"

if [[ ! "${NEW_SHORT_HOSTNAME}" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
    echo "Error: New short hostname must contain only letters, numbers, or dashes." >&2
    exit 1
fi

if [[ ! "${NEW_FQDN}" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9-]+$ ]]; then
    echo "Error: New FQDN must look like a fully qualified domain name." >&2
    exit 1
fi

if [[ ! "${MANAGEMENT_IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Error: Management IP must be an IPv4 address." >&2
    exit 1
fi

require_root
require_standalone_node

CURRENT_SHORT_HOSTNAME="$(hostname)"
CURRENT_FQDN="$(hostname -f 2>/dev/null || hostname)"

echo "Current short hostname: ${CURRENT_SHORT_HOSTNAME}"
echo "Current FQDN: ${CURRENT_FQDN}"
echo "New short hostname: ${NEW_SHORT_HOSTNAME}"
echo "New FQDN: ${NEW_FQDN}"
echo "Management IP: ${MANAGEMENT_IP}"

backup_file "${HOSTNAME_FILE}"
backup_file "${HOSTS_FILE}"

printf '%s\n' "${NEW_SHORT_HOSTNAME}" > "${HOSTNAME_FILE}"
chmod 0644 "${HOSTNAME_FILE}"
hostnamectl set-hostname "${NEW_SHORT_HOSTNAME}"

TMP_HOSTS_FILE="$(mktemp)"
trap 'rm -f "${TMP_HOSTS_FILE}" "${TMP_POSTFIX_FILE:-}"' EXIT

awk \
    -v current_short="${CURRENT_SHORT_HOSTNAME}" \
    -v current_fqdn="${CURRENT_FQDN}" \
    -v new_short="${NEW_SHORT_HOSTNAME}" \
    -v new_fqdn="${NEW_FQDN}" \
    -v management_ip="${MANAGEMENT_IP}" \
    '
    function line_has_hostname(   i) {
        for (i = 2; i <= NF; i++) {
            if ($i == current_short || $i == current_fqdn || $i == new_short || $i == new_fqdn) {
                return 1
            }
        }
        return 0
    }

    {
        if (NF == 0 || $1 ~ /^#/) {
            print
            next
        }

        if ($1 == management_ip) {
            next
        }

        if (line_has_hostname()) {
            next
        }

        print
    }

    END {
        print ""
        print management_ip " " new_fqdn " " new_short
    }
    ' "${HOSTS_FILE}" > "${TMP_HOSTS_FILE}"

cp -- "${TMP_HOSTS_FILE}" "${HOSTS_FILE}"
chmod 0644 "${HOSTS_FILE}"

POSTFIX_UPDATED="no"
if [[ -f "${POSTFIX_FILE}" ]] && grep -Eq '^[[:space:]]*myhostname[[:space:]]*=' "${POSTFIX_FILE}"; then
    backup_file "${POSTFIX_FILE}"
    TMP_POSTFIX_FILE="$(mktemp)"

    awk -v new_fqdn="${NEW_FQDN}" '
        /^[[:space:]]*myhostname[[:space:]]*=/ {
            print "myhostname = " new_fqdn
            next
        }

        {
            print
        }
    ' "${POSTFIX_FILE}" > "${TMP_POSTFIX_FILE}"

    cp -- "${TMP_POSTFIX_FILE}" "${POSTFIX_FILE}"
    chmod 0644 "${POSTFIX_FILE}"

    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files postfix.service >/dev/null 2>&1; then
        systemctl restart postfix
    fi

    POSTFIX_UPDATED="yes"
fi

SHORT_LOOKUP="$(getent hosts "${NEW_SHORT_HOSTNAME}" || true)"
FQDN_LOOKUP="$(getent hosts "${NEW_FQDN}" || true)"

echo
echo "Validation results:"
if grep -q "${MANAGEMENT_IP}" <<<"${SHORT_LOOKUP}"; then
    echo "- ${NEW_SHORT_HOSTNAME} resolves to ${MANAGEMENT_IP}"
else
    echo "- Warning: ${NEW_SHORT_HOSTNAME} did not resolve to ${MANAGEMENT_IP} yet"
fi

if grep -q "${MANAGEMENT_IP}" <<<"${FQDN_LOOKUP}"; then
    echo "- ${NEW_FQDN} resolves to ${MANAGEMENT_IP}"
else
    echo "- Warning: ${NEW_FQDN} did not resolve to ${MANAGEMENT_IP} yet"
fi

echo
echo "Searching for old hostname references in common config paths:"
grep -RFn -e "${CURRENT_SHORT_HOSTNAME}" -e "${CURRENT_FQDN}" /etc/pve /etc/postfix /etc 2>/dev/null || true

echo
echo "Updated ${HOSTNAME_FILE} and ${HOSTS_FILE}."
if [[ "${POSTFIX_UPDATED}" == "yes" ]]; then
    echo "Updated ${POSTFIX_FILE} and restarted postfix."
else
    echo "Postfix myhostname was not changed automatically. Review ${POSTFIX_FILE} if needed."
fi
echo "Review any remaining hostname references, then reboot the node."
echo "After reboot, reconnect with: https://${MANAGEMENT_IP}:8006"
echo "If the new FQDN shows a certificate warning later, run: pvecm updatecerts -f && systemctl restart pveproxy pvedaemon"