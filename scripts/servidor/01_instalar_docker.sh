#!/usr/bin/env bash
# 01_instalar_docker.sh — Actualiza el sistema, instala Docker Engine + Compose v2 desde los
# repositorios de Ubuntu y configura el demonio (daemon.json) con opciones de seguridad.
source "$(dirname "$0")/../comun.sh"
encabezado "Instalación de Docker"
bitacora "inicio"

titulo "1. Actualizar el sistema"
ejecutar sudo apt-get update
ejecutar sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade

titulo "2. Instalar Docker (repositorios de Ubuntu) y herramientas"
ejecutar sudo DEBIAN_FRONTEND=noninteractive apt-get -y install \
  docker.io docker-compose-v2 ufw fail2ban unattended-upgrades openssl curl netcat-openbsd

titulo "3. Configurar el demonio Docker (/etc/docker/daemon.json)"
sudo mkdir -p /etc/docker
[ -f /etc/docker/daemon.json ] && sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
sudo tee /etc/docker/daemon.json >/dev/null <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "no-new-privileges": true,
  "live-restore": true,
  "userland-proxy": false,
  "icc": false
}
JSON
ejecutar cat /etc/docker/daemon.json
ejecutar sudo systemctl enable --now docker
ejecutar sudo systemctl restart docker

titulo "4. Solo el administrador ($USER) en el grupo docker (equivale a root)"
ejecutar sudo usermod -aG docker "$USER"
ejecutar getent group docker

titulo "5. Versiones"
ejecutar sudo docker version
ejecutar sudo docker compose version
ok "Docker instalado. CIERRE SESIÓN Y VUELVA A ENTRAR para que el grupo docker tenga efecto."
