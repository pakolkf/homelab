#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

./auto_update.sh
./set_ip.sh static
./update_unbound_stack.sh
./disable_ipv6.sh
./disable_dns.sh
./enable_firewall.sh
./fix_unmask.sh
./create_estructure.sh
./fix_overcommit.sh

# ------------------------------------------------------------
# NFS mounts (opcional, local al host)
# ------------------------------------------------------------
# Si existe ./nfs-mounts.conf se procesa una línea por montaje.
# Formato:  <servidor>  <export>  [punto_montaje]
# Ver nfs-mounts.conf.example.
NFS_CONF="${SCRIPT_DIR}/nfs-mounts.conf"
if [[ -f "${NFS_CONF}" ]]; then
    echo "→ Procesando NFS mounts desde ${NFS_CONF}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        line="$(echo "${line}" | xargs)"
        [[ -z "${line}" ]] && continue
        # shellcheck disable=SC2086
        ./mount_nfs.sh ${line} || echo "AVISO: mount NFS falló para: ${line}"
    done < "${NFS_CONF}"
else
    echo "→ ${NFS_CONF} no presente — sin NFS mounts en este host."
fi

./sync_appdata.sh
./fix_permissions.sh
./install_docker.sh
./create_docker_network.sh