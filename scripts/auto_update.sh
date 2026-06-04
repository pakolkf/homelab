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

# Reinicia SOLO si el upgrade instalo algo que lo requiere: Debian/Ubuntu crea
# /var/run/reboot-required en ese caso (kernel, libc...). Asi no reinicia a diario
# ni en cada paquete, solo cuando de verdad hace falta.
cat > "${AUTOUPDATE_CRON}" << CRONEOF
# Homelab -- auto-update diario del SO (03:00) + reinicio solo si es necesario
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

0 3 * * * root { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade && { [ -f /var/run/reboot-required ] && /sbin/reboot; }; } >> ${AUTOUPDATE_LOG} 2>&1
CRONEOF

chmod 644 "${AUTOUPDATE_CRON}"
touch "${AUTOUPDATE_LOG}"

echo "Cron auto-update: ${AUTOUPDATE_CRON}"