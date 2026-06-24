#!/bin/bash
# ============================================================
# Desmonta un NFS montado por mount_nfs.sh y lo retira de
# /etc/fstab. Idempotente.
#
# Uso:
#   sudo ./umount_nfs.sh <punto_montaje>
#   sudo ./umount_nfs.sh /opt/homelab/data_arr2
#
# Si el mount está ocupado:
#   sudo FORCE=1 ./umount_nfs.sh /opt/homelab/data_arr2
#   → intenta lazy umount (-l). Útil si un docker sigue
#     teniendo handles abiertos.
# ============================================================

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

MOUNT_POINT="${1:-}"

if [[ -z "${MOUNT_POINT}" ]]; then
    cat >&2 <<EOF
Falta el punto de montaje.

Uso:
  sudo $0 <punto_montaje>

Ejemplo:
  sudo $0 /opt/homelab/data_arr2
EOF
    exit 1
fi

FORCE="${FORCE:-0}"

echo "→ Punto montaje: ${MOUNT_POINT}"

# ------------------------------------------------------------
# 1. Desactivar el automount unit de systemd (si aplica)
# ------------------------------------------------------------
AUTO_UNIT="$(systemd-escape -p --suffix=automount "${MOUNT_POINT}")"
MOUNT_UNIT="$(systemd-escape -p --suffix=mount "${MOUNT_POINT}")"

for unit in "${AUTO_UNIT}" "${MOUNT_UNIT}"; do
    if systemctl is-active --quiet "${unit}" 2>/dev/null; then
        echo "→ Parando ${unit}"
        systemctl stop "${unit}" || true
    fi
done

# ------------------------------------------------------------
# 2. umount (si está montado)
# ------------------------------------------------------------
if mountpoint -q "${MOUNT_POINT}"; then
    echo "→ Desmontando..."
    if [[ "${FORCE}" == "1" ]]; then
        umount -l "${MOUNT_POINT}" || true
    else
        if ! umount "${MOUNT_POINT}"; then
            echo "ERROR: umount falló — algo tiene handles abiertos." >&2
            echo "       Cierra contenedores que usen esa ruta y reintenta," >&2
            echo "       o relanza con  sudo FORCE=1 $0 ${MOUNT_POINT}" >&2
            exit 1
        fi
    fi
else
    echo "→ No estaba montado."
fi

# ------------------------------------------------------------
# 3. Retirar entrada de /etc/fstab (idempotente)
# ------------------------------------------------------------
ESCAPED="$(printf '%s' "${MOUNT_POINT}" | sed 's/[\/&]/\\&/g')"

if grep -qE "^[^#]+\s+${ESCAPED}\s+nfs[34]?\s" /etc/fstab; then
    echo "→ Limpiando /etc/fstab"
    cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
    sed -i.tmp -E "/^[^#]+[[:space:]]+${ESCAPED}[[:space:]]+nfs[34]?[[:space:]]/d" /etc/fstab
    rm -f /etc/fstab.tmp
else
    echo "→ Sin entrada NFS en /etc/fstab para ${MOUNT_POINT} — nada que limpiar."
fi

systemctl daemon-reload

# ------------------------------------------------------------
# 4. Verificación
# ------------------------------------------------------------
echo ""
if mountpoint -q "${MOUNT_POINT}"; then
    echo "ERROR: ${MOUNT_POINT} sigue montado." >&2
    exit 1
fi
echo "OK — ${MOUNT_POINT} desmontado y fstab limpio."

cat <<EOF

Próximos pasos:
  - Si ya no quieres la carpeta vacía:
      sudo rmdir "${MOUNT_POINT}"
  - Si vas a re-montar otro export en ese punto, déjala.
  - Acuérdate de quitar la línea correspondiente de
    scripts/nfs-mounts.conf para que init.sh no la vuelva
    a montar al próximo arranque.
EOF
