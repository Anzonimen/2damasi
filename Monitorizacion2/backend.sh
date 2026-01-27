#!/bin/bash

# =================================================================
# PROYECTO: Dashboard de Control VirtualBox (Nivel Supremo)
# AUTOR: Tú (Alumno de EducaMaX)
# DESCRIPCIÓN: Script Backend que actúa como puente entre la web y el sistema.
# =================================================================

PORT=8000

# --- BLOQUE 1: IMPRESIÓN DE BIENVENIDA ---
# Muestra información visual en la terminal al arrancar
echo "-----------------------------------------------------"
echo "  💀 SYSTEM ROOT: ACCESS GRANTED"
echo "  📡 LISTENING PORT: $PORT"
echo "  👁️  SPY_MODE: ENABLED (Screenshots allowed)"
echo "-----------------------------------------------------"

# --- BLOQUE 2: INICIO DEL SERVIDOR PYTHON ---
# Usamos Python3 (nativo en Ubuntu) para crear un servidor HTTP.
# Bash por sí solo es complicado para web, así que incrustamos Python aquí.
python3 -c "
import http.server
import socketserver
import subprocess   # Para ejecutar comandos de terminal (VBoxManage, free, etc.)
import json         # Para enviar datos a la web en formato legible
import urllib.parse # Para leer los parámetros de la URL (?name=Server1)
import os           # Para leer carga de CPU y gestionar archivos
import time         # Para hacer pausas técnicas
import base64       # Para convertir las imágenes (capturas) en texto y enviarlas por web

PORT = $PORT
SNAPSHOT_NAME = 'HackerDashboard_Snap' # Nombre fijo para nuestras copias de seguridad

