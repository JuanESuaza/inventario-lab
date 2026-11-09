#!/usr/bin/env bash
# comun.sh — Funciones compartidas por todos los scripts (se carga con "source").
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$RAIZ/config.env"
BITACORA=/var/log/inventario-lab-bitacora.log
SCRIPT="$(basename "$0")"

VERDE='\033[1;32m'; ROJO='\033[1;31m'; AZUL='\033[1;34m'; AMARILLO='\033[1;33m'; NC='\033[0m'

# Encabezado para las capturas: hostname, usuario y fecha siempre visibles
encabezado() {
  echo -e "${AZUL}==================================================================${NC}"
  echo -e "${AZUL} $SCRIPT ${1:-}${NC}"
  echo -e "${AZUL} host: $(hostname)   usuario: $(whoami)   fecha: $(date '+%Y-%m-%d %H:%M:%S %Z')${NC}"
  echo -e "${AZUL}==================================================================${NC}"
}

titulo() { echo; echo -e "${AMARILLO}>>> $*${NC}"; }
ok()     { echo -e "${VERDE}OK:${NC} $*"; bitacora "OK: $*"; }
falla()  { echo -e "${ROJO}FALLA:${NC} $*"; bitacora "FALLA: $*"; }

# Muestra el comando (como en la terminal) y lo ejecuta
ejecutar() { echo -e "${VERDE}\$ $*${NC}"; "$@"; }

# Registro automático en la bitácora del servidor/cliente
bitacora() {
  local linea
  linea="$(date '+%Y-%m-%d %H:%M:%S') | $(hostname) | $(whoami) | $SCRIPT | $*"
  echo "$linea" | sudo tee -a "$BITACORA" >/dev/null 2>&1 || true
}

# Interfaz que tiene la IP de la red del proyecto (192.168.56.x)
interfaz_proyecto() {
  ip -o -4 addr show | awk -v red="${RED_PROYECTO%.*/*}" '$4 ~ "^"red {print $2; exit}'
}

requiere_docker() {
  if ! docker info >/dev/null 2>&1; then
    falla "No puedo usar Docker. ¿Cerró sesión y volvió a entrar después del script 01 (grupo docker)?"
    exit 1
  fi
}

ir_a_raiz() { cd "$RAIZ" || exit 1; }
