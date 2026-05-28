#!/usr/bin/env bash

set -Eeuo pipefail

# =========================================================
# CONFIGURAR UMASK 027 PARA EL USUARIO ACTUAL
# =========================================================
#
# Resultado:
#   - Carpetas nuevas  -> 750
#   - Archivos nuevos  -> 640
#
# =========================================================

UMASK_VALUE="027"

echo "========================================="
echo " CONFIGURACIÓN DE UMASK"
echo "========================================="
echo

# Detectar usuario real aunque se use sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~${REAL_USER}")

echo "Usuario detectado : ${REAL_USER}"
echo "Home detectado    : ${REAL_HOME}"
echo "UMASK objetivo    : ${UMASK_VALUE}"
echo

BASHRC_FILE="${REAL_HOME}/.bashrc"
PROFILE_FILE="${REAL_HOME}/.profile"

# Función para añadir umask si no existe
add_umask() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        touch "$file"
        chown "${REAL_USER}:${REAL_USER}" "$file"
    fi

    if grep -q "^umask " "$file"; then
        echo "→ Actualizando umask existente en ${file}"
        sed -i "s/^umask .*/umask ${UMASK_VALUE}/" "$file"
    else
        echo "→ Añadiendo umask a ${file}"
        echo "" >> "$file"
        echo "# Umask segura para homelab" >> "$file"
        echo "umask ${UMASK_VALUE}" >> "$file"
    fi
}

add_umask "${BASHRC_FILE}"
add_umask "${PROFILE_FILE}"

echo
echo "========================================="
echo " UMASK CONFIGURADA CORRECTAMENTE"
echo "========================================="
echo
echo "Nueva configuración:"
echo "  Archivos nuevos -> 640"
echo "  Carpetas nuevas -> 750"
echo
echo "IMPORTANTE:"
echo "Cierra sesión y vuelve a entrar"
echo "o ejecuta:"
echo
echo "source ~/.bashrc"
echo