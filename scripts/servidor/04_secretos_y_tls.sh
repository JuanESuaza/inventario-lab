#!/usr/bin/env bash
# 04_secretos_y_tls.sh — Genera los 6 secretos aleatorios y el certificado TLS autofirmado.
# No sobrescribe nada que ya exista (para regenerar: borrar el archivo a mano, con cuidado).
source "$(dirname "$0")/../comun.sh"
ir_a_raiz
encabezado "Secretos y certificado TLS"
bitacora "inicio"

titulo "1. Secretos (directorio 700; archivos 444 para que los lean los usuarios de cada contenedor)"
# Nota: Compose (sin Swarm) monta el archivo tal cual con sus permisos; postgres (uid 70) y la
# app (uid 10001) deben poder leerlo. Lo protege el directorio secrets/ con permisos 700.
mkdir -p secrets && chmod 700 secrets
gen() { local f="secrets/$1.txt"; if [ -s "$f" ]; then echo "  ya existe: $f"; else openssl rand -hex "$2" > "$f"; chmod 444 "$f"; echo "  creado:    $f"; fi; }
gen db_admin_password 24
gen db_app_password 24
gen db_lectura_password 24
gen flask_secret 32
gen admin_password 8
gen consultor_password 8
ejecutar ls -l secrets/

titulo "2. Certificado TLS autofirmado (CN=docker-srv, SAN IP:$SERVER_IP)"
mkdir -p proxy/certs
if [ -s proxy/certs/servidor.crt ]; then
  echo "  ya existe proxy/certs/servidor.crt"
else
  openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
    -keyout proxy/certs/servidor.key -out proxy/certs/servidor.crt \
    -subj "/C=CO/O=Universidad El Bosque/OU=Reto 5/CN=docker-srv" \
    -addext "subjectAltName=DNS:docker-srv,IP:$SERVER_IP" 2>/dev/null
  # La llave solo la lee el usuario de Nginx sin privilegios (uid 101 en la imagen)
  sudo chown 101:101 proxy/certs/servidor.key && sudo chmod 400 proxy/certs/servidor.key
  chmod 644 proxy/certs/servidor.crt
fi
ejecutar ls -l proxy/certs/
ejecutar openssl x509 -in proxy/certs/servidor.crt -noout -subject -dates -ext subjectAltName

titulo "3. Contraseñas iniciales de la aplicación (guárdelas; NO las muestre en la sustentación)"
echo "  admin:     $(cat secrets/admin_password.txt)"
echo "  consultor: $(cat secrets/consultor_password.txt)"
ok "secretos y certificado listos"
