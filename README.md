# Inventario del Laboratorio — Reto 5: Contenedorización de servicios (Docker)

Sistemas Operacionales (12997) · Universidad El Bosque · 2026-2 · Docente: Ing. Samuel Galindo Pinzón
Equipo: David Felipe Bejarano Montes · Oscar Samuel Oviedo Montealegre · Juan Esteban Suaza Martinez · Jhoan Daniel Bautista

Aplicación web (Flask + gunicorn) para el inventario de un laboratorio, desplegada con **Docker Compose**
en tres contenedores — `proxy` (Nginx, TLS), `app` (Flask) y `db` (PostgreSQL 17) — sobre Ubuntu Server 26.04 LTS,
con validación desde un segundo nodo.

```
docker-cli (.20) ──HTTPS 8443──► [proxy] ──red frontend──► [app] ──red backend (internal)──► [db] ── volumen inventario_datos_pg
                 ──SSH 2222────► host docker-srv (.10)
```

## Estructura

| Ruta | Contenido |
|---|---|
| `docker-compose.yml` | Stack: 3 servicios, 2 redes, 1 volumen nombrado, 6 secretos, límites y hardening |
| `app/` | Código de la aplicación, `Dockerfile`, `gunicorn.conf.py` |
| `proxy/` | Configuración de Nginx (`default.conf`, `proxy_headers.inc`); `certs/` se genera |
| `db/init/` | Script de inicialización: esquema y roles de mínimo privilegio (solo corre con el volumen vacío) |
| `secrets/` | Se genera con el script 04 (nunca se sube a git) |
| `scripts/servidor/` | 01 Docker · 02 hardening host · 03 firewall · 04 secretos/TLS · 05 desplegar · 06 pruebas · 07 incidente · 08 monitoreo · 09 verificar hardening · 10 respaldo |
| `scripts/cliente/` | 01 preparar el segundo nodo · 02 pruebas de validación P1–P8 |
| `config.env` | IPs y puertos del laboratorio |
| `docs/GUIA_IMPLEMENTACION.md` | Paso a paso en las VMs y qué captura sale de cada paso |

## Uso rápido

```bash
# docker-srv
scripts/servidor/01_instalar_docker.sh          # luego cerrar sesión y volver a entrar
# docker-cli
scripts/cliente/01_preparar_cliente.sh
# docker-srv
scripts/servidor/02_hardening_host.sh
scripts/servidor/03_firewall.sh ufw
scripts/servidor/04_secretos_y_tls.sh
scripts/servidor/05_desplegar.sh
scripts/servidor/03_firewall.sh docker-user
# docker-cli
scripts/cliente/02_validacion.sh todas
```

Todos los scripts imprimen hostname, usuario y fecha, y registran sus acciones en
`/var/log/inventario-lab-bitacora.log`.
