#!/bin/bash

echo "=============================================="
echo "  _  __                    ___           _        _ _         "
echo " | |/ /   _ _____  _____  |_ _|_ __  ___| |_ __ _| | | ___ _ __"
echo " | ' / | | |_  / |/ / _ \  | || '_ \/ __| __/ _\` | | |/ _ \ '__|"
echo " | . \ |_| |/ /|   < (_) | | || | | \__ \ || (_| | | |  __/ |   "
echo " |_|\_\__,_/___|_|\_\___/ |___|_| |_|___/\__\__,_|_|_|\___|_|   "
echo ""
echo "==============================================="
echo " WINGFO Kuzco & Ollama Inference Auto Installer"
echo "==============================================="

is_port_available() {
    port=$1
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
        return 1
    else
        return 0
    fi
}

find_available_port() {
    for port in $(seq $1 $2); do
        if is_port_available "$port"; then
            echo "$port"
            return 0
        fi
    done
    return 1
}

show_used_ports() {
    echo "Currently used ports (TCP):"
    echo "------------------------"
    ss -tuln | grep LISTEN | awk '{print $5}' | awk -F: '{print $NF}' | sort -n | uniq
    echo "------------------------"
}

check_system_requirements() {
    echo "=== Checking System Requirements ==="
    
    # Check RAM
    total_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_ram" -lt 4 ]; then
        echo "Warning: Your system has ${total_ram}GB RAM. Ollama recommends at least 4GB for optimal performance."
        echo "You can still proceed, but performance may be limited."
        read -p "Continue? (y/n): " continue_install
        if [[ "$continue_install" != "y" ]]; then
            echo "Installation cancelled."
            exit 1
        fi
    else
        echo "✓ RAM: ${total_ram}GB (sufficient)"
    fi
    
    # Check disk space
    available_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 10 ]; then
        echo "Warning: Low disk space (${available_space}GB available). Ollama models require significant space."
        read -p "Continue? (y/n): " continue_install
        if [[ "$continue_install" != "y" ]]; then
            echo "Installation cancelled."
            exit 1
        fi
    else
        echo "✓ Disk Space: ${available_space}GB available"
    fi
}

install_dependencies() {
    if ! command -v nc &> /dev/null; then
        echo "Installing netcat for port checking..."
        sudo apt-get install -y netcat
    fi

    if ! command -v curl &> /dev/null; then
        echo "Installing curl..."
        sudo apt-get install -y curl
    fi

    if ! command -v jq &> /dev/null; then
        echo "Installing jq for JSON processing..."
        sudo apt-get install -y jq
    fi
}

install_ollama() {
    echo "=== Installing Ollama ==="
    if ! command -v ollama &> /dev/null; then
        echo "Downloading and installing Ollama..."
        curl -fsSL https://ollama.ai/install.sh | sh
        
        # Start Ollama service
        sudo systemctl enable ollama
        sudo systemctl start ollama
        
        # Wait for Ollama to be ready
        echo "Waiting for Ollama to be ready..."
        sleep 10
        
        # Check if Ollama is running
        if ! systemctl is-active --quiet ollama; then
            echo "Starting Ollama manually..."
            nohup ollama serve > ~/ollama.log 2>&1 &
            sleep 5
        fi
    else
        echo "✓ Ollama already installed"
        if ! systemctl is-active --quiet ollama; then
            echo "Starting Ollama service..."
            sudo systemctl start ollama || nohup ollama serve > ~/ollama.log 2>&1 &
            sleep 5
        fi
    fi
}

setup_ollama_models() {
    echo "=== Setting up Ollama Models ==="
    echo "Available models:"
    echo "1. llama3.2:1b (Lightweight, ~1GB)"
    echo "2. llama3.2:3b (Balanced, ~2GB)"
    echo "3. llama3.1:8b (High quality, ~4.7GB)"
    echo "4. qwen2.5:7b (Alternative, ~4.4GB)"
    echo "5. mistral:7b (Popular choice, ~4.1GB)"
    
    read -p "Choose model (1-5) [default: 1]: " model_choice
    model_choice=${model_choice:-1}
    
    case $model_choice in
        1) model_name="llama3.2:1b" ;;
        2) model_name="llama3.2:3b" ;;
        3) model_name="llama3.1:8b" ;;
        4) model_name="qwen2.5:7b" ;;
        5) model_name="mistral:7b" ;;
        *) model_name="llama3.2:1b" ;;
    esac
    
    echo "Downloading model: $model_name (this may take several minutes...)"
    ollama pull "$model_name"
    
    if [ $? -eq 0 ]; then
        echo "✓ Model $model_name downloaded successfully"
    else
        echo "❌ Failed to download model. Trying with a smaller model..."
        ollama pull llama3.2:1b
        model_name="llama3.2:1b"
    fi
    
    echo "MODEL_NAME=$model_name" > ~/.ollama_config
}

