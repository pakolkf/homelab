#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

HOMELAB_DOCKER_DIR="/opt/homelab/docker"
UID_TARGET="1000"
GID_TARGET="1000"

mkdir -p "${HOMELAB_DOCKER_DIR}/homarr/appdata"
chown -R ${UID_TARGET}:${GID_TARGET} "${HOMELAB_DOCKER_DIR}/homarr/appdata"
chmod -R 750 "${HOMELAB_DOCKER_DIR}/homarr/appdata"

echo 'vm.overcommit_memory=1' | tee /etc/sysctl.d/99-homarr-redis.conf
sysctl --system