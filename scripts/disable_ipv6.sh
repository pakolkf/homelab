#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

echo "Desactivando IPv6..."

sysctl_file=/etc/sysctl.d/99-homelab-disable-ipv6.conf

cat > "${sysctl_file}" << SCEOF
# Generado por homelab-installer
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
SCEOF

if command -v sysctl &>/dev/null; then
    sysctl -p "${sysctl_file}" >/dev/null 2>&1 || true
fi

echo "IPv6 desactivado" "IPv6 desactivado a nivel kernel."
echo "Reinicia para garantizar que aplica en todas las redes."