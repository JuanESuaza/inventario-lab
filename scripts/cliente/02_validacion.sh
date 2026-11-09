#!/usr/bin/env bash
# 02_validacion.sh — Pruebas de validación DESDE EL SEGUNDO NODO (docker-cli).
#   p1  HTTPS, /health, cabeceras y certificado
#   p2  perfiles: consultor 403 al modificar; administrador crea un equipo
#   p3  nmap: superficie expuesta
#   p4  conexión directa a PostgreSQL 5432 (debe fallar)
#   p5  SSH: puerto 22, root y contraseña rechazados; con llave funciona
#   p6  acceso web desde IP no autorizada (alias .99): bloqueado por DOCKER-USER   (usa sudo)
#   p7  el equipo creado en p2 sigue presente tras recrear el stack
#   p8  límite de intentos de login (429) y método DELETE (405)
#   hallazgo  solo un curl a /health (para la demostración del hallazgo de UFW)
# Las contraseñas se piden por teclado (no quedan en el historial).
source "$(dirname "$0")/../comun.sh"
URL="https://$SERVER_IP:$WEB_PORT"
PRUEBA="${1:-}"
encabezado "Validación desde el segundo nodo — $PRUEBA"
bitacora "prueba=$PRUEBA"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ULTIMO="$HOME/.inventario_ultimo_equipo"

pedir() { local var=$1 quien=$2; if [ -z "${!var:-}" ]; then read -rsp "Contraseña de $quien: " "$var"; echo; fi; }

# Inicia sesión; deja la cookie en $TMP/$1.jar y el token CSRF en la variable CSRF
iniciar_sesion() {
  local quien=$1 clave=$2 jar="$TMP/$1.jar" tok codigo
  tok=$(curl -sk -c "$jar" "$URL/login" | sed -n 's/.*name="csrf" value="\([^"]*\)".*/\1/p' | head -1)
  codigo=$(curl -sk -b "$jar" -c "$jar" -o /dev/null -w '%{http_code}' \
           --data-urlencode "csrf=$tok" --data-urlencode "usuario=$quien" --data-urlencode "clave=$clave" "$URL/login")
  CSRF=$(curl -sk -b "$jar" "$URL/equipos" | sed -n 's/.*name="csrf" value="\([^"]*\)".*/\1/p' | head -1)
  echo "login $quien → HTTP $codigo $( [ "$codigo" = 302 ] && echo '(correcto)' || echo '(FALLÓ)')"
}
http() { curl -sk -b "$TMP/$1.jar" -o /dev/null -w '%{http_code}' "${@:2}"; }

p1() {
  titulo "P1 · HTTPS a $URL"
  ejecutar curl -sk -w '\nHTTP %{http_code}\n' "$URL/health"
  echo -e "${VERDE}\$ curl -skI $URL/login${NC}"
  curl -skI "$URL/login" | grep -iE '^(HTTP|strict-transport|x-frame|x-content|content-security|referrer|server)'
  echo -e "${VERDE}\$ curl -s -o /dev/null -w '%{http_code}' http://$SERVER_IP:$WEB_PORT/  (HTTP sin TLS)${NC}"
  curl -s -o /dev/null -m 5 -w 'HTTP %{http_code}\n' "http://$SERVER_IP:$WEB_PORT/" || true
  echo -e "${VERDE}\$ openssl s_client -connect $SERVER_IP:$WEB_PORT${NC}"
  echo | openssl s_client -connect "$SERVER_IP:$WEB_PORT" 2>/dev/null | grep -E '^(subject|issuer)=|Protocol|Cipher is' | head -4
}

p2() {
  pedir CLAVE_ADMIN admin; pedir CLAVE_CONSULTOR consultor
  titulo "P2 · Perfil CONSULTOR (solo consulta)"
  iniciar_sesion consultor "$CLAVE_CONSULTOR"
  echo "ver inventario         GET  /equipos            → $(http consultor "$URL/equipos")"
  echo "formulario nuevo       GET  /equipos/nuevo      → $(http consultor "$URL/equipos/nuevo")"
  echo "crear equipo           POST /equipos/nuevo      → $(http consultor --data-urlencode "csrf=$CSRF" -d 'codigo=HACK-1' "$URL/equipos/nuevo")"
  echo "eliminar equipo        POST /equipos/1/eliminar → $(http consultor --data-urlencode "csrf=$CSRF" "$URL/equipos/1/eliminar")"
  echo "ver auditoría          GET  /auditoria          → $(http consultor "$URL/auditoria")"
  titulo "P2 · Perfil ADMINISTRADOR (gestiona)"
  iniciar_sesion admin "$CLAVE_ADMIN"
  local cod="DEMO-$(date +%H%M%S)"
  echo "crear equipo $cod  POST /equipos/nuevo    → $(http admin --data-urlencode "csrf=$CSRF" -d "codigo=$cod" -d 'nombre=Equipo creado en la demo' -d 'categoria=redes' -d 'ubicacion=Sala 301' -d 'estado=disponible' "$URL/equipos/nuevo") (302 = creado)"
  if curl -sk -b "$TMP/admin.jar" "$URL/equipos?q=$cod" | grep -q "$cod"; then ok "el administrador creó $cod y aparece en el inventario"; echo "$cod" > "$ULTIMO"; else falla "no se encontró $cod"; fi
  echo "ver auditoría          GET  /auditoria          → $(http admin "$URL/auditoria")"
  echo "→ Esperado: consultor 200/403/403/403/403; administrador 302 y 200."
}

