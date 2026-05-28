#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

DOCKER_NETWORKS=(
  "homelab_socket"
  "homelab_web"
  "homelab_dns"
)

for net in "${DOCKER_NETWORKS[@]}"; do
    if docker network inspect "$net" >/dev/null 2>&1; then
        echo "Docker network '$net' ya existe (sin cambios)."
    else
        echo "Creando Docker network '$net'..."
        docker network create "$net"
    fi
done