#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

readonly AUTOUPDATE_CRON="/etc/cron.d/homelab-autoupdate"
readonly AUTOUPDATE_LOG="/var/log/homelab-autoupdate.log"

if [[ -f "${AUTOUPDATE_CRON}" ]]; then
    echo "Auto-update: ya existe ${AUTOUPDATE_CRON} (sin cambios)."
    exit 0
fi

echo "Configurando cron diario de actualizacion del sistema..."

cat > "${AUTOUPDATE_CRON}" << CRONEOF
# Homelab -- auto-update diario del SO
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

* 3 * * * root apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade >> ${AUTOUPDATE_LOG} 2>&1
CRONEOF

chmod 644 "${AUTOUPDATE_CRON}"
touch "${AUTOUPDATE_LOG}"

echo "Cron auto-update: ${AUTOUPDATE_CRON}"