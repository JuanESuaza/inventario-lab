"""Inventario del Laboratorio — aplicación Flask (Reto 5, Sistemas Operacionales 2026-2)."""
import logging
import secrets
import sys
from datetime import timedelta
from functools import wraps

from flask import (Flask, abort, flash, g, redirect, render_template, request,
                   session, url_for)
from werkzeug.middleware.proxy_fix import ProxyFix
from werkzeug.security import check_password_hash, generate_password_hash

from . import bd

CATEGORIAS = ["computador", "redes", "electronica", "audiovisual", "otro"]
ESTADOS = ["disponible", "prestado", "mantenimiento", "baja"]

logging.basicConfig(stream=sys.stdout, level=logging.INFO,
                    format="%(levelname)s app %(message)s")
log = logging.getLogger("app")


def evento(nombre, **campos):
    """Registro en formato clave=valor (fácil de filtrar con grep)."""
    partes = [f"evento={nombre}"] + [f"{k}={v!r}" if isinstance(v, str) and " " in v else f"{k}={v}"
                                      for k, v in campos.items()]
    log.info(" ".join(partes))


def leer_secreto(ruta):
    with open(ruta, encoding="utf-8") as f:
        return f.read().strip()


def crear_app(config=None):
    app = Flask(__name__)
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1)

    cfg = bd.config_desde_entorno()
    app.config.update(
        SECRET_KEY=leer_secreto(cfg["flask_secret_file"]) if cfg.get("flask_secret_file") else secrets.token_hex(32),
        SESSION_COOKIE_SECURE=True,
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Strict",
        PERMANENT_SESSION_LIFETIME=timedelta(minutes=30),
        BD=cfg,
    )
    if config:
        app.config.update(config)

    # Falla rápido y con un mensaje claro si no hay base de datos (5 intentos)
    bd.esperar_bd(app.config["BD"], evento, log)
    asegurar_usuarios_iniciales(app)

    registrar_rutas(app)
    return app


def asegurar_usuarios_iniciales(app):
    cfg = app.config["BD"]
    iniciales = [("admin", "Administrador del laboratorio", "administrador", cfg.get("admin_password_file")),
                 ("consultor", "Consultor del laboratorio", "consultor", cfg.get("consultor_password_file"))]
    with bd.conectar(cfg) as con:
        for usuario, nombre, rol, archivo in iniciales:
            if not archivo:
                continue
            existe = con.execute("SELECT 1 FROM usuarios WHERE usuario = %s", (usuario,)).fetchone()
            if not existe:
                con.execute("INSERT INTO usuarios (usuario, nombre, rol, hash) VALUES (%s, %s, %s, %s)",
                            (usuario, nombre, rol, generate_password_hash(leer_secreto(archivo))))
                evento("usuario_creado", usuario=usuario, rol=rol)


# ---------------------------------------------------------------- utilidades de seguridad
def ip_cliente():
    return request.remote_addr or "-"


def auditar(accion, detalle=""):
    usuario = session.get("usuario", "anonimo")
    try:
        with bd.conectar(g.cfg_bd) as con:
            con.execute("INSERT INTO auditoria (usuario, accion, detalle, ip) VALUES (%s, %s, %s, %s)",
                        (usuario, accion, detalle, ip_cliente()))
    except Exception as e:  # la auditoría nunca debe tumbar la petición
        evento("auditoria_fallida", error=str(e))


def token_csrf():
    if "csrf" not in session:
        session["csrf"] = secrets.token_urlsafe(32)
    return session["csrf"]


def requiere_login(f):
    @wraps(f)
    def envoltura(*a, **kw):
        if "usuario" not in session:
            return redirect(url_for("login"))
        return f(*a, **kw)
    return envoltura


def requiere_rol(rol):
    def deco(f):
        @wraps(f)
        @requiere_login
        def envoltura(*a, **kw):
            if session.get("rol") != rol:
                detalle = f"{request.method} {request.path} requiere {rol}"
                evento("acceso_denegado", usuario=session.get("usuario"), ip=ip_cliente(), detalle=detalle)
                auditar("acceso_denegado", detalle)
                abort(403)
            return f(*a, **kw)
        return envoltura
    return deco


