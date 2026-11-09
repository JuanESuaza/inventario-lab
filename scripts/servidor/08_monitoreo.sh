#!/usr/bin/env bash
# 08_monitoreo.sh — Panorama de observabilidad: estado, recursos, eventos, accesos y auditoría.
#   (sin argumento: una foto)   seguir -> logs en vivo de app y proxy
source "$(dirname "$0")/../comun.sh"
ir_a_raiz
requiere_docker
if [ "${1:-}" = "seguir" ]; then exec docker compose logs -f --tail 5 app proxy; fi
encabezado "Monitoreo del servicio"
bitacora "foto de monitoreo"

titulo "1. Estado y salud";   ejecutar docker compose ps
for c in inv-proxy inv-app inv-db; do
  docker inspect "$c" --format '{{.Name}}  salud={{.State.Health.Status}}  reinicios={{.RestartCount}}  salida={{.State.ExitCode}}  OOM={{.State.OOMKilled}}'
done
titulo "2. Recursos";         ejecutar docker stats --no-stream inv-proxy inv-app inv-db
titulo "3. Eventos de la app";  ejecutar docker compose logs --tail 8 app
titulo "4. Accesos HTTP (proxy)"; ejecutar docker compose logs --tail 6 proxy
titulo "5. Auditoría de negocio (últimos 10)"
ejecutar docker compose exec -T db psql -U postgres -d inventario -X -c \
  "SELECT to_char(momento,'YYYY-MM-DD HH24:MI:SS') AS momento, usuario, accion, detalle, ip FROM inventario.auditoria ORDER BY id DESC LIMIT 10;"
titulo "6. Motor Docker (eventos de la última hora)"
ejecutar docker events --since 60m --until 0s --filter type=container --format '{{.Time}} {{.Actor.Attributes.name}} {{.Action}}' | tail -n 10
ejecutar sudo journalctl -u docker --no-pager -n 5
