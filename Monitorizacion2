#!/bin/bash

# --- NIVEL 2: BACKEND DE CONTROL ---
# Este script levanta un servidor local que escucha peticiones del Dashboard
# y ejecuta comandos de VirtualBox en tu máquina.

PORT=8000

echo "-----------------------------------------------------"
echo "  🚀 INICIANDO BACKEND DE CONTROL DE SERVIDORES"
echo "  📡 Escuchando en: http://localhost:$PORT"
echo "  🛠️  Funciones: Start, Stop, Reboot, Status"
echo "-----------------------------------------------------"

# Usamos Python3 (preinstalado en Ubuntu) para crear un servidor HTTP capaz de manejar CORS
# Esto permite que tu GitHub Pages (internet) hable con tu PC (local)

python3 -c "
import http.server
import socketserver
import subprocess
import json
import urllib.parse

PORT = $PORT

class RequestHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        # 1. Configurar Cabeceras CORS (Vital para que funcione desde GitHub Pages)
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*') # Permite acceso desde cualquier lado
        self.end_headers()

        # 2. Analizar la petición (Ruta y Parámetros)
        parsed_path = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed_path.query)
        command = parsed_path.path.strip('/') # start, stop, status, etc.
        
        vm_name = params.get('name', [''])[0]
        response = {}

        # 3. Lógica de Control de VirtualBox
        try:
            if command == 'status':
                # Devuelve el estado de TODAS las máquinas
                result = subprocess.check_output(['VBoxManage', 'list', 'vms'], text=True)
                vms = []
                for line in result.splitlines():
                    parts = line.split('\"')
                    if len(parts) > 1:
                        name = parts[1]
                        # Consultar estado individual
                        info = subprocess.check_output(['VBoxManage', 'showvminfo', name, '--machinereadable'], text=True)
                        state = 'stopped'
                        if 'VMState=\"running\"' in info:
                            state = 'running'
                        vms.append({'name': name, 'status': state})
                response = {'vms': vms}

            elif command == 'start' and vm_name:
                print(f'[CMD] Iniciando {vm_name}...')
                subprocess.run(['VBoxManage', 'startvm', vm_name, '--type', 'headless'], check=True)
                response = {'status': 'ok', 'message': f'{vm_name} Iniciado'}

            elif command == 'stop' and vm_name:
                print(f'[CMD] Apagando {vm_name}...')
                subprocess.run(['VBoxManage', 'controlvm', vm_name, 'poweroff'], check=True)
                response = {'status': 'ok', 'message': f'{vm_name} Apagado'}
            
            elif command == 'reboot' and vm_name:
                print(f'[CMD] Reiniciando {vm_name}...')
                # Intentamos apagar y luego encender
                subprocess.run(['VBoxManage', 'controlvm', vm_name, 'poweroff'], stderr=subprocess.DEVNULL)
                import time
                time.sleep(1) # Espera técnica
                subprocess.run(['VBoxManage', 'startvm', vm_name, '--type', 'headless'], check=True)
                response = {'status': 'ok', 'message': f'{vm_name} Reiniciado'}

            else:
                response = {'status': 'error', 'message': 'Comando desconocido o falta nombre'}

        except Exception as e:
            print(f'[ERROR] {e}')
            response = {'status': 'error', 'message': str(e)}

        # 4. Enviar respuesta al Dashboard (Frontend)
        self.wfile.write(json.dumps(response).encode('utf-8'))
    
    # Manejar peticiones vacías del navegador (Pre-flight)
    def do_OPTIONS(self):
        self.send_response(200, 'ok')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'X-Requested-With')
        self.end_headers()

# Iniciar el servidor
with socketserver.TCPServer(('', PORT), RequestHandler) as httpd:
    print(f'Servidor activo. Pulsa Ctrl+C para detener.')
    httpd.serve_forever()
"
