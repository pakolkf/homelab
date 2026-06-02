#!/bin/bash

# Descarga root.hints y genera root.key (ancla DNSSEC) DIRECTAMENTE en
# /opt/homelab/appdata/unbound/, listos para que el stack unbound los monte.
# Necesita Docker (genera root.key con unbound-anchor de la imagen klutchell),
# por eso en init.sh va DESPUÉS de install_docker.
#
# Idempotente: si ya existen, no hace nada (el cron mensual update_unbound_roots
# los refresca a partir de entonces).

set -uo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Ejecuta como root (sudo)." >&2
    exit 1
fi

readonly DEST="/opt/homelab/appdata/unbound"
readonly IMG_UNBOUND="klutchell/unbound:latest"
PUID="${SUDO_UID:-$(id -u)}"
PGID="${SUDO_GID:-$(id -g)}"

mkdir -p "${DEST}"

if [[ -f "${DEST}/root.hints" && -f "${DEST}/root.key" ]]; then
    echo "Raíces de unbound: ya existen en ${DEST} (sin cambios)."
    exit 0
fi

echo "Descargando root.hints..."
curl -fsSL --max-time 30 https://www.internic.net/domain/named.root -o "${DEST}/root.hints"

echo "Generando root.key (ancla DNSSEC) con unbound-anchor..."
# unbound-anchor devuelve 1 cuando ACTUALIZA el ancla (es normal) -> no abortar.
docker run --rm --user root --entrypoint unbound-anchor \
    -v "${DEST}:/anchor" "${IMG_UNBOUND}" -a /anchor/root.key || true

chown "${PUID}:${PGID}" "${DEST}/root.hints" "${DEST}/root.key"
chmod 644 "${DEST}/root.hints" "${DEST}/root.key"

echo "Raíces de unbound listas en ${DEST}."
