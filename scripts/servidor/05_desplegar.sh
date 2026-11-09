#!/usr/bin/env bash
# 05_desplegar.sh — Genera .env, valida el Compose, construye la imagen y levanta el stack.
source "$(dirname "$0")/../comun.sh"
ir_a_raiz
requiere_docker
encabezado "Despliegue del stack"
bitacora "inicio"

for s in db_admin_password db_app_password db_lectura_password flask_secret admin_password consultor_password; do
  [ -s "secrets/$s.txt" ] || { falla "falta secrets/$s.txt: ejecute primero 04_secretos_y_tls.sh"; exit 1; }
done
chmod +x db/init/*.sh

titulo "1. Archivo .env (solo IP y puerto de publicación, nada secreto)"
printf 'BIND_IP=%s\nWEB_PORT=%s\n' "$SERVER_IP" "$WEB_PORT" > .env
ejecutar cat .env

titulo "2. Validar el docker-compose.yml"
ejecutar docker compose config --quiet && ok "docker-compose.yml válido"

titulo "3. Construir la imagen de la app y descargar las demás"
ejecutar docker compose build
ejecutar docker compose pull proxy db

titulo "4. Levantar el stack y esperar a que los 3 contenedores estén healthy"
ejecutar docker compose up -d --wait || { falla "el stack no quedó healthy; revise: docker compose logs --tail 30"; exit 1; }

titulo "5. Estado"
ejecutar docker compose ps
ejecutar docker network ls --filter name=inventario-lab
ejecutar docker volume ls --filter name=inventario_datos_pg
ejecutar curl -sk "https://$SERVER_IP:$WEB_PORT/health"; echo
ok "stack desplegado (hito 2)"