create_ollama_proxy() {
    echo "=== Creating Ollama API Proxy ==="
    
    show_used_ports
    suggested_port=$(find_available_port 11000 12000)
    echo "Recommended available port: $suggested_port"
    read -p "Enter custom port for Ollama Proxy [default: $suggested_port]: " ollama_port
    ollama_port=${ollama_port:-$suggested_port}
    
    if ! is_port_available "$ollama_port"; then
        echo "Warning: Port $ollama_port is already in use."
        suggested_port=$(find_available_port 11000 12000)
        if [[ -n "$suggested_port" ]]; then
            echo "Using available port: $suggested_port"
            ollama_port=$suggested_port
        else
            echo "Could not find an available port in range 11000-12000."
            exit 1
        fi
    fi
    
    # Create Ollama proxy script
    cat > ~/ollama-proxy.py << 'EOL'
#!/usr/bin/env python3
import json
import requests
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import sys
import os

class OllamaProxyHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, model_name="llama3.2:1b", **kwargs):
        self.model_name = model_name
        super().__init__(*args, **kwargs)
    
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        
        try:
            # Parse incoming request
            request_data = json.loads(post_data.decode('utf-8'))
            
            # Convert to Ollama format
            ollama_request = {
                "model": self.model_name,
                "prompt": request_data.get("prompt", ""),
                "stream": False
            }
            
            # Send to Ollama
            response = requests.post(
                "http://localhost:11434/api/generate",
                json=ollama_request,
                timeout=60
            )
            
            if response.status_code == 200:
                ollama_response = response.json()
                
                # Convert back to expected format
                proxy_response = {
                    "response": ollama_response.get("response", ""),
                    "model": self.model_name,
                    "created_at": ollama_response.get("created_at", ""),
                    "done": ollama_response.get("done", True)
                }
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps(proxy_response).encode())
            else:
                self.send_error(500, f"Ollama error: {response.status_code}")
                
        except Exception as e:
            print(f"Error processing request: {e}")
            self.send_error(500, f"Internal server error: {str(e)}")
    
    def do_GET(self):
        if self.path == '/health':
            try:
                # Check Ollama health
                response = requests.get("http://localhost:11434/api/tags", timeout=5)
                if response.status_code == 200:
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({"status": "healthy", "model": self.model_name}).encode())
                else:
                    self.send_error(503, "Ollama not available")
            except:
                self.send_error(503, "Ollama not available")
        else:
            self.send_error(404, "Not found")
    
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

def run_proxy(port, model_name):
    def handler(*args, **kwargs):
        return OllamaProxyHandler(*args, model_name=model_name, **kwargs)
    
    server = HTTPServer(('0.0.0.0', port), handler)
    print(f"Ollama proxy running on port {port} with model {model_name}")
    server.serve_forever()

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 11435
    model_name = sys.argv[2] if len(sys.argv) > 2 else "llama3.2:1b"
    run_proxy(port, model_name)
EOL

    chmod +x ~/ollama-proxy.py
    
    # Get model name from config
    if [ -f ~/.ollama_config ]; then
        source ~/.ollama_config
    else
        MODEL_NAME="llama3.2:1b"
    fi
    
    # Start proxy in background
    echo "Starting Ollama proxy on port $ollama_port with model $MODEL_NAME..."
    nohup python3 ~/ollama-proxy.py $ollama_port $MODEL_NAME > ~/ollama-proxy.log 2>&1 &
    
    # Wait and test proxy
    sleep 5
    if curl -s "http://localhost:$ollama_port/health" > /dev/null; then
        echo "✓ Ollama proxy started successfully on port $ollama_port"
    else
        echo "❌ Failed to start Ollama proxy"
        exit 1
    fi
    
    echo "OLLAMA_PORT=$ollama_port" >> ~/.ollama_config
}

# Main installation process
check_system_requirements
install_dependencies

echo "=== Updating system ==="
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "=== Installing Docker ==="
    sudo apt install apt-transport-https ca-certificates curl software-properties-common -y
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update -y && sudo apt upgrade -y
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
    sudo systemctl enable docker
    sudo systemctl start docker
else
    echo "✓ Docker already installed"
fi

# Install Python3 and pip if not available
if ! command -v python3 &> /dev/null; then
    echo "Installing Python3..."
    sudo apt install python3 python3-pip -y
fi

# Install required Python packages
pip3 install requests

# Install and setup Ollama
install_ollama
setup_ollama_models
create_ollama_proxy

# Setup Kuzco Node
echo "=== Installing Kuzco Node ==="
cd ~
if [ ! -d "kuzco-installer-docker" ]; then
    git clone https://github.com/direkturcrypto/kuzco-installer-docker
fi
cd kuzco-installer-docker/kuzco-main

read -p "Enter KUZCO_WORKER from Kuzco dashboard: " kuzco_worker
read -p "Enter KUZCO_CODE from Kuzco dashboard: " kuzco_code

VPS_IP=$(curl -s ifconfig.me)
echo "=== Detected VPS IP: $VPS_IP ==="

# Get Ollama port from config
source ~/.ollama_config
OLLAMA_PORT=${OLLAMA_PORT:-11435}

