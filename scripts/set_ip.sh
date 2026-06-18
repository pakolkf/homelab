#!/bin/bash

# Configuración — ajusta estos valores
INTERFACE="eth0"
STATIC_IP="10.55.0.20/24"
GATEWAY="10.55.0.1"
NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"

# ─────────────────────────────────────────
usage() {
  echo "Uso: $0 [static|dynamic]"
  echo "  static   → asigna IP fija"
  echo "  dynamic  → vuelve a DHCP"
  exit 1
}

set_static() {
  echo "Configurando IP estática $STATIC_IP en $INTERFACE..."
  cat > "$NETPLAN_FILE" << NETPLAN
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: false
      addresses:
        - $STATIC_IP
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses:
          - $GATEWAY
NETPLAN

  netplan apply
  echo "IP estática aplicada: $STATIC_IP"
  ip addr show "$INTERFACE" | grep "inet "
}

set_dynamic() {
  echo "Configurando DHCP en $INTERFACE..."
  cat > "$NETPLAN_FILE" << NETPLAN
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: true
NETPLAN

  netplan apply
  echo "DHCP activado"
  sleep 3
  ip addr show "$INTERFACE" | grep "inet "
}

# ─────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo "Ejecuta como root: sudo $0 $1"
  exit 1
fi

case "$1" in
  static)  set_static ;;
  dynamic) set_dynamic ;;
  *)       usage ;;
esac