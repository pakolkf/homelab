#!/bin/bash
# ============================================================
# Monta una exportación NFS bajo /opt/homelab y la persiste en
# /etc/fstab. Idempotente: si la entrada ya existe, no la duplica.
#
# Uso:
#   sudo ./mount_nfs.sh <servidor> <export> [punto_montaje]
#
# Ejemplo:
#   sudo ./mount_nfs.sh 10.0.0.50 /export/data_arr /opt/homelab/data_arr
#
# Variables de entorno alternativas (si no se pasan args):
#   NFS_SERVER, NFS_EXPORT, MOUNT_POINT
#
# Opciones del montaje (NFSv3 por defecto, override con NFS_VERS=4.1):
#   - vers=${NFS_VERS} (default 3)
#   - proto=tcp (más estable que udp para v3)
#   - hard (no perder escrituras si el server cae)
#   - rsize/wsize=1048576 (rendimiento alto)
#   - _netdev + x-systemd.automount (espera a la red, no
#     bloquea boot si el server no responde aún)
#   - nofail (no aborta boot si el NFS no contesta)
# ============================================================

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

NFS_SERVER="${1:-${NFS_SERVER:-}}"
NFS_EXPORT="${2:-${NFS_EXPORT:-}}"
MOUNT_POINT="${3:-${MOUNT_POINT:-/opt/homelab/data_arr}}"

if [[ -z "${NFS_SERVER}" || -z "${NFS_EXPORT}" ]]; then
    cat >&2 <<EOF
Faltan argumentos.

Uso:
  sudo $0 <servidor> <export> [punto_montaje]

Ejemplo:
  sudo $0 10.0.0.50 /export/data_arr /opt/homelab/data_arr
EOF
    exit 1
fi

REMOTE="${NFS_SERVER}:${NFS_EXPORT}"
NFS_VERS="${NFS_VERS:-3}"
OPTS="nfs vers=${NFS_VERS},proto=tcp,hard,rsize=1048576,wsize=1048576,_netdev,x-systemd.automount,x-systemd.idle-timeout=600,nofail 0 0"

echo "→ Servidor NFS:  ${NFS_SERVER}"
echo "→ Export:        ${NFS_EXPORT}"
echo "→ Punto montaje: ${MOUNT_POINT}"

# ------------------------------------------------------------
# 1. Cliente NFS
# ------------------------------------------------------------
if ! command -v mount.nfs &>/dev/null; then
    echo "→ Instalando nfs-common..."
    apt-get update -qq
    apt-get install -y nfs-common
fi

# ------------------------------------------------------------
# 2. Punto de montaje
# ------------------------------------------------------------
if [[ ! -d "${MOUNT_POINT}" ]]; then
    echo "→ Creando punto de montaje ${MOUNT_POINT}"
    mkdir -p "${MOUNT_POINT}"
    chown 1000:1000 "${MOUNT_POINT}"
    chmod 750 "${MOUNT_POINT}"
fi

# Si ya hay algo dentro y no es un mount, avisa pero continúa
if [[ -n "$(ls -A "${MOUNT_POINT}" 2>/dev/null)" ]] && ! mountpoint -q "${MOUNT_POINT}"; then
    echo "AVISO: ${MOUNT_POINT} ya contiene datos locales."
    echo "        Al montar el NFS encima quedarán ocultos (no borrados)."
    read -r -p "¿Continuar? [y/N] " ans
    [[ "${ans,,}" == "y" ]] || { echo "Abortado."; exit 1; }
fi

# ------------------------------------------------------------
# 3. Entrada en /etc/fstab (idempotente)
# ------------------------------------------------------------
FSTAB_LINE="${REMOTE}  ${MOUNT_POINT}  ${OPTS}"

if grep -qE "^\s*${NFS_SERVER}:${NFS_EXPORT}\s+${MOUNT_POINT}\s+" /etc/fstab; then
    echo "→ /etc/fstab ya contiene una entrada para este NFS — no se duplica."
else
    echo "→ Añadiendo entrada a /etc/fstab"
    cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
    printf '\n# NFS homelab (mount_nfs.sh)\n%s\n' "${FSTAB_LINE}" >> /etc/fstab
fi

# ------------------------------------------------------------
# 4. Recarga systemd y monta
# ------------------------------------------------------------
systemctl daemon-reload

if mountpoint -q "${MOUNT_POINT}"; then
    echo "→ Ya estaba montado, remount..."
    mount -o remount "${MOUNT_POINT}"
else
    echo "→ Montando..."
    mount "${MOUNT_POINT}"
fi

# ------------------------------------------------------------
# 5. Verificación
# ------------------------------------------------------------
echo ""
if mountpoint -q "${MOUNT_POINT}"; then
    echo "OK — montado:"
    findmnt -no SOURCE,TARGET,FSTYPE,OPTIONS "${MOUNT_POINT}"
    echo ""
    df -h "${MOUNT_POINT}"
else
    echo "ERROR: ${MOUNT_POINT} no aparece montado." >&2
    exit 1
fi

cat <<EOF

Próximos pasos:
  - Confirma que el server NFS exporta con:
      ${NFS_EXPORT} <subred>(rw,sync,no_subtree_check,no_root_squash)
  - Si los contenedores van a escribir, asegúrate de que el uid 1000
    tiene permisos en el lado servidor (chown 1000:1000 en el export).
  - Tras cambios en exports del servidor: exportfs -ra en el server.
EOF
