#!/usr/bin/env bash
# Written by HoloPanio (https://github.com/HoloPanio)
#
# Replaces /etc/apt/sources.list with official Debian 13 (Trixie)
# network repositories. A timestamped backup is created before the
# existing source list is overwritten.

set -euo pipefail

# The legacy APT source-list file this script manages.
SOURCES_FILE="/etc/apt/sources.list"

# Preserve the original file with a timestamp so it can be restored if needed.
BACKUP_FILE="${SOURCES_FILE}.bak.$(date +%Y%m%d-%H%M%S)"

# Writing to /etc/apt requires root privileges.
if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: Run this script as root (for example: sudo bash $0)." >&2
    exit 1
fi

# Back up the existing source list, retaining ownership and permissions.
if [[ -e "${SOURCES_FILE}" ]]; then
    cp -a -- "${SOURCES_FILE}" "${BACKUP_FILE}"
    echo "Backup created: ${BACKUP_FILE}"
fi

# Write the official Debian 13 (Trixie) package, update, and security sources.
# The non-free-firmware component provides supported proprietary firmware packages.
cat >"${SOURCES_FILE}" <<'EOF'
# Debian 13 (Trixie) official APT repositories
deb https://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb https://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb https://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF

# Use the normal read-only permissions expected for an APT source-list file.
chmod 0644 "${SOURCES_FILE}"

echo "Replaced ${SOURCES_FILE}."
echo "Review the file if desired, then run: apt update"