#!/usr/bin/env bash
# 03_firewall.sh — Firewall en dos etapas:
#   ./03_firewall.sh ufw          -> UFW: deny por defecto, solo SSH 2222 desde la red del proyecto
#   ./03_firewall.sh docker-user  -> reglas en la cadena DOCKER-USER (/etc/ufw/after.rules)
#   ./03_firewall.sh hallazgo     -> demuestra que "ufw deny 8443" NO bloquea el puerto de Docker
#   ./03_firewall.sh estado       -> muestra UFW e iptables DOCKER-USER
source "$(dirname "$0")/../comun.sh"
MODO="${1:-}"
IFACE="$(interfaz_proyecto)"
encabezado "Firewall — modo: ${MODO:-?}  (interfaz del proyecto: ${IFACE:-no encontrada})"
bitacora "modo=$MODO"

case "$MODO" in
ufw)
  ejecutar sudo ufw --force reset
  ejecutar sudo ufw default deny incoming
  ejecutar sudo ufw default allow outgoing
  ejecutar sudo ufw limit from "$RED_PROYECTO" to any port "$SSH_PORT" proto tcp comment 'SSH administracion'
  ejecutar sudo ufw logging on
  ejecutar sudo ufw --force enable
  ejecutar sudo ufw status verbose
  ;;
hallazgo)
  titulo "Se agrega 'ufw deny $WEB_PORT' y se prueba desde docker-cli: el puerto SIGUE respondiendo"
  ejecutar sudo ufw deny "$WEB_PORT"/tcp
  ejecutar sudo ufw status numbered
  echo
  echo "Ahora en docker-cli ejecute:  curl -sk -o /dev/null -w '%{http_code}\n' https://$SERVER_IP:$WEB_PORT/health"
  echo "Si responde 200, UFW no está filtrando el puerto publicado por Docker (va por FORWARD, no por INPUT)."
  echo "Para ver por qué:  sudo iptables -t nat -S DOCKER | grep $WEB_PORT   y   sudo iptables -S FORWARD | head"
  ;;
docker-user)
  [ -z "$IFACE" ] && { falla "No encontré una interfaz con IP de $RED_PROYECTO"; exit 1; }
  # Se quita el 'deny' de la prueba del hallazgo, si existe (no sirve para Docker)
  sudo ufw --force delete deny "$WEB_PORT"/tcp >/dev/null 2>&1 || true
  sudo cp /etc/ufw/after.rules "/etc/ufw/after.rules.bak.$(date +%Y%m%d%H%M%S)"
  # Elimina un bloque anterior (idempotente)
  sudo sed -i '/# BEGIN INVENTARIO-LAB DOCKER-USER/,/# END INVENTARIO-LAB DOCKER-USER/d' /etc/ufw/after.rules
  PERMITIR=""
  for ipok in $WEB_IPS_AUTORIZADAS; do
    PERMITIR+="-A DOCKER-USER -i $IFACE -s $ipok -p tcp --dport $WEB_PORT -j RETURN"$'\n'
  done
  sudo tee -a /etc/ufw/after.rules >/dev/null <<RULES
# BEGIN INVENTARIO-LAB DOCKER-USER
# -----------------------------------------------------------------------------------------
# Docker publica puertos con reglas DNAT propias: el tráfico hacia un contenedor pasa por la
# cadena FORWARD y NO por INPUT, así que "ufw allow/deny" NO lo controla. La cadena DOCKER-USER
# es el punto que Docker reserva para reglas del administrador y que evalúa antes que las suyas.
# Aquí se permite el puerto web solo desde las IPs autorizadas y se descarta todo lo demás.
# -----------------------------------------------------------------------------------------
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -i docker0 -j RETURN
-A DOCKER-USER -i br-+ -j RETURN
${PERMITIR}-A DOCKER-USER -m limit --limit 6/min -j LOG --log-prefix "[DOCKER-USER BLOQUEO] "
-A DOCKER-USER -j DROP
COMMIT
# END INVENTARIO-LAB DOCKER-USER
RULES
  ejecutar sudo ufw reload
  ejecutar sudo iptables -S DOCKER-USER
  ok "DOCKER-USER: $WEB_PORT solo desde $WEB_IPS_AUTORIZADAS por $IFACE; el resto se registra y descarta"
  ;;
estado)
  ejecutar sudo ufw status verbose
  ejecutar sudo iptables -S DOCKER-USER
  ;;
*)
  echo "Uso: $0 {ufw|hallazgo|docker-user|estado}"; exit 1 ;;
esac
