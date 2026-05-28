#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

readonly UNBOUND_CRON="/etc/cron.d/homelab-unbound-roots"
readonly UNBOUND_LOG="/var/log/homelab-unbound.log"

readonly CONTAINER_NAME="unbound"
readonly STACK_DIR="/opt/homelab/docker/unbound"
readonly IMG_UNBOUND="mvance/unbound:latest"

if [[ -f "${UNBOUND_CRON}" ]]; then
    echo "Unbound cron: ya existe ${UNBOUND_CRON} (sin cambios)."
    exit 0
fi

echo "Configurando cron mensual de refresco Unbound..."

cat > "${UNBOUND_CRON}" << CRONEOF
# Homelab -- refresco mensual root.hints + root.key
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

0 4 1 * * root docker ps --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}$' && curl -fsSL --max-time 30 https://www.internic.net/domain/named.root -o ${STACK_DIR}/root.hints && docker run --rm --entrypoint unbound-anchor -v ${STACK_DIR}:/anchor ${IMG_UNBOUND} -a /anchor/root.key && docker restart ${CONTAINER_NAME} >> ${UNBOUND_LOG} 2>&1
CRONEOF

chmod 644 "${UNBOUND_CRON}"
touch "${UNBOUND_LOG}"

echo "Cron Unbound: ${UNBOUND_CRON}"