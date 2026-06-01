#!/usr/bin/env bash

set -uo pipefail

HOMELAB_DIR="/opt/homelab"
UID_TARGET="1000"
GID_TARGET="1000"

echo "========================================="
echo " CONFIGURACIÓN DE PERMISOS HOMELAB"
echo "========================================="
echo

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Ejecuta este script con sudo"
    exit 1
fi

if [[ ! -d "${HOMELAB_DIR}" ]]; then
    echo "ERROR: No existe ${HOMELAB_DIR}"
    exit 1
fi

echo "→ Eliminando atributos immutable..."
chattr -R -i "${HOMELAB_DIR}" 2>/dev/null || true

# -xdev: no cruzar a otros sistemas de ficheros montados (p.ej. un NAS NFS/SMB
# en /opt/homelab/stacks). Sus permisos los gobierna el export del NAS; aquí solo
# tocamos el disco local. Sin esto, cada ejecución recorrería el NAS entero por red.
echo "→ Aplicando propietario ${UID_TARGET}:${GID_TARGET}..."
find "${HOMELAB_DIR}" -xdev \
    -path "*/.git" -prune -o \
    -exec chown "${UID_TARGET}:${GID_TARGET}" {} \; 2>/dev/null || true

echo "→ Aplicando permisos a carpetas (750)..."
find "${HOMELAB_DIR}" -xdev \
    -path "*/.git" -prune -o \
    -type d -exec chmod 750 {} \; 2>/dev/null || true

echo "→ Aplicando permisos a archivos (640)..."
find "${HOMELAB_DIR}" -xdev \
    -path "*/.git" -prune -o \
    -type f -exec chmod 640 {} \; 2>/dev/null || true

echo "→ Configurando scripts ejecutables..."
find "${HOMELAB_DIR}" -xdev \
    -type f \
    -name "*.sh" \
    -exec chmod 750 {} \; 2>/dev/null || true

echo "→ Protegiendo archivos .env..."
find "${HOMELAB_DIR}" -xdev \
    -type f \
    \( -name ".env" -o -name "*.env" \) \
    -exec chmod 600 {} \; 2>/dev/null || true

echo "→ Protegiendo carpetas secrets..."
find "${HOMELAB_DIR}" -xdev \
    -type d \
    \( -name "secret" -o -name "secrets" \) \
    -exec chmod 700 {} \; 2>/dev/null || true

echo "→ Protegiendo archivos secretos..."
find "${HOMELAB_DIR}" -xdev \
    -type f \
    \( \
        -name "*.pem" \
        -o -name "*.key" \
        -o -name "id_rsa" \
        -o -name "id_ed25519" \
    \) \
    -exec chmod 600 {} \; 2>/dev/null || true

echo
echo "========================================="
echo " CONFIGURACIÓN FINALIZADA"
echo "========================================="
echo