#!/bin/bash

echo "=============================================="
echo " Ollama + Kuzco Troubleshooting & Optimizer"
echo "=============================================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_system_resources() {
    echo "=== System Resource Check ==="
    
    # Memory check
    total_ram=$(free -h | awk '/^Mem:/{print $2}')
    used_ram=$(free -h | awk '/^Mem:/{print $3}')
    available_ram=$(free -h | awk '/^Mem:/{print $7}')
    
    log_info "RAM Status: Total: $total_ram, Used: $used_ram, Available: $available_ram"
    
    # Disk space check
    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    available_space=$(df -h / | awk 'NR==2 {print $4}')
    
    log_info "Disk Usage: $disk_usage% used, $available_space available"
    
    if [ "$disk_usage" -gt 85 ]; then
        log_warn "Disk usage is high (${disk_usage}%). Consider cleaning up."
    fi
    
    # CPU load
    cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    log_info "CPU Load Average: $cpu_load"
    
    # GPU check (if available)
    if command -v nvidia-smi &> /dev/null; then
        log_info "GPU detected:"
        nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv,noheader,nounits
    else
        log_info "No GPU detected (CPU-only mode)"
    fi
}

check_services() {
    echo "=== Service Status Check ==="
    
    # Check Ollama service
    if systemctl is-active --quiet ollama; then
        log_info "✓ Ollama systemd service is running"
    elif pgrep -f "ollama serve" > /dev/null; then
        log_info "✓ Ollama is running (manual process)"
    else
        log_error "❌ Ollama is not running"
        echo "Try: sudo systemctl start ollama"
        echo "Or: nohup ollama serve > ~/ollama.log 2>&1 &"
    fi
    
    # Check Ollama proxy
    if pgrep -f "ollama-proxy.py" > /dev/null; then
        log_info "✓ Ollama proxy is running"
    else
        log_error "❌ Ollama proxy is not running"
        echo "Try: ~/ollama-manager.sh start"
    fi
    
    # Check Docker
    if systemctl is-active --quiet docker; then
        log_info "✓ Docker service is running"
    else
        log_error "❌ Docker is not running"
        echo "Try: sudo systemctl start docker"
    fi
    
    # Check Kuzco containers
    if [ -d ~/kuzco-installer-docker/kuzco-main ]; then
        cd ~/kuzco-installer-docker/kuzco-main
        running_containers=$(docker-compose ps --services --filter "status=running" | wc -l)
        total_containers=$(docker-compose ps --services | wc -l)
        
        if [ "$running_containers" -eq "$total_containers" ] && [ "$total_containers" -gt 0 ]; then
            log_info "✓ Kuzco containers are running ($running_containers/$total_containers)"
        else
            log_warn "⚠ Kuzco containers status: $running_containers/$total_containers running"
            echo "Try: docker-compose up -d"
        fi
    else
        log_error "❌ Kuzco installation directory not found"
    fi
}

test_ollama_connectivity() {
    echo "=== Ollama Connectivity Test ==="
    
    source ~/.ollama_config 2>/dev/null || true
    OLLAMA_PORT=${OLLAMA_PORT:-11435}
    
    # Test Ollama direct API
    if curl -s --max-time 5 "http://localhost:11434/api/tags" > /dev/null; then
        log_info "✓ Ollama API is responding on port 11434"
    else
        log_error "❌ Ollama API not responding on port 11434"
    fi
    
    # Test proxy
    if curl -s --max-time 5 "http://localhost:$OLLAMA_PORT/health" > /dev/null; then
        log_info "✓ Ollama proxy is responding on port $OLLAMA_PORT"
    else
        log_error "❌ Ollama proxy not responding on port $OLLAMA_PORT"
    fi
    
    # Test model inference
    echo "Testing model inference..."
    response=$(curl -s --max-time 30 -X POST "http://localhost:11434/api/generate" \
        -H "Content-Type: application/json" \
        -d '{"model":"'"${MODEL_NAME:-llama3.2:1b}"'","prompt":"Hello","stream":false}' 2>/dev/null)
    
    if echo "$response" | jq '.response' > /dev/null 2>&1; then
        log_info "✓ Model inference test successful"
    else
        log_error "❌ Model inference test failed"
        echo "Response: $response"
    fi
}

optimize_system() {
    echo "=== System Optimization ==="
    
    read -p "Apply system optimizations? (y/n): " apply_opt
    if [[ "$apply_opt" != "y" ]]; then
        return
    fi
    
    # Increase file descriptor limits
    echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
    echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf
    
    # Optimize network settings
    sudo tee -a /etc/sysctl.conf << EOL
# Network optimizations for Ollama
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOL
    
    # Apply sysctl changes
    sudo sysctl -p
    
    # Create swap if needed (for low memory systems)
    if [ $(free -m | awk '/^Mem:/{print $2}') -lt 4096 ] && [ ! -f /swapfile ]; then
        log_info "Creating 2GB swap file for low memory system..."
        sudo fallocate -l 2G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
    
    log_info "System optimizations applied"
}

clean_logs() {
    echo "=== Log Cleanup ==="
    
    log_size=$(du -sh ~/ollama*.log 2>/dev/null | awk '{sum += $1} END {print sum}' || echo "0")
    echo "Current log size: ${log_size}"
    
    read -p "Clean old logs? (y/n): " clean_logs
    if [[ "$clean_logs" == "y" ]]; then
        # Keep only last 1000 lines of each log
        for log_file in ~/ollama*.log; do
            if [ -f "$log_file" ]; then
                tail -1000 "$log_file" > "${log_file}.tmp" && mv "${log_file}.tmp" "$log_file"
                log_info "Cleaned $log_file"
            fi
        done
        
        # Clean Docker logs
        if command -v docker &> /dev/null; then
            docker system prune -f --volumes
            log_info "Cleaned Docker system"
        fi
    fi
}

