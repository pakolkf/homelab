#!/bin/bash

# Sincroniza la CONFIG versionada de cada stack (todo menos el compose y los
# .env) desde el repo a /opt/homelab/appdata/<svc>/, que es donde los
# contenedores la montan vía ${APPDATA_DIR}.
#
# Además renderiza variables del host (FQDN, ACME_EMAIL) en la config, para que
# el repo nunca hardcodee el dominio ni el email reales: en el repo van como
# ${FQDN} / ${ACME_EMAIL} y aquí se sustituyen por su valor del .env del host.
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

# Variables del host que se renderizan en las plantillas de config.
RENDER_VARS="FQDN ACME_EMAIL"

# Usuario real (vía sudo -> SUDO_*; root login -> id).
PUID="${SUDO_UID:-$(id -u)}"
PGID="${SUDO_GID:-$(id -g)}"

if [[ ! -d "${SRC}" ]]; then
    echo "ERROR: no existe ${SRC}" >&2
    exit 1
fi

# Carga las variables del host para renderizar.
if [[ -f "${HOST_ENV}" ]]; then
    set -a; . "${HOST_ENV}"; set +a
fi

echo "Sincronizando config de stacks-templates -> ${DEST} ..."

for svc_dir in "${SRC}"/*/; do
    svc="$(basename "${svc_dir}")"
    # Si no hay config versionada (solo quedaría compose/.env), la carpeta
    # estaría vacía -> no se sincroniza.
    if [[ -z "$(find "${svc_dir}" -type f \
            ! -name 'docker-compose.yaml' ! -name 'docker-compose.yml' \
            ! -name '.env' ! -name '.env.*' -print -quit)" ]]; then
        echo "skip: ${svc} (sin config versionada)"
        continue
    fi
    mkdir -p "${DEST}/${svc}"
    # Copia la config; excluye recetas (compose) y secretos (.env).
    rsync -a \
        --exclude 'docker-compose.yaml' \
        --exclude 'docker-compose.yml' \
        --exclude '.env' \
        --exclude '.env.*' \
        "${svc_dir}" "${DEST}/${svc}/"
    # Renderiza ${VAR} -> valor en la config copiada.
    for var in ${RENDER_VARS}; do
        val="${!var:-}"
        [[ -n "${val}" ]] || continue
        find "${DEST}/${svc}" -type f -print0 \
            | xargs -0 -r sed -i "s|\${${var}}|${val}|g"
    done
    chown -R "${PUID}:${PGID}" "${DEST}/${svc}"
    echo "OK: ${svc}"
done

for var in ${RENDER_VARS}; do
    [[ -n "${!var:-}" ]] || echo "AVISO: ${var} no definido en ${HOST_ENV}; plantillas con \${${var}} sin renderizar." >&2
done

echo "Config sincronizada."
