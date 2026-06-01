#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

echo "Creando estructura del homelab..."

# Config base
HOMELAB_BASE="/opt/homelab"
DOCKER_BASE="${HOMELAB_BASE}/docker"
STACKS_BASE="${HOMELAB_BASE}/stacks"
APPDATA="${HOMELAB_BASE}/appdata"
ENV_FILE="${DOCKER_BASE}/.env"

# Detecta el usuario real que invocó el script:
#  - vía sudo            -> SUDO_UID/SUDO_GID (uid de p.ej. pepe, no root)
#  - root login sin sudo -> id -u / id -g (será 0)
PUID="${SUDO_UID:-$(id -u)}"
PGID="${SUDO_GID:-$(id -g)}"
TZ="Europe/Madrid"

# Directorios
DIRS=(
  "${HOMELAB_BASE}"
  "${DOCKER_BASE}"
  "${STACKS_BASE}"
  "${APPDATA}"
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

# Inserta o actualiza una clave KEY=VALUE en el .env (idempotente).
set_env_var() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|" "${ENV_FILE}"
  else
    echo "${key}=${val}" >> "${ENV_FILE}"
  fi
}

if [[ ! -f "${ENV_FILE}" ]]; then
  cat > "${ENV_FILE}" << EOF
PUID=${PUID}
PGID=${PGID}
TZ=${TZ}
FQDN=example.com
HOMELAB_BASE=${HOMELAB_BASE}
DOCKER_BASE=${DOCKER_BASE}
STACKS_BASE=${STACKS_BASE}
APPDATA=${APPDATA}
EOF

  chown root:root "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"

  echo "OK: .env creado (solo root)"
else
  echo ".env ya existe — sincronizando PUID/PGID al usuario detectado (${PUID}:${PGID})"
  set_env_var PUID "${PUID}"
  set_env_var PGID "${PGID}"
fi

echo ""
echo "Estructura lista."