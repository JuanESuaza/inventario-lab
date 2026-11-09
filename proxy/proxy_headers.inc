# Cabeceras hacia la app. X-Forwarded-For se REEMPLAZA (no se concatena) para que
# un cliente no pueda falsificar su IP en la auditoría.
proxy_set_header Host              $host;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $remote_addr;
proxy_set_header X-Forwarded-Proto https;
proxy_connect_timeout 3s;
proxy_read_timeout    30s;
