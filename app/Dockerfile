# Imagen de la aplicación "Inventario del Laboratorio"
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /srv/app

# Dependencias primero: aprovecha la caché de capas si solo cambia el código
COPY requirements.txt .
RUN pip install -r requirements.txt

# Código propiedad de root: el proceso (uid 10001) puede leerlo pero no modificarlo
COPY . .
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser \
 && chmod -R go-w /srv/app

USER 10001:10001
EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=3s --start-period=30s --retries=3 \
  CMD ["python", "-c", "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status == 200 else 1)"]

CMD ["gunicorn", "-c", "gunicorn.conf.py", "wsgi:app"]
