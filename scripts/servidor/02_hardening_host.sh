#!/usr/bin/env bash
# 02_hardening_host.sh — SSH (puerto 2222, sin root, solo llave), fail2ban, sysctl y
# actualizaciones automáticas. REQUISITO: la llave del cliente ya debe estar en ~/.ssh/authorized_keys
source "$(dirname "$0")/../comun.sh"
encabezado "Hardening general del servidor"
bitacora "inicio"

if [ ! -s "$HOME/.ssh/authorized_keys" ]; then
  falla "No hay llaves en ~/.ssh/authorized_keys. Primero ejecute en docker-cli: scripts/cliente/01_preparar_cliente.sh"
  echo "Si se desactiva la contraseña sin llave, quedaría sin acceso por SSH (solo por la consola de VirtualBox)."
  exit 1
fi

titulo "1. SSH endurecido (/etc/ssh/sshd_config.d/00-hardening.conf)"
# Se llama 00-… porque sshd se queda con el PRIMER valor que lee: si se llamara 99-…,
# un 50-cloud-init.conf con "PasswordAuthentication yes" le ganaría.
sudo tee /etc/ssh/sshd_config.d/00-hardening.conf >/dev/null <<CONF
# Hardening Reto 5 — Ubuntu 26.04 usa activación por socket:
# tras cambiar Port: sudo systemctl daemon-reload && sudo systemctl restart ssh.socket
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
LogLevel VERBOSE
AllowGroups sudo
CONF
ejecutar sudo sshd -t && ok "sintaxis de sshd correcta"
ejecutar sudo systemctl daemon-reload
sudo systemctl restart ssh.socket 2>/dev/null || true
ejecutar sudo systemctl restart ssh
ejecutar sudo ss -tlnp | grep -E ":$SSH_PORT\b" && ok "sshd escucha en $SSH_PORT"

titulo "2. fail2ban para SSH (3 fallos en 10 min => bloqueo 1 h con UFW)"
sudo tee /etc/fail2ban/jail.d/inventario.local >/dev/null <<CONF
[sshd]
enabled  = true
port     = $SSH_PORT
backend  = systemd
maxretry = 3
findtime = 10m
bantime  = 1h
banaction = ufw
# La estación de administración (docker-cli) es de confianza: no se bloquea durante las pruebas
ignoreip = 127.0.0.1/8 ::1 $CLIENT_IP
CONF
ejecutar sudo systemctl enable --now fail2ban
ejecutar sudo systemctl restart fail2ban
sleep 2
ejecutar sudo fail2ban-client status sshd

titulo "3. Parámetros del kernel (sysctl)"
sudo tee /etc/sysctl.d/99-inventario-hardening.conf >/dev/null <<'CONF'
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
# OJO: net.ipv4.ip_forward se deja en 1 porque Docker lo necesita para enrutar a los contenedores
CONF
ejecutar sudo sysctl --system >/dev/null && ok "sysctl aplicado"

titulo "4. Actualizaciones automáticas de seguridad"
sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF
ejecutar sudo systemctl enable --now unattended-upgrades
ok "Hardening del host aplicado. Desde ahora: ssh -p $SSH_PORT $USER@$SERVER_IP"
