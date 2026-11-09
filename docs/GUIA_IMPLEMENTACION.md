# Guía de implementación en las VMs — Reto 5 (Docker)

Orden pensado para terminar hoy. Cada paso dice **dónde** se ejecuta (🖥️ docker-srv / 💻 docker-cli) y **qué captura** sale para el informe. Tiempo total aproximado: 1,5 a 2 horas (la mayor parte es descarga de paquetes e imágenes).

> Todas las capturas deben mostrar terminal, hostname y fecha. Los scripts imprimen un encabezado con los tres datos, y el paso 0.4 pone la fecha en el prompt.

---

## Fase 0 · Preparar las dos máquinas (≈ 25 min)

### 0.1 VirtualBox: adaptadores de red
En la VM base (apagada): **Configuración → Red**
- Adaptador 1: **NAT** (Internet para descargar paquetes e imágenes).
- Adaptador 2: **Adaptador solo-anfitrión** (`VirtualBox Host-Only Ethernet Adapter`, red 192.168.56.0/24).

### 0.2 Preparar la base y clonar
Encender la VM base y ejecutar:
```bash
sudo apt update && sudo apt -y upgrade
sudo apt -y install openssh-server git unzip
```
Apagar y **clonar** (clic derecho → Clonar → *Clon completo* → política MAC: **Generar nuevas direcciones MAC**). Una queda como **docker-srv** y la otra como **docker-cli**. Con 3 GB de RAM para el servidor y 1 GB para el cliente es suficiente.

### 0.3 En cada VM: nombre, IP fija e identidad propia
🖥️ en docker-srv (en docker-cli, lo mismo con `docker-cli` y `192.168.56.20`):
```bash
sudo hostnamectl set-hostname docker-srv
ip -br a                       # anote el nombre de la 2.ª interfaz (normalmente enp0s8)
sudo tee /etc/netplan/60-proyecto.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    enp0s8:
      dhcp4: false
      addresses: [192.168.56.10/24]
EOF
sudo chmod 600 /etc/netplan/60-proyecto.yaml && sudo netplan apply
# Solo en el CLON: identidad propia (si no, ambas VMs comparten machine-id y llaves SSH)
sudo rm /etc/machine-id && sudo systemd-machine-id-setup
sudo rm /etc/ssh/ssh_host_* && sudo dpkg-reconfigure openssh-server
```
Verificar desde docker-cli: `ping -c 3 192.168.56.10`.

### 0.4 Prompt con fecha (en ambas VMs)
```bash
echo "PS1='\[\e[1;32m\]\u@\h\[\e[0m\] [\D{%Y-%m-%d %H:%M:%S}] \w\\$ '" >> ~/.bashrc && source ~/.bashrc
```

### 0.5 Copiar el repositorio a las dos VMs
**Opción A (recomendada, también sirve para el Anexo D):** subir la carpeta `inventario-lab` a un repositorio de GitHub y en cada VM:
```bash
git clone https://github.com/<usuario>/inventario-lab.git ~/inventario-lab
```
**Opción B:** desde el computador anfitrión (PowerShell), antes del hardening:
```powershell
scp inventario-lab.zip juan@192.168.56.10:~/
scp inventario-lab.zip juan@192.168.56.20:~/
```
y en cada VM: `unzip inventario-lab.zip -d ~ `.

Después, en ambas:
```bash
cd ~/inventario-lab && chmod +x scripts/*.sh scripts/*/*.sh db/init/*.sh
```
Si sus IPs no son .10 y .20, cambie `config.env` en las dos VMs antes de seguir.

---

## Fase 1 · Instalar Docker (≈ 10 min)

🖥️ `scripts/servidor/01_instalar_docker.sh`
Luego **cerrar sesión y volver a entrar** (para que el grupo docker tenga efecto) y verificar: `docker ps` sin sudo.

📸 **Figura 4**: final de la salida (versiones de Docker y Compose + `getent group docker` con un solo miembro).
📝 Anote para la Tabla 6: `docker version --format '{{.Server.Version}}'`, `docker compose version`, `nproc`, `free -h`.

---

## Fase 2 · Llave SSH y hardening del host (≈ 10 min)

1. 💻 `scripts/cliente/01_preparar_cliente.sh` → pide la contraseña del usuario del servidor **una vez** y copia la llave.
2. 🖥️ `scripts/servidor/02_hardening_host.sh` → SSH pasa al puerto **2222**, sin root y solo con llave; fail2ban; sysctl; actualizaciones automáticas.
3. 🖥️ `scripts/servidor/03_firewall.sh ufw`
4. 💻 comprobar que se sigue entrando: `ssh -p 2222 juan@192.168.56.10 hostname`

> ⚠️ Si algo sale mal con SSH, no pasa nada: se entra por la consola de VirtualBox.

---

## Fase 3 · Secretos, TLS y despliegue (≈ 15 min)

