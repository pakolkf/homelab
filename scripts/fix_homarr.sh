#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

HOMELAB_DOCKER_DIR="/opt/homelab/docker"
# Usuario real que invocó el script: vía sudo -> SUDO_UID/SUDO_GID (uid de pepe);
# root login sin sudo -> id -u / id -g (será 0).
UID_TARGET="${SUDO_UID:-$(id -u)}"
GID_TARGET="${SUDO_GID:-$(id -g)}"

mkdir -p "${HOMELAB_DOCKER_DIR}/homarr/appdata"
chown -R ${UID_TARGET}:${GID_TARGET} "${HOMELAB_DOCKER_DIR}/homarr/appdata"
chmod -R 750 "${HOMELAB_DOCKER_DIR}/homarr/appdata"

echo 'vm.overcommit_memory=1' | tee /etc/sysctl.d/99-homarr-redis.conf
sysctl --system