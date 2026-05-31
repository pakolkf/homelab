#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

./auto_update.sh
./set_ip.sh static
./update_unbound_roots.sh
./disable_ipv6.sh
./disable_dns.sh
./fix_unmask.sh
./create_estructure.sh
./fix_homarr.sh
./fix_permissions.sh
./install_docker.sh
./create_docker_network.sh