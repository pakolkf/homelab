#!/bin/bash

# Sincroniza la CONFIG versionada de cada stack (todo menos el compose y los
# .env) desde el repo a /opt/homelab/appdata/<svc>/, que es donde los
# contenedores la montan vía ${APPDATA_DIR}.
#
# Además renderiza ${FQDN} en la config (Traefik/Unbound usan el dominio),
# tomándolo del .env del host. Así el repo nunca hardcodea el dominio real.
#
# Motivo: dockhand solo escribe el compose del stack; los ficheros de config
# versionados (traefik.yaml, dynamic/, unbound.conf, AdGuardHome.yaml, root.*)
# no los coloca nadie. Este script los pone en su sitio.
#
# Idempotente y NO destructivo: usa rsync sin --delete, así nunca borra datos
# de runtime ya presentes en appdata. Reejecutar tras cambiar config en el repo.

set -uo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${REPO_DIR}/stacks-templates"
DEST="/opt/homelab/appdata"
HOST_ENV="/opt/homelab/docker/.env"

# Usuario real (vía sudo -> SUDO_*; root login -> id).
PUID="${SUDO_UID:-$(id -u)}"
PGID="${SUDO_GID:-$(id -g)}"

if [[ ! -d "${SRC}" ]]; then
    echo "ERROR: no existe ${SRC}" >&2
    exit 1
fi

# Carga variables del host (FQDN…) para renderizar las plantillas de config.
if [[ -f "${HOST_ENV}" ]]; then
    set -a; . "${HOST_ENV}"; set +a
fi

echo "Sincronizando config de stacks-templates -> ${DEST} ..."

for svc_dir in "${SRC}"/*/; do
    svc="$(basename "${svc_dir}")"
    mkdir -p "${DEST}/${svc}"
    # Copia la config; excluye recetas (compose) y secretos (.env).
    rsync -a \
        --exclude 'docker-compose.yaml' \
        --exclude 'docker-compose.yml' \
        --exclude '.env' \
        --exclude '.env.*' \
        "${svc_dir}" "${DEST}/${svc}/"
    # Renderiza ${FQDN} en la config copiada (Traefik/Unbound usan el dominio).
    if [[ -n "${FQDN:-}" ]]; then
        find "${DEST}/${svc}" -type f -print0 \
            | xargs -0 -r sed -i "s|\${FQDN}|${FQDN}|g"
    fi
    chown -R "${PUID}:${PGID}" "${DEST}/${svc}"
    echo "OK: ${svc}"
done

if [[ -z "${FQDN:-}" ]]; then
    echo "AVISO: FQDN no definido en ${HOST_ENV}; plantillas con \${FQDN} sin renderizar." >&2
fi

echo "Config sincronizada."
