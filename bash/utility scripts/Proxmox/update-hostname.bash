#!/usr/bin/env bash
# Written by HoloPanio (https://github.com/HoloPanio)
#
# Updates a standalone Proxmox VE node hostname by rewriting
# /etc/hostname and /etc/hosts, then migrating guest configs from
# stale /etc/pve/nodes entries so a second run can repair an
# incomplete standalone-node rename.

set -euo pipefail

HOSTNAME_FILE="/etc/hostname"
HOSTS_FILE="/etc/hosts"
POSTFIX_FILE="/etc/postfix/main.cf"
PVE_DIR="/etc/pve"
PVE_NODES_DIR="${PVE_DIR}/nodes"
STORAGE_CFG_FILE="${PVE_DIR}/storage.cfg"
BACKUP_DIR="/root/proxmox-rename-backup"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"
BACKUP_CREATED="no"
HOSTNAME_UPDATED="no"
HOSTS_UPDATED="no"
POSTFIX_UPDATED="no"
POSTFIX_RESTARTED="no"
STORAGE_UPDATED="no"
PVE_GUEST_CONFIGS_MOVED="no"
PVE_SERVICES_RESTARTED="no"

usage() {
    cat <<'EOF'
Usage: update-hostname.bash <new-short-hostname> <new-fqdn> <management-ip>

Example:
  sudo bash update-hostname.bash pve01 pve01.lab.example 192.168.10.10

This script is only for standalone Proxmox VE nodes.
Do not use it on a node that belongs to a Proxmox cluster.
Running it again is safe and will attempt to repair stale
/etc/pve/nodes entries from an incomplete rename.
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

backup_proxmox_config() {
    if [[ -d "${PVE_DIR}" ]]; then
        mkdir -p -- "${BACKUP_DIR}"
        tar -czf "${BACKUP_DIR}/etc-pve-before-node-move-${BACKUP_SUFFIX}.tar.gz" "${PVE_DIR}"
        cp -a -- "${HOSTNAME_FILE}" "${BACKUP_DIR}/hostname.before.${BACKUP_SUFFIX}"
        cp -a -- "${HOSTS_FILE}" "${BACKUP_DIR}/hosts.before.${BACKUP_SUFFIX}"
        BACKUP_CREATED="yes"
        echo "Backup created: ${BACKUP_DIR}/etc-pve-before-node-move-${BACKUP_SUFFIX}.tar.gz"
    fi
}

node_dir_has_guest_configs() {
    local node_name="$1"

    if find "${PVE_NODES_DIR}/${node_name}" \( -path '*/qemu-server/*.conf' -o -path '*/lxc/*.conf' \) -type f -print -quit 2>/dev/null | grep -q .; then
        return 0
    fi

    return 1
}

resolve_old_node_name() {
    local node_name
    local candidate=""
    local guest_dir_count=0

    OLD_NODE_NAME=""

    if [[ ! -d "${PVE_NODES_DIR}" ]]; then
        return 0
    fi

    if [[ "${CURRENT_SHORT_HOSTNAME}" != "${NEW_SHORT_HOSTNAME}" ]] && [[ -d "${PVE_NODES_DIR}/${CURRENT_SHORT_HOSTNAME}" ]]; then
        OLD_NODE_NAME="${CURRENT_SHORT_HOSTNAME}"
        return 0
    fi

    while IFS= read -r node_name; do
        if [[ "${node_name}" == "${NEW_SHORT_HOSTNAME}" ]]; then
            continue
        fi

        if [[ -z "${OLD_NODE_NAME}" ]]; then
            OLD_NODE_NAME="${node_name}"
        else
            OLD_NODE_NAME=""
        fi

        if node_dir_has_guest_configs "${node_name}"; then
            candidate="${node_name}"
            guest_dir_count=$((guest_dir_count + 1))
        fi
    done < <(find "${PVE_NODES_DIR}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

    if [[ "${guest_dir_count}" -eq 1 ]]; then
        OLD_NODE_NAME="${candidate}"
    elif [[ "${guest_dir_count}" -gt 1 ]]; then
        echo "Error: Multiple stale Proxmox node directories contain guest configs." >&2
        echo "Review ${PVE_NODES_DIR} manually before retrying." >&2
        exit 1
    fi
}

ensure_new_node_dirs() {
    if [[ -d "${PVE_NODES_DIR}" ]]; then
        mkdir -p -- "${PVE_NODES_DIR}/${NEW_SHORT_HOSTNAME}/qemu-server"
        mkdir -p -- "${PVE_NODES_DIR}/${NEW_SHORT_HOSTNAME}/lxc"
    fi
}

move_guest_configs() {
    local guest_type="$1"
    local source_dir="$2"
    local target_dir="${PVE_NODES_DIR}/${NEW_SHORT_HOSTNAME}/${guest_type}"
    local moved_any="no"
    local config_file

    if [[ ! -d "${source_dir}" ]]; then
        return 0
    fi

    while IFS= read -r -d '' config_file; do
        mv -v -- "${config_file}" "${target_dir}/"
        moved_any="yes"
        PVE_GUEST_CONFIGS_MOVED="yes"
    done < <(find "${source_dir}" -maxdepth 1 -type f -name '*.conf' -print0)

    if [[ "${moved_any}" == "yes" ]]; then
        echo "Moved ${guest_type} configs into ${target_dir}"
    fi
}

migrate_proxmox_node_configs() {
    if [[ ! -d "${PVE_NODES_DIR}" ]]; then
        return 0
    fi

    resolve_old_node_name
    ensure_new_node_dirs

    if [[ -z "${OLD_NODE_NAME}" ]] || [[ "${OLD_NODE_NAME}" == "${NEW_SHORT_HOSTNAME}" ]]; then
        echo "No stale Proxmox node directory needed migration."
        return 0
    fi

    echo "Migrating guest configs from ${OLD_NODE_NAME} to ${NEW_SHORT_HOSTNAME}."
    move_guest_configs "qemu-server" "${PVE_NODES_DIR}/${OLD_NODE_NAME}/qemu-server"
    move_guest_configs "lxc" "${PVE_NODES_DIR}/${OLD_NODE_NAME}/lxc"
}

update_storage_cfg() {
    if [[ -z "${OLD_NODE_NAME}" ]] || [[ ! -f "${STORAGE_CFG_FILE}" ]]; then
        return 0
    fi

    if ! grep -Eq "^[[:space:]]*nodes[[:space:]].*${OLD_NODE_NAME}" "${STORAGE_CFG_FILE}"; then
        return 0
    fi

    backup_file "${STORAGE_CFG_FILE}"

    TMP_STORAGE_CFG_FILE="$(mktemp)"

    awk -v old_node="${OLD_NODE_NAME}" -v new_node="${NEW_SHORT_HOSTNAME}" '
        BEGIN {
            OFS = " "
        }

        /^[[:space:]]*nodes[[:space:]]+/ {
            for (i = 2; i <= NF; i++) {
                count = split($i, parts, ",")
                for (j = 1; j <= count; j++) {
                    if (parts[j] == old_node) {
                        parts[j] = new_node
                    }
                }

                $i = parts[1]
                for (j = 2; j <= count; j++) {
                    $i = $i "," parts[j]
                }
            }
        }

        {
            print
        }
    ' "${STORAGE_CFG_FILE}" > "${TMP_STORAGE_CFG_FILE}"

    cp -- "${TMP_STORAGE_CFG_FILE}" "${STORAGE_CFG_FILE}"
    chmod 0644 "${STORAGE_CFG_FILE}"
    STORAGE_UPDATED="yes"
    echo "Updated node restrictions in ${STORAGE_CFG_FILE}."
}

restart_proxmox_services() {
    local service_name

    for service_name in pve-cluster pvedaemon pveproxy pvestatd; do
        if systemctl list-unit-files "${service_name}.service" --no-legend 2>/dev/null | grep -q .; then
            systemctl restart "${service_name}"
            PVE_SERVICES_RESTARTED="yes"
        fi
    done
}

print_summary() {
    echo
    echo "Summary of changes:"

    if [[ "${BACKUP_CREATED}" == "yes" ]]; then
        echo "- Created Proxmox backup archive in ${BACKUP_DIR}"
    else
        echo "- No Proxmox backup archive was created"
    fi

    if [[ "${HOSTNAME_UPDATED}" == "yes" ]]; then
        echo "- Updated ${HOSTNAME_FILE} to ${NEW_SHORT_HOSTNAME}"
    else
        echo "- ${HOSTNAME_FILE} was not changed"
    fi

    if [[ "${HOSTS_UPDATED}" == "yes" ]]; then
        echo "- Updated ${HOSTS_FILE} with ${MANAGEMENT_IP} ${NEW_FQDN} ${NEW_SHORT_HOSTNAME}"
    else
        echo "- ${HOSTS_FILE} was not changed"
    fi

    if [[ "${POSTFIX_UPDATED}" == "yes" ]]; then
        echo "- Updated ${POSTFIX_FILE}"
    else
        echo "- ${POSTFIX_FILE} was not changed"
    fi

    if [[ "${POSTFIX_RESTARTED}" == "yes" ]]; then
        echo "- Restarted postfix"
    fi

    if [[ "${PVE_GUEST_CONFIGS_MOVED}" == "yes" ]]; then
        echo "- Moved guest configs from ${OLD_NODE_NAME} to ${NEW_SHORT_HOSTNAME} under ${PVE_NODES_DIR}"
    else
        echo "- No guest config files needed to move under ${PVE_NODES_DIR}"
    fi

    if [[ "${STORAGE_UPDATED}" == "yes" ]]; then
        echo "- Updated node restrictions in ${STORAGE_CFG_FILE}"
    else
        echo "- ${STORAGE_CFG_FILE} did not need node restriction changes"
    fi

    if [[ "${PVE_SERVICES_RESTARTED}" == "yes" ]]; then
        echo "- Restarted Proxmox services: pve-cluster, pvedaemon, pveproxy, pvestatd"
    else
        echo "- No Proxmox services were restarted"
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
OLD_NODE_NAME=""

echo "Current short hostname: ${CURRENT_SHORT_HOSTNAME}"
echo "Current FQDN: ${CURRENT_FQDN}"
echo "New short hostname: ${NEW_SHORT_HOSTNAME}"
echo "New FQDN: ${NEW_FQDN}"
echo "Management IP: ${MANAGEMENT_IP}"

backup_proxmox_config
backup_file "${HOSTNAME_FILE}"
backup_file "${HOSTS_FILE}"

printf '%s\n' "${NEW_SHORT_HOSTNAME}" > "${HOSTNAME_FILE}"
chmod 0644 "${HOSTNAME_FILE}"
hostnamectl set-hostname "${NEW_SHORT_HOSTNAME}"
HOSTNAME_UPDATED="yes"

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
HOSTS_UPDATED="yes"

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
        POSTFIX_RESTARTED="yes"
    fi

    POSTFIX_UPDATED="yes"
fi

migrate_proxmox_node_configs
update_storage_cfg
restart_proxmox_services

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
if [[ -n "${OLD_NODE_NAME}" && "${OLD_NODE_NAME}" != "${NEW_SHORT_HOSTNAME}" ]]; then
    grep -RFn -e "${OLD_NODE_NAME}" -e "${CURRENT_FQDN}" /etc/pve /etc/postfix /etc 2>/dev/null || true
else
    grep -RFn -e "${CURRENT_SHORT_HOSTNAME}" -e "${CURRENT_FQDN}" /etc/pve /etc/postfix /etc 2>/dev/null || true
fi

echo
print_summary
echo "Review any remaining hostname references, then reboot the node if this was the first rename pass."
echo "Reconnect with: https://${MANAGEMENT_IP}:8006"
echo "If the new FQDN shows a certificate warning later, run: pvecm updatecerts -f && systemctl restart pveproxy pvedaemon"