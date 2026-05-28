#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

echo "Creando estructura del homelab..."

# Config base
HOMELAB_BASE="/opt/homelab"
DOCKER_BASE="${HOMELAB_BASE}/docker"
ENV_FILE="${HOMELAB_BASE}/.env"

PUID=1000
PGID=1000
TZ="Europe/Madrid"

# Directorios
DIRS=(
  "${HOMELAB_BASE}"
  "${DOCKER_BASE}"
)

echo "Creando directorios..."

for dir in "${DIRS[@]}"; do
  mkdir -p "${dir}"
  chown -R "${PUID}:${PGID}" "${dir}"
  chmod -R 775 "${dir}"
  echo "OK: ${dir} (owner ${PUID}:${PGID})"
done

# .env seguro (solo root)
echo "Creando .env..."

if [[ ! -f "${ENV_FILE}" ]]; then
  cat > "${ENV_FILE}" << EOF
PUID=${PUID}
PGID=${PGID}
TZ=${TZ}
HOMELAB_BASE=${HOMELAB_BASE}
DOCKER_BASE=${DOCKER_BASE}
EOF

  chown root:root "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"

  echo "OK: .env creado (solo root)"
else
  echo ".env ya existe (sin cambios)"
fi

echo ""
echo "Estructura lista."