# Clase principal que maneja las peticiones del navegador
class RequestHandler(http.server.SimpleHTTPRequestHandler):
    
    # --- FUNCIÓN: OBTENER ESTADÍSTICAS DEL PC REAL (HOST) ---
    def get_host_stats(self):
        # 1. RAM: Ejecuta 'free -m' en Linux para ver la memoria libre
        try:
            mem_output = subprocess.check_output(['free', '-m'], text=True).splitlines()[1].split()
            total_ram = int(mem_output[1])
            used_ram = int(mem_output[2])
            ram_percent = round((used_ram / total_ram) * 100, 1)
        except:
            ram_percent = 0

        # 2. CPU: Usa la librería OS para ver la carga de trabajo del sistema
        try:
            load = os.getloadavg()[0] # Carga del último minuto
            cpu_count = os.cpu_count() or 1
            # Calculamos porcentaje basado en núcleos
            cpu_percent = min(round((load / cpu_count) * 100, 1), 100) 
        except:
            cpu_percent = 0
            
        return {'cpu': cpu_percent, 'ram': ram_percent}

    # --- FUNCIÓN: OBTENER DETALLES TÉCNICOS DE LA VM ---
    def get_vm_extended_info(self, vm_name):
        # Ejecuta 'VBoxManage showvminfo' para sacar MAC, Tipo de SO, VRAM, etc.
        try:
            info = subprocess.check_output(['VBoxManage', 'showvminfo', vm_name, '--machinereadable'], text=True)
            data = {'ram': '?', 'cpus': '1', 'vram': '?', 'os': '?', 'mac': '?', 'vrde': 'OFF'}
            
            # Parseamos línea a línea buscando las claves que nos interesan
            for line in info.splitlines():
                if '=' in line:
                    key, val = line.split('=', 1)
                    val = val.strip('\"')
                    
                    if key == 'memory': data['ram'] = val
                    elif key == 'cpus': data['cpus'] = val
                    elif key == 'vram': data['vram'] = val
                    elif key == 'ostype': data['os'] = val
                    elif key == 'macaddress1': data['mac'] = val
                    elif key == 'vrde': data['vrde'] = val
                    
            return data
        except:
            return {}

    # --- CONTROLADOR PRINCIPAL (CUANDO LA WEB PIDE ALGO) ---
    def do_GET(self):
        # CONFIGURACIÓN CORS (CRÍTICO):
        # Permite que GitHub Pages (externo) hable con Localhost (interno)
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*') # 'Cualquiera puede entrar'
        self.end_headers()

        # Analizamos qué pide la web (ej: /start?name=Server1)
        parsed_path = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed_path.query)
        command = parsed_path.path.strip('/')
        
        vm_name = params.get('name', [''])[0]
        response = {}

        try:
            # --- CASO 1: ESTADO GENERAL (LOOP) ---
            if command == 'status':
                # Pregunta a VirtualBox qué máquinas existen
                result = subprocess.check_output(['VBoxManage', 'list', 'vms'], text=True)
                vms = []
                for line in result.splitlines():
                    parts = line.split('\"')
                    if len(parts) > 1:
                        name = parts[1]
                        
                        # Miramos si está 'running', 'paused' o 'stopped'
                        info_dump = subprocess.check_output(['VBoxManage', 'showvminfo', name, '--machinereadable'], text=True)
                        state = 'stopped'
                        if 'VMState=\"running\"' in info_dump: state = 'running'
                        elif 'VMState=\"paused\"' in info_dump: state = 'paused'
                        
                        # Obtenemos los detalles técnicos extra
                        details = self.get_vm_extended_info(name)
                        
                        vms.append({
                            'name': name, 
                            'status': state,
                            'specs': details
                        })
                
                # Devolvemos JSON con VMs + Salud del Host
                response = {'vms': vms, 'host': self.get_host_stats()}

            # --- CASO 2: COMANDOS DE ENERGÍA ---
            elif command == 'start' and vm_name:
                # --type headless significa 'sin ventana', para que no moleste en el servidor
                subprocess.run(['VBoxManage', 'startvm', vm_name, '--type', 'headless'], check=True)
                response = {'status': 'ok', 'msg': 'BOOT SEQUENCE INITIATED'}

            elif command == 'stop' and vm_name:
                # poweroff es como quitar el cable de corriente (brusco)
                subprocess.run(['VBoxManage', 'controlvm', vm_name, 'poweroff'], check=True)
                response = {'status': 'ok', 'msg': 'HARD POWER OFF EXECUTED'}
            
            elif command == 'acpi' and vm_name:
                # acpipowerbutton es como pulsar el botón de la torre (apagado suave)
                subprocess.run(['VBoxManage', 'controlvm', vm_name, 'acpipowerbutton'], check=True)
                response = {'status': 'ok', 'msg': 'ACPI SHUTDOWN SIGNAL SENT'}

            elif command == 'reset' and vm_name:
                subprocess.run(['VBoxManage', 'controlvm', vm_name, 'reset'], check=True)
                response = {'status': 'ok', 'msg': 'SYSTEM HARD RESET'}

            elif command == 'pause' and vm_name:
                # Congela la CPU de la VM
                subprocess.run(['VBoxManage', 'controlvm', vm_name, 'pause'], check=True)
                response = {'status': 'ok', 'msg': 'PROCESS FROZEN'}

            elif command == 'resume' and vm_name:
                # Descongela la CPU
                subprocess.run(['VBoxManage', 'controlvm', vm_name, 'resume'], check=True)
                response = {'status': 'ok', 'msg': 'PROCESS RESUMED'}

            # --- CASO 3: GESTIÓN DE TIEMPO (SNAPSHOTS) ---
            elif command == 'snapshot' and vm_name:
                # Borramos snapshot anterior para ahorrar espacio y creamos uno nuevo
                subprocess.run(['VBoxManage', 'snapshot', vm_name, 'delete', SNAPSHOT_NAME], stderr=subprocess.DEVNULL)
                time.sleep(0.5)
                subprocess.run(['VBoxManage', 'snapshot', vm_name, 'take', SNAPSHOT_NAME], check=True)
                response = {'status': 'ok', 'msg': 'SYSTEM STATE SAVED'}

            elif command == 'restore' and vm_name:
                # Restaurar requiere apagar la máquina primero
                subprocess.run(['VBoxManage', 'controlvm', vm_name, 'poweroff'], stderr=subprocess.DEVNULL)
                time.sleep(1)
                subprocess.run(['VBoxManage', 'snapshot', vm_name, 'restore', SNAPSHOT_NAME], check=True)
                response = {'status': 'ok', 'msg': 'TIMELINE RESTORED'}

            # --- CASO 4: ESPIONAJE (SCREENSHOT) ---
            elif command == 'screenshot' and vm_name:
                tmp_file = f'/tmp/{vm_name}_spy.png'
                # 1. VBox toma la foto y la guarda en temporal
                subprocess.run(['VBoxManage', 'controlvm', vm_name, 'screenshotpng', tmp_file], check=True)
                
                # 2. Leemos la imagen y la convertimos a Base64 (Texto)
                # Esto es necesario para enviar una imagen dentro de un JSON
                with open(tmp_file, 'rb') as img_file:
                    b64_string = base64.b64encode(img_file.read()).decode('utf-8')
                
                # 3. Borramos el archivo temporal
                os.remove(tmp_file)
                response = {'status': 'ok', 'image': b64_string, 'msg': 'VISUAL CAPTURE ACQUIRED'}

            else:
                response = {'status': 'error', 'msg': 'INVALID COMMAND SYNTAX'}

        except Exception as e:
            print(f'[ERROR] {e}')
            response = {'status': 'error', 'msg': str(e)}

        self.wfile.write(json.dumps(response).encode('utf-8'))
    
    # Maneja las peticiones 'OPTIONS' que hacen los navegadores modernos antes de conectar
    def do_OPTIONS(self):
        self.send_response(200, 'ok')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'X-Requested-With')
        self.end_headers()

# Arrancar el loop infinito del servidor
with socketserver.TCPServer(('', PORT), RequestHandler) as httpd:
    print(f'SERVER ONLINE. PID: {os.getpid()}')
    httpd.serve_forever()
"
