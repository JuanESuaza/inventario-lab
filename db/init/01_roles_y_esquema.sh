#!/bin/sh
# 01_roles_y_esquema.sh — Se ejecuta UNA SOLA VEZ, cuando el volumen de datos está vacío
# (mecanismo /docker-entrypoint-initdb.d de la imagen oficial de PostgreSQL).
#
# Crea el esquema y dos roles de base de datos con privilegios mínimos:
#   inv_app     -> usado por la aplicación: lee y modifica equipos; solo AGREGA a la auditoría.
#   inv_lectura -> perfil de reportes: solo SELECT. No ve las credenciales de usuarios.
# El superusuario "postgres" queda únicamente para administración; la app nunca lo usa.
#
# IMPORTANTE: como este script solo corre al inicializar el volumen, cambiar después el
# archivo de secreto NO cambia la contraseña guardada en la base (ver incidente simulado).
set -eu

APP_PW="$(cat /run/secrets/db_app_password)"
RO_PW="$(cat /run/secrets/db_lectura_password)"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v app_pw="$APP_PW" -v ro_pw="$RO_PW" -v db="$POSTGRES_DB" <<'EOSQL'
-- ---------- Roles ----------
CREATE ROLE inv_app     LOGIN PASSWORD :'app_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 20;
CREATE ROLE inv_lectura LOGIN PASSWORD :'ro_pw'  NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 5;

-- Nadie se conecta a la base salvo los roles autorizados
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"db" TO inv_app, inv_lectura;
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- ---------- Esquema ----------
CREATE SCHEMA inventario AUTHORIZATION postgres;

CREATE TABLE inventario.usuarios (
    id       serial PRIMARY KEY,
    usuario  text UNIQUE NOT NULL CHECK (usuario ~ '^[a-z][a-z0-9_]{2,30}$'),
    nombre   text NOT NULL,
    rol      text NOT NULL CHECK (rol IN ('administrador', 'consultor')),
    hash     text NOT NULL,
    activo   boolean NOT NULL DEFAULT true,
    creado   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inventario.equipos (
    id          serial PRIMARY KEY,
    codigo      text UNIQUE NOT NULL CHECK (codigo ~ '^[A-Z0-9-]{3,20}$'),
    nombre      text NOT NULL CHECK (length(nombre) BETWEEN 2 AND 120),
    categoria   text NOT NULL CHECK (categoria IN ('computador', 'redes', 'electronica', 'audiovisual', 'otro')),
    ubicacion   text NOT NULL CHECK (length(ubicacion) BETWEEN 2 AND 80),
    estado      text NOT NULL CHECK (estado IN ('disponible', 'prestado', 'mantenimiento', 'baja')),
    responsable text CHECK (responsable IS NULL OR length(responsable) <= 80),
    actualizado timestamptz NOT NULL DEFAULT now(),
    actualizado_por text
);

-- Bitácora de auditoría: la aplicación puede agregar, nunca modificar ni borrar.
CREATE TABLE inventario.auditoria (
    id      bigserial PRIMARY KEY,
    momento timestamptz NOT NULL DEFAULT now(),
    usuario text,
    accion  text NOT NULL,
    detalle text,
    ip      text
);

-- Datos iniciales de ejemplo
INSERT INTO inventario.equipos (codigo, nombre, categoria, ubicacion, estado, responsable, actualizado_por) VALUES
  ('PC-001',  'Computador Dell OptiPlex 7010', 'computador',  'Sala 301', 'disponible',    NULL,        'sistema'),
  ('PC-002',  'Computador Lenovo ThinkCentre', 'computador',  'Sala 301', 'mantenimiento', 'Soporte TI','sistema'),
  ('SW-001',  'Switch Cisco Catalyst 2960',    'redes',       'Rack A',   'disponible',    NULL,        'sistema'),
  ('OSC-001', 'Osciloscopio Rigol DS1054Z',    'electronica', 'Lab 2',    'prestado',      'Grupo 4',   'sistema'),
  ('VB-001',  'Video beam Epson PowerLite',    'audiovisual', 'Sala 302', 'disponible',    NULL,        'sistema');

-- ---------- Privilegios ----------
GRANT USAGE ON SCHEMA inventario TO inv_app, inv_lectura;
GRANT SELECT, INSERT, UPDATE, DELETE ON inventario.equipos   TO inv_app;
GRANT SELECT, INSERT, UPDATE         ON inventario.usuarios  TO inv_app;
GRANT SELECT, INSERT                 ON inventario.auditoria TO inv_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA inventario TO inv_app;
GRANT SELECT ON inventario.equipos, inventario.auditoria TO inv_lectura;

ALTER ROLE inv_app     SET search_path = inventario;
ALTER ROLE inv_lectura SET search_path = inventario;
EOSQL

echo "01_roles_y_esquema: roles inv_app e inv_lectura y esquema inventario creados"
