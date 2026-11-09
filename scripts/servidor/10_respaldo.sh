#!/usr/bin/env bash
# 10_respaldo.sh — Respaldo lógico con pg_dump (un volumen NO es un respaldo).
source "$(dirname "$0")/../comun.sh"
ir_a_raiz
requiere_docker
encabezado "Respaldo de la base de datos"
mkdir -p backups && chmod 700 backups
ARCH="backups/inventario_$(date +%Y%m%d_%H%M%S).sql.gz"
echo -e "${VERDE}\$ docker compose exec -T db pg_dump -U postgres inventario | gzip > $ARCH${NC}"
docker compose exec -T db pg_dump -U postgres inventario | gzip > "$ARCH" && chmod 600 "$ARCH"
ejecutar ls -lh backups/
bitacora "respaldo $ARCH"
ok "respaldo creado: $ARCH  (restaurar: gunzip -c $ARCH | docker compose exec -T db psql -U postgres -d inventario)"
