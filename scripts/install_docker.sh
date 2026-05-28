#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

echo "Instalando Docker y Docker Compose..."

# Dependencias
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

# Keyring Docker
install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

chmod a+r /etc/apt/keyrings/docker.gpg

# Repositorio Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

# Instalacion
apt-get update

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Habilitar servicio
systemctl enable docker
systemctl start docker

# Usuario actual al grupo docker
if [[ -n "${SUDO_USER}" ]]; then
    usermod -aG docker "${SUDO_USER}"
    echo "Usuario ${SUDO_USER} añadido al grupo docker."
fi

echo ""
echo "Docker instalado correctamente."
echo ""

docker --version
docker compose version

echo ""
echo "IMPORTANTE:"
echo "Cierra sesión y vuelve a entrar para usar Docker sin sudo."