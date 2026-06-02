#!/bin/bash

# Mantiene las raíces de Unbound al día SIN gestionarlas a mano. La imagen
# klutchell trae root.hints + ancla DNSSEC baked, y unbound mantiene el ancla en
# runtime (auto-trust-anchor-file/RFC5011); basta con re-desplegar el stack cada
# cierto tiempo para traer la imagen más reciente (hints frescos + parches de
# unbound). Eso es lo que hace el cron que instala este script.
#
# Modos:
#   (sin args)  -> instala el cron (idempotente). Lo lanza init.sh.
#   --run       -> ejecuta la actualización (lo invoca el cron).

set -uo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Ejecuta como root (sudo)." >&2
    exit 1
fi

readonly CONTAINER_NAME="unbound"
readonly IMG_UNBOUND="klutchell/unbound:latest"
readonly UNBOUND_CRON="/etc/cron.d/homelab-unbound-update"
readonly UNBOUND_LOG="/var/log/homelab-unbound.log"
readonly LEGACY_CRON="/etc/cron.d/homelab-unbound-roots"
# Programación del refresco. Por defecto: día 1 de cada mes a las 04:00.
readonly CRON_SCHEDULE="0 4 1 * *"

run_update() {
    echo "[$(date '+%F %T')] Actualizando stack ${CONTAINER_NAME}..."
    docker pull "${IMG_UNBOUND}" || { echo "ERROR: docker pull falló."; exit 1; }

    # Recrea el contenedor con SU MISMO compose (el que desplegó hawser/dockhand),
    # localizado por las labels de compose del contenedor en marcha -> sin
    # hardcodear rutas del host.
    local cfg wd
    cfg="$(docker inspect "${CONTAINER_NAME}" --format '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' 2>/dev/null)"
    wd="$(docker inspect "${CONTAINER_NAME}"  --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}'  2>/dev/null)"

    if [[ -n "${cfg}" && -n "${wd}" ]]; then
        docker compose -f "${cfg}" --project-directory "${wd}" up -d "${CONTAINER_NAME}"
    else
        echo "AVISO: el contenedor no tiene labels de compose; no puedo recrearlo con"
        echo "       la imagen nueva sin su compose. Re-despliega el stack '${CONTAINER_NAME}'"
        echo "       desde dockhand. Reinicio el contenedor para que RFC5011 re-sincronice."
        docker restart "${CONTAINER_NAME}" || true
    fi
    echo "[$(date '+%F %T')] Hecho."
}

# --- Modo ejecución (lo invoca el cron) ---
if [[ "${1:-}" == "--run" ]]; then
    run_update
    exit 0
fi

# --- Modo instalación (lo invoca init.sh) ---
# Limpia el cron antiguo (regeneraba root.hints/root.key a mano; ya no aplica).
if [[ -f "${LEGACY_CRON}" ]]; then
    echo "Eliminando cron antiguo ${LEGACY_CRON} (obsoleto)."
    rm -f "${LEGACY_CRON}"
fi

if [[ -f "${UNBOUND_CRON}" ]]; then
    echo "Unbound update cron: ya existe ${UNBOUND_CRON} (sin cambios)."
    exit 0
fi

SELF="$(readlink -f "$0")"
echo "Instalando cron de actualización del stack unbound (${CRON_SCHEDULE})..."
cat > "${UNBOUND_CRON}" << CRONEOF
# Homelab -- actualiza el stack unbound (pull de imagen + recreate) para refrescar
# root.hints y el ancla DNSSEC baked, y aplicar parches de unbound. La gestión fina
# del ancla la hace unbound en runtime (auto-trust-anchor-file/RFC5011).
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

${CRON_SCHEDULE} root ${SELF} --run >> ${UNBOUND_LOG} 2>&1
CRONEOF

chmod 644 "${UNBOUND_CRON}"
touch "${UNBOUND_LOG}"

echo "Cron Unbound update: ${UNBOUND_CRON}"