echo "=== Updating nginx configuration ==="
cat > nginx.conf << EOL
server {
    listen $OLLAMA_PORT;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:$OLLAMA_PORT;
        proxy_buffering off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
EOL

echo "=== Updating docker-compose.yml configuration ==="
sed -i "s|KUZCO_WORKER: \"YOUR_WORKER_ID\"|KUZCO_WORKER: \"$kuzco_worker\"|g" docker-compose.yml
sed -i "s|KUZCO_CODE: \"YOUR_WORKER_CODE\"|KUZCO_CODE: \"$kuzco_code\"|g" docker-compose.yml

# Add Ollama endpoint to environment
echo "OLLAMA_ENDPOINT=http://localhost:$OLLAMA_PORT" >> .env

echo "=== Running Kuzco Node ==="
docker-compose up -d --build

# Create management script
echo "=== Creating Ollama manager script ==="
cat > ~/ollama-manager.sh << 'EOL'
#!/bin/bash

source ~/.ollama_config 2>/dev/null || true
OLLAMA_PORT=${OLLAMA_PORT:-11435}
MODEL_NAME=${MODEL_NAME:-"llama3.2:1b"}

case "$1" in
    start)
        echo "Starting Ollama services..."
        sudo systemctl start ollama || nohup ollama serve > ~/ollama.log 2>&1 &
        sleep 5
        nohup python3 ~/ollama-proxy.py $OLLAMA_PORT $MODEL_NAME > ~/ollama-proxy.log 2>&1 &
        echo "Ollama services started"
        ;;
    stop)
        echo "Stopping Ollama services..."
        pkill -f ollama-proxy.py
        sudo systemctl stop ollama || pkill -f "ollama serve"
        echo "Ollama services stopped"
        ;;
    status)
        echo "=== Ollama Service Status ==="
        if systemctl is-active --quiet ollama || pgrep -f "ollama serve" > /dev/null; then
            echo "✓ Ollama server is running"
        else
            echo "❌ Ollama server is not running"
        fi
        
        if pgrep -f ollama-proxy.py > /dev/null; then
            echo "✓ Ollama proxy is running on port $OLLAMA_PORT"
        else
            echo "❌ Ollama proxy is not running"
        fi
        
        echo "=== Model Status ==="
        if command -v ollama &> /dev/null; then
            ollama list
        fi
        ;;
    restart)
        echo "Restarting Ollama services..."
        $0 stop
        sleep 3
        $0 start
        ;;
    logs)
        echo "=== Ollama Server Logs ==="
        tail -20 ~/ollama.log 2>/dev/null || echo "No server logs found"
        echo "=== Ollama Proxy Logs ==="
        tail -20 ~/ollama-proxy.log 2>/dev/null || echo "No proxy logs found"
        ;;
    test)
        echo "Testing Ollama API..."
        curl -s "http://localhost:$OLLAMA_PORT/health" | jq . 2>/dev/null || echo "Health check failed"
        ;;
    models)
        echo "Available models:"
        ollama list
        ;;
    pull)
        if [ -z "$2" ]; then
            echo "Usage: $0 pull <model_name>"
            echo "Example: $0 pull llama3.2:3b"
        else
            ollama pull "$2"
        fi
        ;;
    ports)
        echo "Checking used ports..."
        ss -tuln | grep LISTEN
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart|logs|test|models|pull|ports}"
        echo ""
        echo "Commands:"
        echo "  start   - Start Ollama services"
        echo "  stop    - Stop Ollama services"
        echo "  status  - Check service status"
        echo "  restart - Restart services"
        echo "  logs    - Show recent logs"
        echo "  test    - Test API connectivity"
        echo "  models  - List installed models"
        echo "  pull    - Download a new model"
        echo "  ports   - Show used ports"
        exit 1
        ;;
esac
exit 0
EOL

chmod +x ~/ollama-manager.sh

# Final status check
echo "=============================================="
echo "=== Installation Complete! ==="
echo ""
echo "Configuration Summary:"
echo "• Ollama Model: $MODEL_NAME"
echo "• Ollama Proxy Port: $OLLAMA_PORT"
echo "• VPS IP: $VPS_IP"
echo ""
echo "Management Commands:"
echo "• Check status: ~/ollama-manager.sh status"
echo "• View logs: ~/ollama-manager.sh logs"
echo "• Test API: ~/ollama-manager.sh test"
echo "• Restart: ~/ollama-manager.sh restart"
echo ""
echo "Kuzco Logs:"
echo "• cd ~/kuzco-installer-docker/kuzco-main && docker-compose logs -f --tail 100"
echo ""
echo "Next Steps:"
echo "1. Wait a few minutes for services to fully initialize"
echo "2. Check status with: ~/ollama-manager.sh status"
echo "3. Monitor Kuzco dashboard for worker status"
echo "=============================================="

# Test the setup
echo "=== Running initial tests ==="
sleep 10
~/ollama-manager.sh test