benchmark_model() {
    echo "=== Model Performance Benchmark ==="
    
    source ~/.ollama_config 2>/dev/null || true
    MODEL_NAME=${MODEL_NAME:-"llama3.2:1b"}
    
    echo "Testing model: $MODEL_NAME"
    echo "Running benchmark..."
    
    start_time=$(date +%s.%N)
    
    response=$(curl -s --max-time 60 -X POST "http://localhost:11434/api/generate" \
        -H "Content-Type: application/json" \
        -d '{"model":"'"$MODEL_NAME"'","prompt":"Write a short poem about artificial intelligence","stream":false}')
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l)
    
    if echo "$response" | jq '.response' > /dev/null 2>&1; then
        response_text=$(echo "$response" | jq -r '.response')
        word_count=$(echo "$response_text" | wc -w)
        words_per_second=$(echo "scale=2; $word_count / $duration" | bc -l)
        
        log_info "Benchmark Results:"
        echo "• Duration: ${duration}s"
        echo "• Words generated: $word_count"
        echo "• Speed: ${words_per_second} words/second"
        echo "• Response preview: $(echo "$response_text" | head -c 100)..."
    else
        log_error "Benchmark failed. Response: $response"
    fi
}

fix_common_issues() {
    echo "=== Common Issue Fixes ==="
    
    echo "1. Fix Ollama permission issues"
    sudo chown -R $USER:$USER ~/.ollama
    
    echo "2. Restart Ollama service"
    sudo systemctl restart ollama 2>/dev/null || {
        pkill -f "ollama serve"
        sleep 2
        nohup ollama serve > ~/ollama.log 2>&1 &
    }
    
    echo "3. Fix Docker permissions"
    sudo usermod -aG docker $USER
    
    echo "4. Clear Ollama cache if corrupted"
    read -p "Clear Ollama model cache? This will require re-downloading models (y/n): " clear_cache
    if [[ "$clear_cache" == "y" ]]; then
        ollama rm --all 2>/dev/null || true
        rm -rf ~/.ollama/models/* 2>/dev/null || true
        log_info "Cache cleared. You'll need to re-download models."
    fi
    
    echo "5. Reset proxy script"
    if [ -f ~/ollama-proxy.py ]; then
        pkill -f ollama-proxy.py
        sleep 2
        source ~/.ollama_config 2>/dev/null || true
        OLLAMA_PORT=${OLLAMA_PORT:-11435}
        MODEL_NAME=${MODEL_NAME:-"llama3.2:1b"}
        nohup python3 ~/ollama-proxy.py $OLLAMA_PORT $MODEL_NAME > ~/ollama-proxy.log 2>&1 &
        log_info "Proxy script restarted"
    fi
}

show_detailed_status() {
    echo "=== Detailed System Status ==="
    
    echo "--- Process Status ---"
    ps aux | grep -E "(ollama|docker|kuzco)" | grep -v grep
    
    echo "--- Port Status ---"
    ss -tuln | grep -E ":11434|:11435|:8080|:80"
    
    echo "--- Recent Logs ---"
    echo "Ollama Service Log (last 5 lines):"
    tail -5 ~/ollama.log 2>/dev/null || echo "No ollama.log found"
    
    echo "Ollama Proxy Log (last 5 lines):"
    tail -5 ~/ollama-proxy.log 2>/dev/null || echo "No ollama-proxy.log found"
    
    echo "--- Ollama Models ---"
    if command -v ollama &> /dev/null; then
        ollama list
    else
        echo "Ollama command not available"
    fi
    
    echo "--- Docker Containers ---"
    if [ -d ~/kuzco-installer-docker/kuzco-main ]; then
        cd ~/kuzco-installer-docker/kuzco-main
        docker-compose ps
    fi
}

interactive_menu() {
    while true; do
        echo ""
        echo "=============================================="
        echo "         Ollama + Kuzco Troubleshooter"
        echo "=============================================="
        echo "1. Quick Status Check"
        echo "2. Full System Diagnosis"
        echo "3. Test Connectivity"
        echo "4. Performance Benchmark"
        echo "5. Fix Common Issues"
        echo "6. System Optimization"
        echo "7. Clean Logs"
        echo "8. Detailed Status"
        echo "9. Restart All Services"
        echo "0. Exit"
        echo ""
        read -p "Choose option (0-9): " choice
        
        case $choice in
            1)
                check_services
                ;;
            2)
                check_system_resources
                check_services
                test_ollama_connectivity
                ;;
            3)
                test_ollama_connectivity
                ;;
            4)
                benchmark_model
                ;;
            5)
                fix_common_issues
                ;;
            6)
                optimize_system
                ;;
            7)
                clean_logs
                ;;
            8)
                show_detailed_status
                ;;
            9)
                echo "Restarting all services..."
                ~/ollama-manager.sh restart
                if [ -d ~/kuzco-installer-docker/kuzco-main ]; then
                    cd ~/kuzco-installer-docker/kuzco-main
                    docker-compose restart
                fi
                log_info "All services restarted"
                ;;
            0)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid option. Please try again."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Main execution
if [ "$1" = "--auto" ]; then
    # Auto mode - run all checks
    check_system_resources
    check_services
    test_ollama_connectivity
    echo "Auto diagnosis complete. Run without --auto for interactive mode."
else
    # Interactive mode
    interactive_menu
fi
