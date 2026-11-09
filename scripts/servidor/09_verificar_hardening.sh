#!/usr/bin/env bash
# 09_verificar_hardening.sh — Evidencia del hardening general y del específico de Docker.
source "$(dirname "$0")/../comun.sh"
ir_a_raiz
encabezado "Verificación de hardening"
bitacora "verificación"

titulo "HOST · Firewall";  ejecutar sudo ufw status verbose
titulo "HOST · SSH efectivo"
ejecutar sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|authenticationmethods|maxauthtries|allowgroups|x11forwarding) '
titulo "HOST · fail2ban";   ejecutar sudo fail2ban-client status sshd
titulo "HOST · actualizaciones"
ejecutar sh -c "apt list --upgradable 2>/dev/null | tail -n +2 | wc -l | xargs echo 'paquetes pendientes:'"
ejecutar systemctl is-active unattended-upgrades
ejecutar cat /etc/apt/apt.conf.d/20auto-upgrades
titulo "HOST · sysctl"
ejecutar sysctl kernel.kptr_restrict kernel.dmesg_restrict net.ipv4.tcp_syncookies net.ipv4.conf.all.rp_filter net.ipv4.conf.all.accept_redirects
titulo "DOCKER · grupo docker (equivale a root: solo el administrador)"; ejecutar getent group docker
titulo "DOCKER · demonio";  ejecutar cat /etc/docker/daemon.json
docker info --format 'SecurityOptions={{.SecurityOptions}}  LiveRestore={{.LiveRestoreEnabled}}  LoggingDriver={{.LoggingDriver}}'
titulo "DOCKER · firewall de Docker"; ejecutar sudo iptables -S DOCKER-USER
titulo "CONTENEDORES · usuario, solo lectura, capabilities, no-new-privileges"
for c in inv-proxy inv-app inv-db; do
  docker inspect "$c" --format '{{.Name}}: User={{if .Config.User}}{{.Config.User}}{{else}}(root al arrancar){{end}} ReadOnly={{.HostConfig.ReadonlyRootfs}} CapDrop={{.HostConfig.CapDrop}} CapAdd={{.HostConfig.CapAdd}} SecOpt={{.HostConfig.SecurityOpt}}'
done
echo; echo "UID real de los procesos de cada contenedor (0 sería root):"
for c in inv-proxy inv-app inv-db; do
  echo "  $c:"; docker top "$c" -o uid,pid,comm | sed 's/^/    /'
done
titulo "CONTENEDORES · secretos fuera de las variables de entorno"
echo -e "${VERDE}\$ docker inspect inv-app --format '{{json .Config.Env}}'${NC}"
docker inspect inv-app --format '{{json .Config.Env}}' | tr ',' '\n' | grep -E 'PASSWORD|SECRET'
echo "→ solo aparecen RUTAS (/run/secrets/...), nunca las contraseñas."
