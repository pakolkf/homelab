#!/bin/bash

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

echo "Configurando DNS del sistema..."

# ------------------------------------------------------------
# 1. Deshabilitar systemd-resolved stub listener
# ------------------------------------------------------------

mkdir -p /etc/systemd/resolved.conf.d

cat > /etc/systemd/resolved.conf.d/99-homelab-dns.conf << 'EOF'
# Homelab DNS configuration
[Resolve]

# Desactiva el stub listener (libera control de /etc/resolv.conf)
DNSStubListener=no

# DNS upstream del host (fallback global)
DNS=9.9.9.9
FallbackDNS=1.1.1.1 8.8.8.8
EOF

echo "Config systemd-resolved aplicada."

# ------------------------------------------------------------
# 2. Forzar resolv.conf gestionado por systemd-resolved
# ------------------------------------------------------------

ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

echo "resolv.conf enlazado a systemd-resolved."

# ------------------------------------------------------------
# 3. Reiniciar servicio
# ------------------------------------------------------------

systemctl restart systemd-resolved

echo "systemd-resolved reiniciado."

# ------------------------------------------------------------
# 4. Verificación
# ------------------------------------------------------------

echo ""
echo "DNS actual del sistema:"
cat /etc/resolv.conf

echo ""
echo "DNS configurado correctamente."