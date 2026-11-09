#!/usr/bin/env bash
# 07_incidente.sh — Incidente simulado: rotación INCOMPLETA de la contraseña de inv_app.
#   provocar  -> cambia el secreto y recrea la app SIN cambiar la clave en PostgreSQL
#   diagnosticar -> corre los comandos de investigación (los mismos que se muestran en vivo)
#   resolver  -> rotación coordinada: ALTER ROLE con el valor del secreto nuevo + reinicio
#   revertir  -> alternativa: vuelve al secreto anterior
source "$(dirname "$0")/../comun.sh"
ir_a_raiz
requiere_docker
ACCION="${1:-}"
encabezado "Incidente simulado — $ACCION"
bitacora "accion=$ACCION"
SECRETO=secrets/db_app_password.txt
ANTERIOR=secrets/.db_app_password.anterior

case "$ACCION" in
provocar)
  titulo "Un integrante 'rota' la contraseña de inv_app solo en el archivo de secreto"
  # Se guarda el secreto original (solo la primera vez) para poder revertir
  [ -f "$ANTERIOR" ] || { cp "$SECRETO" "$ANTERIOR" && chmod 400 "$ANTERIOR"; }
  chmod u+w "$SECRETO"; openssl rand -hex 24 > "$SECRETO"; chmod 444 "$SECRETO"
  ejecutar ls -l --time-style=+%H:%M:%S "$SECRETO"
  ejecutar docker compose up -d --force-recreate --no-deps app
  echo; echo "Listo. En unos 15 s la app entra en bucle. Observe:  docker compose ps"
  ;;
diagnosticar)
  ejecutar docker compose ps
  ejecutar docker inspect inv-app --format 'Estado={{.State.Status}} Reinicios={{.RestartCount}} Salida={{.State.ExitCode}} OOM={{.State.OOMKilled}}'
  ejecutar docker compose logs --tail 4 app
  ejecutar docker compose logs --tail 3 db
  ejecutar docker compose logs --tail 3 proxy
  ejecutar ls -l --time-style=+%H:%M:%S "$SECRETO"
  ;;
resolver)
  titulo "Rotación coordinada: la base adopta la contraseña del secreto nuevo"
  # La contraseña viaja por la entrada estándar (printf es interno de bash): no queda
  # en el historial ni en la lista de procesos.
  echo -e "${VERDE}\$ (\\set pw <secreto nuevo>; ALTER ROLE inv_app PASSWORD :'pw';) | docker compose exec -T db psql -U postgres -d inventario${NC}"
  { printf "\\set pw '%s'\n" "$(cat "$SECRETO")"; echo "ALTER ROLE inv_app PASSWORD :'pw';"; } \
    | docker compose exec -T db psql -U postgres -d inventario -X -q -v ON_ERROR_STOP=1 \
    && ok "contraseña de inv_app actualizada en PostgreSQL"
  ejecutar docker compose restart app
  ejecutar docker compose up -d --wait
  ejecutar docker compose ps
  ejecutar docker inspect inv-app --format 'Reinicios={{.RestartCount}} Salida={{.State.ExitCode}}'
  ejecutar docker compose logs --tail 3 app
  rm -f "$ANTERIOR"
  ;;
revertir)
  [ -f "$ANTERIOR" ] || { falla "no hay secreto anterior guardado"; exit 1; }
  chmod u+w "$SECRETO"; cp "$ANTERIOR" "$SECRETO"; chmod 444 "$SECRETO"; rm -f "$ANTERIOR"
  ejecutar docker compose up -d --force-recreate --no-deps --wait app
  ejecutar docker compose ps
  ;;
*)
  echo "Uso: $0 {provocar|diagnosticar|resolver|revertir}"; exit 1 ;;
esac
