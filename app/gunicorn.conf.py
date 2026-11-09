# gunicorn.conf.py
bind = "0.0.0.0:8000"
workers = 2
# La app se carga en el proceso maestro: si no logra conectarse a la base, el maestro
# termina con código 1 y Docker lo ve (base del incidente simulado).
preload_app = True
worker_tmp_dir = "/dev/shm"      # el sistema de archivos del contenedor es de solo lectura
timeout = 30
accesslog = None                 # el registro de accesos lo lleva Nginx
errorlog = "-"
loglevel = "info"