p3() {
  titulo "P3 · Superficie expuesta (nmap)"
  ejecutar nmap -Pn -p 22,80,443,2222,5432,8000,8080,8443 "$SERVER_IP"
  echo "→ Esperado: solo 2222 (SSH) y 8443 (HTTPS) abiertos."
}

p4() {
  titulo "P4 · Conexión directa a PostgreSQL"
  ejecutar nc -zv -w 3 "$SERVER_IP" 5432 || true
  ejecutar nc -zv -w 3 docker-srv 5432 || true
  echo -e "${VERDE}\$ psql \"host=$SERVER_IP port=5432 user=postgres connect_timeout=3\"${NC}"
  psql "host=$SERVER_IP port=5432 user=postgres dbname=inventario connect_timeout=3" -c 'select 1' 2>&1 | head -2 || true
  echo "→ Esperado: rechazada o sin respuesta. La base no tiene puertos publicados."
}

p5() {
  local admin; read -rp "Usuario administrador en docker-srv [$USER]: " admin; admin="${admin:-$USER}"
  titulo "P5 · SSH endurecido"
  echo -e "${VERDE}\$ ssh -p 22 $admin@$SERVER_IP${NC}"
  ssh -p 22 -o ConnectTimeout=4 -o BatchMode=yes "$admin@$SERVER_IP" true 2>&1 | tail -1
  echo -e "${VERDE}\$ ssh -p $SSH_PORT root@$SERVER_IP${NC}"
  ssh -p "$SSH_PORT" -o ConnectTimeout=4 -o BatchMode=yes "root@$SERVER_IP" true 2>&1 | tail -1
  echo -e "${VERDE}\$ ssh -p $SSH_PORT -o PubkeyAuthentication=no $admin@$SERVER_IP   (solo contraseña)${NC}"
  ssh -p "$SSH_PORT" -o ConnectTimeout=4 -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive -o BatchMode=yes "$admin@$SERVER_IP" true 2>&1 | tail -1
  echo -e "${VERDE}\$ ssh -p $SSH_PORT $admin@$SERVER_IP 'hostname; whoami'   (con llave)${NC}"
  ssh -p "$SSH_PORT" -o ConnectTimeout=4 -o BatchMode=yes "$admin@$SERVER_IP" 'hostname; whoami' 2>&1
  echo "→ Esperado: 22 rechazado/sin respuesta; root y contraseña: Permission denied; con llave: docker-srv."
}

p6() {
  local iface="${2:-$(interfaz_proyecto)}"
  titulo "P6 · Acceso web desde una IP NO autorizada ($IP_NO_AUTORIZADA en $iface)"
  ejecutar sudo ip addr add "$IP_NO_AUTORIZADA/24" dev "$iface"
  echo -e "${VERDE}\$ curl --interface $IP_NO_AUTORIZADA -m 5 $URL/health${NC}"
  curl -sk --interface "$IP_NO_AUTORIZADA" -m 5 -o /dev/null -w 'desde .99 → HTTP %{http_code} (000 = sin respuesta)\n' "$URL/health" || true
  echo -e "${VERDE}\$ curl --interface $CLIENT_IP -m 5 $URL/health${NC}"
  curl -sk --interface "$CLIENT_IP" -m 5 -o /dev/null -w 'desde .20 → HTTP %{http_code}\n' "$URL/health" || true
  ejecutar sudo ip addr del "$IP_NO_AUTORIZADA/24" dev "$iface"
  echo "→ En el servidor, el bloqueo queda en el log del kernel:  sudo journalctl -k | grep 'DOCKER-USER BLOQUEO' | tail -3"
}

p7() {
  pedir CLAVE_ADMIN admin
  titulo "P7 · Persistencia vista desde el cliente"
  local cod; cod="$(cat "$ULTIMO" 2>/dev/null)"
  [ -z "$cod" ] && { falla "primero ejecute p2 (crea el equipo de prueba)"; exit 1; }
  iniciar_sesion admin "$CLAVE_ADMIN"
  if curl -sk -b "$TMP/admin.jar" "$URL/equipos?q=$cod" | grep -q "$cod"; then ok "el equipo $cod, creado antes de recrear el stack, sigue presente"; else falla "$cod no aparece"; fi
}

p8() {
  titulo "P8 · Hardening de la aplicación: límite de login (Nginx) y métodos no permitidos"
  echo -e "${VERDE}\$ for i in \$(seq 1 9); do curl -sk -o /dev/null -w '%{http_code} ' -d 'usuario=x&clave=y' $URL/login; done${NC}"
  for i in $(seq 1 9); do curl -sk -o /dev/null -w '%{http_code} ' -d 'usuario=x&clave=y' "$URL/login"; done; echo
  echo "→ 400 = rechazado por falta de token CSRF; 429 = Nginx cortó por exceso de intentos (10/min, ráfaga 5)."
  echo -e "${VERDE}\$ curl -sk -o /dev/null -w '%{http_code}' -X DELETE $URL/${NC}"
  curl -sk -o /dev/null -w 'HTTP %{http_code}\n' -X DELETE "$URL/"
  echo "→ En el servidor:  docker compose logs proxy | grep 'limiting requests' | tail -2"
}

hallazgo() { ejecutar curl -sk -m 5 -o /dev/null -w 'HTTP %{http_code}\n' "$URL/health"; }

case "$PRUEBA" in
  p1|p2|p3|p4|p5|p7|p8|hallazgo) "$PRUEBA" ;;
  p6) p6 "$@" ;;
  todas) p1; p2; p3; p4; p5; p7 ;;
  *) echo "Uso: $0 {p1|p2|p3|p4|p5|p6 [interfaz]|p7|p8|hallazgo|todas}"; exit 1 ;;
esac