🖥️
```bash
scripts/servidor/04_secretos_y_tls.sh      # anote las contraseñas de admin y consultor
scripts/servidor/05_desplegar.sh           # descarga imágenes y construye la app (tarda)
```
📸 **Figura 5**: salida de `05_desplegar.sh` desde "Estado": `docker compose ps` con los 3 **healthy**, redes y volumen.

---

## Fase 4 · El hallazgo de UFW y la corrección con DOCKER-USER (≈ 10 min)

1. 🖥️ `scripts/servidor/03_firewall.sh hallazgo` (agrega `ufw deny 8443`)
2. 💻 `scripts/cliente/02_validacion.sh hallazgo` → **responde 200 aunque UFW lo niega**.
   📸 **Figura nueva (hallazgo)**: las dos terminales lado a lado.
3. 🖥️ `scripts/servidor/03_firewall.sh docker-user` (quita el deny inútil y crea las reglas)
4. 💻 `scripts/cliente/02_validacion.sh p6` → desde .99 **000** (sin respuesta) y desde .20 **200**.
   📸 **Figura 12**: `03_firewall.sh estado` (iptables -S DOCKER-USER) + salida de p6.

---

## Fase 5 · Pruebas de los hitos (≈ 20 min)

| # | Dónde | Comando | Figura del informe |
|---|---|---|---|
| 1 | 💻 | `scripts/cliente/02_validacion.sh p2` | Fig. 9 (perfiles) |
| 2 | 🖥️ | `scripts/servidor/06_pruebas_servidor.sh roles` | reemplaza el Listado 2 |
| 3 | 🖥️ | `scripts/servidor/06_pruebas_servidor.sh red` | Fig. 7 (con la de p4) |
| 4 | 💻 | `scripts/cliente/02_validacion.sh p4` | Fig. 7 |
| 5 | 🖥️ | `scripts/servidor/06_pruebas_servidor.sh persistencia` | Fig. 6 |
| 6 | 💻 | `scripts/cliente/02_validacion.sh p7` | Fig. 6 (vista desde el cliente) |
| 7 | 🖥️ | `scripts/servidor/06_pruebas_servidor.sh limites` | Fig. 8 · anote el % de CPU |
| 8 | 💻 | `scripts/cliente/02_validacion.sh p1`, `p3`, `p5` | Fig. 16 |
| 9 | 💻 | `scripts/cliente/02_validacion.sh p8` | reemplaza el Listado 3 |
| 10 | 🖥️ | `scripts/servidor/09_verificar_hardening.sh` | Figura nueva en §7.1 y §7.3 |
| 11 | 🖥️ | `scripts/servidor/08_monitoreo.sh` | Fig. 13 (reemplaza el Listado 4) |

---

## Fase 6 · Incidente simulado (≈ 10 min)

💻 dejar corriendo en el cliente:
```bash
watch -n2 "curl -sk -o /dev/null -w '%{http_code}' https://192.168.56.10:8443/health"
```
🖥️
```bash
scripts/servidor/07_incidente.sh provocar
sleep 30; docker compose ps                 # app en Restarting
scripts/servidor/07_incidente.sh diagnosticar
scripts/servidor/07_incidente.sh resolver
```
📸 **Síntoma**: el `watch` del cliente en 502 + `docker compose ps` con *Restarting*.
📸 **Figura 15**: salida de `diagnosticar` (reemplaza el Listado 5).
📸 **Verificación**: salida de `resolver` (3 healthy) + `watch` de nuevo en 200.
📝 Anote: número de reinicios, hora de inicio y de recuperación.

---

## Fase 7 · Cierre (≈ 5 min)

🖥️ `scripts/servidor/10_respaldo.sh`
🖥️ y 💻 `sudo cat /var/log/inventario-lab-bitacora.log` → base del **Anexo A** (agregar a mano los errores que tuvieron y cómo los resolvieron).

---

## Si algo falla

| Síntoma | Qué revisar |
|---|---|
| `permission denied ... docker.sock` | No cerró sesión después del script 01. |
| `05_desplegar.sh` falla al construir | Sin Internet en la VM: revisar el adaptador NAT (`ping -c2 8.8.8.8`). |
| db no queda healthy | `docker compose logs --tail 30 db`. Si cambió secretos después del primer arranque: `docker compose down -v` (borra los datos) y `05` de nuevo. |
| proxy no queda healthy | `docker compose logs --tail 30 proxy`; revisar que existan `proxy/certs/servidor.crt` y `.key`. |
| app con `password authentication failed` sin haber provocado el incidente | Igual que db: los secretos cambiaron después de crear el volumen. `07_incidente.sh resolver`. |
| p6 responde 200 desde .99 | No se aplicó `03_firewall.sh docker-user`, o `ufw` se reinició con `ufw` (eso borra el bloque): repetir `docker-user`. |
| La prueba de memoria no da 137 | `docker inspect inv-app --format '{{.HostConfig.MemorySwap}}'` debe ser igual al límite (268435456). |
