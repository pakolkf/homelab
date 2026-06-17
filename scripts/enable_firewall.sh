#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

echo "Configurando UFW (firewall del host)..."

# ------------------------------------------------------------
# 1. Instalar UFW si no está
# ------------------------------------------------------------

if ! command -v ufw &>/dev/null; then
    apt-get update
    apt-get install -y ufw
fi

# ------------------------------------------------------------
# 2. Políticas por defecto
# ------------------------------------------------------------

ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null

# ------------------------------------------------------------
# 3. Reglas necesarias del homelab
# ------------------------------------------------------------
# IMPORTANTE: SSH va ANTES de habilitar el firewall para no
# perder el acceso si se ejecuta por SSH.

ufw allow 22/tcp  comment 'SSH'   >/dev/null
ufw allow 80/tcp  comment 'HTTP (Traefik)'  >/dev/null
ufw allow 443/tcp comment 'HTTPS (Traefik)' >/dev/null

# ------------------------------------------------------------
# 4. Habilitar (idempotente: --force evita el prompt)
# ------------------------------------------------------------

if ufw status | grep -q "Status: active"; then
    echo "UFW ya estaba activo. Reglas actualizadas."
else
    ufw --force enable
    echo "UFW habilitado."
fi

# ------------------------------------------------------------
# 5. Verificación
# ------------------------------------------------------------

echo ""
ufw status verbose

echo ""
echo "NOTA: los puertos publicados por contenedores Docker NO los"
echo "filtra UFW (Docker inserta sus propias reglas en iptables)."
echo "Para bloquearlos, no los publiques al host (o usa 127.0.0.1)."