def validar_equipo(form):
    import re
    datos = {k: (form.get(k) or "").strip() for k in
             ("codigo", "nombre", "categoria", "ubicacion", "estado", "responsable")}
    datos["codigo"] = datos["codigo"].upper()
    errores = []
    if not re.fullmatch(r"[A-Z0-9-]{3,20}", datos["codigo"]):
        errores.append("Código: 3 a 20 caracteres (A-Z, 0-9, guion).")
    if not 2 <= len(datos["nombre"]) <= 120:
        errores.append("Nombre: entre 2 y 120 caracteres.")
    if datos["categoria"] not in CATEGORIAS:
        errores.append("Categoría no válida.")
    if not 2 <= len(datos["ubicacion"]) <= 80:
        errores.append("Ubicación: entre 2 y 80 caracteres.")
    if datos["estado"] not in ESTADOS:
        errores.append("Estado no válido.")
    if len(datos["responsable"]) > 80:
        errores.append("Responsable: máximo 80 caracteres.")
    datos["responsable"] = datos["responsable"] or None
    return datos, errores


# ---------------------------------------------------------------- rutas
def registrar_rutas(app):

    @app.before_request
    def antes():
        g.cfg_bd = app.config["BD"]
        session.permanent = True
        if request.method == "POST":
            enviado = request.form.get("csrf", "")
            if not enviado or not secrets.compare_digest(enviado, session.get("csrf", "")):
                evento("csrf_invalido", ip=ip_cliente(), ruta=request.path)
                abort(400)

    @app.context_processor
    def contexto():
        return {"csrf": token_csrf, "usuario": session.get("usuario"), "rol": session.get("rol")}

    @app.get("/health")
    def health():
        try:
            with bd.conectar(g.cfg_bd, timeout=2) as con:
                con.execute("SELECT 1")
            return {"estado": "ok", "bd": "ok"}, 200
        except Exception as e:
            evento("bd_no_disponible", origen="health", error=str(e).splitlines()[0])
            return {"estado": "error", "bd": "no disponible"}, 503

    @app.get("/")
    def inicio():
        return redirect(url_for("equipos"))

    @app.route("/login", methods=["GET", "POST"])
    def login():
        if request.method == "POST":
            usuario = request.form.get("usuario", "").strip().lower()
            clave = request.form.get("clave", "")
            with bd.conectar(g.cfg_bd) as con:
                fila = con.execute("SELECT usuario, rol, hash, activo FROM usuarios WHERE usuario = %s",
                                   (usuario,)).fetchone()
            if fila and fila[3] and check_password_hash(fila[2], clave):
                session.clear()
                session["usuario"], session["rol"] = fila[0], fila[1]
                token_csrf()
                evento("login_ok", usuario=fila[0], ip=ip_cliente(), detalle=f"rol={fila[1]}")
                auditar("login_ok", f"rol={fila[1]}")
                return redirect(url_for("equipos"))
            evento("login_fallido", usuario="anonimo", ip=ip_cliente(), detalle=f"usuario={usuario!r}")
            auditar("login_fallido", f"usuario={usuario}")
            flash("Usuario o contraseña incorrectos.")
            return render_template("login.html"), 401
        return render_template("login.html")

    @app.post("/logout")
    def logout():
        if "usuario" in session:
            auditar("logout")
        session.clear()
        return redirect(url_for("login"))

    @app.get("/equipos")
    @requiere_login
    def equipos():
        q = request.args.get("q", "").strip()
        with bd.conectar(g.cfg_bd) as con:
            if q:
                patron = f"%{q}%"
                filas = con.execute(
                    "SELECT id, codigo, nombre, categoria, ubicacion, estado, responsable, actualizado "
                    "FROM equipos WHERE codigo ILIKE %s OR nombre ILIKE %s OR ubicacion ILIKE %s "
                    "ORDER BY codigo", (patron, patron, patron)).fetchall()
            else:
                filas = con.execute(
                    "SELECT id, codigo, nombre, categoria, ubicacion, estado, responsable, actualizado "
                    "FROM equipos ORDER BY codigo").fetchall()
        return render_template("equipos.html", filas=filas, q=q)

    @app.route("/equipos/nuevo", methods=["GET", "POST"])
    @requiere_rol("administrador")
    def equipo_nuevo():
        datos, errores = {}, []
        if request.method == "POST":
            datos, errores = validar_equipo(request.form)
            if not errores:
                try:
                    with bd.conectar(g.cfg_bd) as con:
                        con.execute(
                            "INSERT INTO equipos (codigo, nombre, categoria, ubicacion, estado, responsable, "
                            "actualizado_por) VALUES (%s, %s, %s, %s, %s, %s, %s)",
                            (datos["codigo"], datos["nombre"], datos["categoria"], datos["ubicacion"],
                             datos["estado"], datos["responsable"], session["usuario"]))
                    evento("equipo_creado", usuario=session["usuario"], codigo=datos["codigo"], ip=ip_cliente())
                    auditar("equipo_creado", datos["codigo"])
                    return redirect(url_for("equipos"))
                except bd.errors.UniqueViolation:
                    errores.append("Ya existe un equipo con ese código.")
        return render_template("equipo_form.html", datos=datos, errores=errores, titulo="Nuevo equipo",
                               categorias=CATEGORIAS, estados=ESTADOS), (400 if errores else 200)

    @app.route("/equipos/<int:id_equipo>/editar", methods=["GET", "POST"])
    @requiere_rol("administrador")
    def equipo_editar(id_equipo):
        with bd.conectar(g.cfg_bd) as con:
            fila = con.execute("SELECT codigo, nombre, categoria, ubicacion, estado, responsable "
                               "FROM equipos WHERE id = %s", (id_equipo,)).fetchone()
        if not fila:
            abort(404)
        datos = dict(zip(("codigo", "nombre", "categoria", "ubicacion", "estado", "responsable"), fila))
        errores = []
        if request.method == "POST":
            datos, errores = validar_equipo(request.form)
            if not errores:
                try:
                    with bd.conectar(g.cfg_bd) as con:
                        con.execute(
                            "UPDATE equipos SET codigo=%s, nombre=%s, categoria=%s, ubicacion=%s, estado=%s, "
                            "responsable=%s, actualizado=now(), actualizado_por=%s WHERE id=%s",
                            (datos["codigo"], datos["nombre"], datos["categoria"], datos["ubicacion"],
                             datos["estado"], datos["responsable"], session["usuario"], id_equipo))
                    evento("equipo_editado", usuario=session["usuario"], codigo=datos["codigo"], ip=ip_cliente())
                    auditar("equipo_editado", datos["codigo"])
                    return redirect(url_for("equipos"))
                except bd.errors.UniqueViolation:
                    errores.append("Ya existe un equipo con ese código.")
        return render_template("equipo_form.html", datos=datos, errores=errores, titulo="Editar equipo",
                               categorias=CATEGORIAS, estados=ESTADOS), (400 if errores else 200)

    @app.post("/equipos/<int:id_equipo>/eliminar")
    @requiere_rol("administrador")
    def equipo_eliminar(id_equipo):
        with bd.conectar(g.cfg_bd) as con:
            fila = con.execute("DELETE FROM equipos WHERE id = %s RETURNING codigo", (id_equipo,)).fetchone()
        if not fila:
            abort(404)
        evento("equipo_eliminado", usuario=session["usuario"], codigo=fila[0], ip=ip_cliente())
        auditar("equipo_eliminado", fila[0])
        return redirect(url_for("equipos"))

    @app.get("/auditoria")
    @requiere_rol("administrador")
    def auditoria():
        with bd.conectar(g.cfg_bd) as con:
            filas = con.execute("SELECT momento, usuario, accion, detalle, ip FROM auditoria "
                                "ORDER BY id DESC LIMIT 200").fetchall()
        return render_template("auditoria.html", filas=filas)

    @app.errorhandler(400)
    @app.errorhandler(403)
    @app.errorhandler(404)
    def error_http(e):
        return render_template("error.html", codigo=e.code, mensaje=e.description), e.code
