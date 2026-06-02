#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

readonly UNBOUND_CRON="/etc/cron.d/homelab-unbound-roots"
readonly UNBOUND_LOG="/var/log/homelab-unbound.log"

readonly CONTAINER_NAME="unbound"
readonly APPDATA_DIR="/opt/homelab/appdata/unbound"
readonly IMG_UNBOUND="klutchell/unbound:latest"

if [[ -f "${UNBOUND_CRON}" ]]; then
    echo "Unbound cron: ya existe ${UNBOUND_CRON} (sin cambios)."
    exit 0
fi

echo "Configurando cron mensual de refresco Unbound..."

# Notas:
#  - --user root: unbound-anchor escribe root.key en el dir montado; con el
#    usuario por defecto del contenedor no podría. Lo deja en root (0:0)...
#  - chown 101:102: ...así que tras generarlas se devuelven al usuario 'unbound'
#    (uid 101/gid 102), que debe poder LEER root.hints y RE-ESCRIBIR root.key
#    (auto-trust-anchor-file/RFC5011). chmod 644 => owner rw, resto ro.
#  - bloque { ...; }: unbound-anchor devuelve 1 cuando ACTUALIZA el ancla, así
#    que encadenamos con ';' para no abortar el restart.
cat > "${UNBOUND_CRON}" << CRONEOF
# Homelab -- refresco mensual root.hints + root.key
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

0 4 1 * * root docker ps --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}\$' && { curl -fsSL --max-time 30 https://www.internic.net/domain/named.root -o ${APPDATA_DIR}/root.hints; docker run --rm --user root --entrypoint unbound-anchor -v ${APPDATA_DIR}:/anchor ${IMG_UNBOUND} -a /anchor/root.key; chown 101:102 ${APPDATA_DIR}/root.hints ${APPDATA_DIR}/root.key; chmod 644 ${APPDATA_DIR}/root.hints ${APPDATA_DIR}/root.key; docker restart ${CONTAINER_NAME}; } >> ${UNBOUND_LOG} 2>&1
CRONEOF

chmod 644 "${UNBOUND_CRON}"
touch "${UNBOUND_LOG}"

echo "Cron Unbound: ${UNBOUND_CRON}"
