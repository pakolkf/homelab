#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

# Requisito del host para el Redis interno de Homarr.
echo 'vm.overcommit_memory=1' > /etc/sysctl.d/99-homarr-redis.conf
sysctl --system
