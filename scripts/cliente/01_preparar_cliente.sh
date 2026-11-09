#!/usr/bin/env bash
# 01_preparar_cliente.sh — Prepara docker-cli: herramientas de prueba, nombre del servidor y
# llave SSH. Ejecutar ANTES de 02_hardening_host.sh en el servidor (todavía con SSH en el 22).
source "$(dirname "$0")/../comun.sh"
encabezado "Preparar el segundo nodo"
bitacora "inicio"

titulo "1. Herramientas de prueba"
ejecutar sudo apt-get update
ejecutar sudo DEBIAN_FRONTEND=noninteractive apt-get -y install curl nmap netcat-openbsd openssh-client postgresql-client openssl

titulo "2. Nombre del servidor en /etc/hosts"
grep -q "docker-srv" /etc/hosts || echo "$SERVER_IP docker-srv" | sudo tee -a /etc/hosts
ejecutar getent hosts docker-srv

titulo "3. Llave SSH (ed25519) y copia al servidor"
[ -f "$HOME/.ssh/id_ed25519" ] || ejecutar ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" -C "$USER@docker-cli"
read -rp "Usuario administrador en docker-srv [$USER]: " ADMIN; ADMIN="${ADMIN:-$USER}"
echo "Se pedirá la contraseña de $ADMIN UNA vez (después solo se entra con la llave):"
ejecutar ssh-copy-id -p 22 -i "$HOME/.ssh/id_ed25519.pub" "$ADMIN@$SERVER_IP"
ok "llave copiada. Ahora ejecute en el servidor: scripts/servidor/02_hardening_host.sh"
