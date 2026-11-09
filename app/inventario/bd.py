"""Acceso a PostgreSQL. Una conexión por operación: suficiente para el volumen del laboratorio."""
import os
import sys
import time

import psycopg
from psycopg import errors  # noqa: F401  (se reexporta para la app)


def config_desde_entorno():
    def leer(ruta):
        with open(ruta, encoding="utf-8") as f:
            return f.read().strip()
    return {
        "host": os.environ.get("DB_HOST", "db"),
        "dbname": os.environ.get("DB_NAME", "inventario"),
        "user": os.environ.get("DB_USER", "inv_app"),
        "password": leer(os.environ["DB_PASSWORD_FILE"]) if os.environ.get("DB_PASSWORD_FILE") else "",
        "flask_secret_file": os.environ.get("FLASK_SECRET_FILE"),
        "admin_password_file": os.environ.get("ADMIN_PASSWORD_FILE"),
        "consultor_password_file": os.environ.get("CONSULTOR_PASSWORD_FILE"),
    }


def conectar(cfg, timeout=5):
    return psycopg.connect(host=cfg["host"], dbname=cfg["dbname"], user=cfg["user"],
                           password=cfg["password"], connect_timeout=timeout,
                           application_name="inventario-app")


def esperar_bd(cfg, evento, log, intentos=5, pausa=2):
    """Intenta conectarse varias veces; si no puede, aborta el arranque con código 1."""
    ultimo = ""
    for i in range(1, intentos + 1):
        try:
            with conectar(cfg, timeout=3) as con:
                con.execute("SELECT 1")
            evento("bd_conectada", intento=i, host=cfg["host"], usuario_bd=cfg["user"])
            return
        except psycopg.OperationalError as e:
            ultimo = " ".join(str(e).split())
            log.warning(f"evento=bd_no_disponible intento={i}/{intentos} error='{ultimo}'")
            time.sleep(pausa)
    log.critical(f"evento=arranque_abortado motivo='{ultimo}'")
    sys.exit(1)
