#!/usr/bin/env bash

set -uo pipefail

HOMELAB_DIR="/opt/homelab"
# Usuario real que invocó el script: vía sudo -> SUDO_UID/SUDO_GID (uid de pepe);
# root login sin sudo -> id -u / id -g (será 0).
UID_TARGET="${SUDO_UID:-$(id -u)}"
GID_TARGET="${SUDO_GID:-$(id -g)}"

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

# Unbound (imagen klutchell): el proceso corre como uid 101 / gid 102 (usuario
# 'unbound', UNBOUND_UID/UNBOUND_GID del Dockerfile). Va al FINAL para revertir el
# chown 1000 y el chmod 600 (bloque *.key) que se aplicaron antes.
# - unbound.conf y root.hints solo se LEEN -> 644 basta.
# - root.key la ESCRIBE unbound (auto-trust-anchor-file/RFC5011) -> debe pertenecer
#   a 101:102 y ser escribible por el dueño (644 => owner rw). De ahí el chown.
readonly UNBOUND_UID=101
readonly UNBOUND_GID=102
if [[ -d "${HOMELAB_DIR}/appdata/unbound" ]]; then
    echo "→ Unbound (klutchell): dueño ${UNBOUND_UID}:${UNBOUND_GID}, dir 755, ficheros 644..."
    chown -R "${UNBOUND_UID}:${UNBOUND_GID}" "${HOMELAB_DIR}/appdata/unbound" 2>/dev/null || true
    chmod 755 "${HOMELAB_DIR}/appdata/unbound" 2>/dev/null || true
    find "${HOMELAB_DIR}/appdata/unbound" -xdev -type f \
        -exec chmod 644 {} \; 2>/dev/null || true
fi

echo
echo "========================================="
echo " CONFIGURACIÓN FINALIZADA"
echo "========================================="
echo