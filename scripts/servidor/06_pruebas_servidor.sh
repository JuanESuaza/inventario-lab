#!/usr/bin/env bash
# 06_pruebas_servidor.sh — Pruebas de los hitos en el servidor.
#   persistencia -> hito 3 · red -> hito 4 · limites -> hito 5 · roles -> perfiles de BD · todo
source "$(dirname "$0")/../comun.sh"
ir_a_raiz
requiere_docker
PRUEBA="${1:-todo}"
encabezado "Pruebas del servidor — $PRUEBA"
bitacora "prueba=$PRUEBA"
PSQL=(docker compose exec -T db psql -U postgres -d inventario -X -q -t -A)

persistencia() {
  titulo "HITO 3 · Persistencia: crear registro → docker compose down → up → el registro sigue"
  local cod="PERS-$(date +%H%M%S)"
  ejecutar "${PSQL[@]}" -c "INSERT INTO inventario.equipos (codigo,nombre,categoria,ubicacion,estado,actualizado_por) VALUES ('$cod','Registro de prueba de persistencia','otro','Servidor','disponible','06_pruebas');"
  echo "Registro creado: $cod"
  echo "IDs de contenedores ANTES:";   docker compose ps -q | cut -c1-12
  ejecutar docker compose down
  ejecutar docker volume ls --filter name=inventario_datos_pg
  ejecutar docker compose up -d --wait
  echo "IDs de contenedores DESPUÉS:"; docker compose ps -q | cut -c1-12
  ejecutar "${PSQL[@]}" -c "SELECT codigo, nombre, actualizado FROM inventario.equipos WHERE codigo='$cod';"
  if [ "$("${PSQL[@]}" -c "SELECT count(*) FROM inventario.equipos WHERE codigo='$cod';")" = "1" ]; then
    ok "el registro $cod sobrevivió a la recreación de los contenedores (volumen nombrado)"
  else
    falla "el registro $cod no está"
  fi
}

red() {
  titulo "HITO 4 · La base de datos solo es alcanzable desde la red interna"
  ejecutar docker network inspect inventario-lab_backend --format 'red backend: Internal={{.Internal}}'
  echo -e "${VERDE}\$ docker inspect inv-db --format 'puertos publicados de db: {{json .NetworkSettings.Ports}}'${NC}"
  docker inspect inv-db --format 'puertos publicados de db: {{json .NetworkSettings.Ports}}'
  echo -e "${VERDE}\$ sudo ss -tlnp | grep 5432${NC}"
  if sudo ss -tlnp | grep -q ':5432\b'; then falla "algo escucha en 5432 del host"; else ok "nada escucha en el puerto 5432 del host"; fi
  echo -e "${VERDE}\$ docker compose exec app python -c '<conectar a db:5432>'${NC}"
  docker compose exec -T app python -c "import socket; socket.create_connection(('db',5432),2); print('app -> db:5432 CONECTA (misma red backend)')"
  echo -e "${VERDE}\$ docker compose exec proxy nc -z -w2 db 5432${NC}"
  if docker compose exec -T proxy sh -c 'nc -z -w2 db 5432' 2>&1; then
    falla "el proxy alcanza a la base"
  else
    ok "proxy NO alcanza a db (no está en la red backend: ni resuelve el nombre)"
  fi
}

limites() {
  titulo "HITO 5 · Límites de recursos (cgroups)"
  for c in inv-proxy inv-app inv-db; do
    docker inspect "$c" --format '{{.Name}}: CPU={{.HostConfig.NanoCpus}} (1e9 = 1 CPU)  Memoria={{.HostConfig.Memory}} B  Swap={{.HostConfig.MemorySwap}} B  PIDs={{.HostConfig.PidsLimit}}'
  done
  echo; echo "Archivos del kernel (cgroup v2) del contenedor app:"
  ejecutar docker compose exec -T app sh -c 'echo "cpu.max=$(cat /sys/fs/cgroup/cpu.max)  memory.max=$(cat /sys/fs/cgroup/memory.max)  pids.max=$(cat /sys/fs/cgroup/pids.max)"'

  titulo "CPU: bucle infinito de 25 s dentro de app (límite 0,5 CPU)"
  docker compose exec -d app python -c "import time
t=time.time()+25
while time.time()<t: pass"
  sleep 8
  ejecutar docker stats --no-stream inv-proxy inv-app inv-db
  echo "→ inv-app no debe pasar de ~50 % de CPU aunque el bucle quiera el 100 %."

  titulo "Memoria: contenedor de prueba con el mismo límite (256 MB) intenta usar 400 MB"
  echo -e "${VERDE}\$ docker compose run --rm --no-deps app python -c \"x = b'1' * (400*1024*1024)\"${NC}"
  docker compose run --rm --no-deps app python -c "x = b'1' * (400*1024*1024); print('no debería llegar aquí')"
  local cod=$?
  echo "código de salida: $cod"
  if [ "$cod" = "137" ]; then ok "OOM killer: salida 137 = 128 + 9 (SIGKILL). El resto del servidor sigue intacto"; else falla "se esperaba 137 y salió $cod"; fi
  ejecutar docker compose ps
}

roles() {
  titulo "Roles de PostgreSQL con mínimo privilegio (Listado 2 del informe)"
  local Q=(docker compose exec -T db psql -d inventario -X)
  echo -e "${VERDE}\$ psql -U inv_lectura -c \"UPDATE equipos SET estado='baja'\"${NC}"
  "${Q[@]}" -U inv_lectura -c "UPDATE equipos SET estado='baja'" 2>&1
  echo -e "${VERDE}\$ psql -U inv_lectura -c \"SELECT hash FROM usuarios\"${NC}"
  "${Q[@]}" -U inv_lectura -c "SELECT hash FROM usuarios" 2>&1
  echo -e "${VERDE}\$ psql -U inv_app -c \"DELETE FROM auditoria\"${NC}"
  "${Q[@]}" -U inv_app -c "DELETE FROM auditoria" 2>&1
  echo -e "${VERDE}\$ psql -U inv_app -c \"CREATE TABLE x(i int)\"${NC}"
  "${Q[@]}" -U inv_app -c "CREATE TABLE x(i int)" 2>&1
  echo -e "${VERDE}\$ psql -U inv_lectura -c \"SELECT count(*) FROM equipos\"${NC}"
  "${Q[@]}" -U inv_lectura -t -c "SELECT count(*) FROM equipos" 2>&1
  echo "→ Esperado: los 4 primeros con 'permission denied'; el último sí funciona (solo lectura)."
}

case "$PRUEBA" in
  roles) roles ;;
  persistencia) persistencia ;;
  red) red ;;
  limites) limites ;;
  todo) red; roles; limites; persistencia ;;
  *) echo "Uso: $0 {persistencia|red|limites|roles|todo}"; exit 1 ;;
esac
