# Panduan Instalasi Kuzco + Ollama (Pengganti ViKey)

## 🎯 Overview

Script ini mengganti **ViKey Inference** dengan **Ollama** sebagai backend AI inference untuk Kuzco Node. Ollama berjalan secara lokal tanpa memerlukan API key berbayar dan mendukung berbagai model open-source.

## 📋 Persyaratan Sistem

### Minimum Requirements
- **OS**: Ubuntu 20.04/22.04 atau Debian
- **RAM**: 4GB (minimum 2GB untuk model kecil)
- **Storage**: 10GB free space (lebih banyak untuk model besar)
- **CPU**: 2+ cores
- **Network**: Stable internet connection

### Recommended Requirements
- **RAM**: 8GB+ 
- **Storage**: 20GB+ free space
- **CPU**: 4+ cores
- **GPU**: Optional (NVIDIA dengan CUDA untuk performa lebih baik)

## 🚀 Instalasi Cepat

### 1. Download dan Jalankan Script

```bash
# Download script utama
curl -L https://raw.githubusercontent.com/blackcatdeath-dev/Kuzco/refs/heads/main/kuzco-ollama.sh -o kuzco-ollama.sh

# Berikan permission execute
chmod +x kuzco-ollama.sh

# Jalankan instalasi
./kuzco-ollama.sh
```

### 2. Ikuti Proses Instalasi

Script akan menanyakan:

1. **Model Selection**: Pilih model AI yang sesuai dengan RAM Anda
   - `llama3.2:1b` - Ringan (~1GB RAM)
   - `llama3.2:3b` - Seimbang (~2GB RAM) 
   - `llama3.1:8b` - Kualitas tinggi (~4.7GB RAM)

2. **Port Configuration**: Script otomatis mencari port yang tersedia

3. **Kuzco Credentials**: 
   - Worker ID dari dashboard Kuzco
   - Worker Code dari dashboard Kuzco

## 🛠 Model yang Tersedia

| Model | Size | RAM Required | Performance | Use Case |
|-------|------|--------------|-------------|----------|
| llama3.2:1b | ~1GB | 2GB | Basic | Low-end VPS |
| llama3.2:3b | ~2GB | 4GB | Good | Balanced |
| llama3.1:8b | ~4.7GB | 8GB | Excellent | High-end VPS |
| qwen2.5:7b | ~4.4GB | 8GB | Excellent | Alternative choice |
| mistral:7b | ~4.1GB | 8GB | Excellent | Popular model |

## 📊 Management Commands

### Ollama Manager Script

```bash
# Cek status semua service
~/ollama-manager.sh status

# Start semua service
~/ollama-manager.sh start

# Stop semua service  
~/ollama-manager.sh stop

# Restart semua service
~/ollama-manager.sh restart

# Lihat logs
~/ollama-manager.sh logs

# Test API connectivity
~/ollama-manager.sh test

# Lihat model yang terinstall
~/ollama-manager.sh models

# Download model baru
~/ollama-manager.sh pull llama3.2:3b

# Cek port yang digunakan
~/ollama-manager.sh ports
```

### Troubleshooting Script

```bash
# Download troubleshooting script
curl -L https://raw.githubusercontent.com/blackcatdeath-dev/Kuzco/refs/heads/main/troubleshoot.sh -o troubleshoot.sh
chmod +x troubleshoot.sh

# Jalankan diagnosis otomatis
./troubleshoot.sh --auto

# Mode interaktif
./troubleshoot.sh
```

## 🔧 Konfigurasi Manual

### Mengganti Model

```bash
# Stop services
~/ollama-manager.sh stop

# Download model baru
ollama pull llama3.1:8b

# Update konfigurasi
echo "MODEL_NAME=llama3.1:8b" > ~/.ollama_config

# Start services
~/ollama-manager.sh start
```

### Mengubah Port

```bash
# Edit konfigurasi
nano ~/.ollama_config

# Ubah OLLAMA_PORT=12345
# Simpan dan restart
~/ollama-manager.sh restart
```

## 📋 Monitoring & Logs

### Cek Status Kuzco Worker

```bash
cd ~/kuzco-installer-docker/kuzco-main
docker-compose logs -f --tail 100
```

### Monitor Resource Usage

```bash
# Memory usage
free -h

# CPU usage
htop

# Disk usage
df -h

# Ollama process
ps aux | grep ollama
```

### Log Files

- **Ollama Server**: `~/ollama.log`
- **Ollama Proxy**: `~/ollama-proxy.log`
- **Kuzco Worker**: Docker logs via docker-compose

## ⚠️ Troubleshooting Common Issues

### 1. Ollama Not Starting

```bash
# Check service
sudo systemctl status ollama

# Manual start
sudo systemctl start ollama

# Or run manually
nohup ollama serve > ~/ollama.log 2>&1 &
```

### 2. Port Already in Use

```bash
# Find process using port
sudo lsof -i :11435

# Kill process
sudo kill -9 <PID>

# Or use different port
~/ollama-manager.sh ports
```

### 3. Model Download Failed

```bash
# Check internet connection
ping google.com

# Manual download
ollama pull llama3.2:1b

# Check disk space
df -h
```

### 4. High Memory Usage

```bash
# Switch to smaller model
ollama pull llama3.2:1b
echo "MODEL_NAME=llama3.2:1b" > ~/.ollama_config
~/ollama-manager.sh restart
```

### 5. Kuzco Worker Not Connecting

```bash
# Check proxy status
curl http://localhost:11435/health

# Restart all services
~/ollama-manager.sh restart
cd ~/kuzco-installer-docker/kuzco-main
docker-compose restart
```

## 🔄 Update & Maintenance

### Update Ollama

```bash
# Update Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Restart services
~/ollama-manager.sh restart
```

### Update Models

```bash
# List current models
ollama list

# Update model
ollama pull llama3.2:3b

# Remove old model
ollama rm old-model:tag
```

### Cleanup

```bash
# Clean logs
./troubleshoot.sh
# Choose option 7 (Clean Logs)

# Clean Docker
docker system prune -f

# Clean Ollama cache
ollama rm --all
```

## 📈 Performance Optimization

### For Low-End VPS (2GB RAM)

```bash
# Use smallest model
ollama pull llama3.2:1b

# Enable swap
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### For High-End VPS (8GB+ RAM)

```bash
# Use larger model
ollama pull llama3.1:8b

# Optimize for performance
echo 'OLLAMA_NUM_PARALLEL=4' >> ~/.ollama_config
echo 'OLLAMA_MAX_LOADED_MODELS=2' >> ~/.ollama_config
```

## 💡 Tips & Best Practices

1. **Model Selection**: Mulai dengan model kecil, upgrade jika perlu
2. **Monitoring**: Cek status secara berkala dengan `~/ollama-manager.sh status`
3. **Backup**: Simpan konfigurasi penting (`~/.ollama_config`)
4. **Updates**: Update Ollama dan model secara berkala
5. **Resource**: Monitor penggunaan RAM dan disk space

## 🆚 Perbandingan dengan ViKey

| Aspect | ViKey | Ollama |
|--------|-------|--------|
| Cost | Pay per request | Free |
| Setup | Simple API key | Local installation |
| Performance | Cloud-based | Local hardware dependent |
| Privacy | Data sent to cloud | Fully local |
| Availability | Depends on service | Always available offline |
| Models | Limited selection | Many open models |

## 🔗 Links & Resources

- [Ollama Official Site](https://ollama.ai/)
- [Kuzco Dashboard](https://inference.supply)
- [Docker Documentation](https://docs.docker.com/)
- [Ubuntu Server Guide](https://ubuntu.com/server/docs)

## 📞 Support & Community

Jika mengalami masalah:

1. Jalankan troubleshooting script: `./troubleshoot.sh`
2. Cek logs: `~/ollama-manager.sh logs`
3. Join komunitas Kuzco di Discord/Telegram
4. Buka issue di GitHub repository

---

**Disclaimer**: Script ini disediakan "as-is". Selalu backup data penting sebelum menjalankan script instalasi pada sistem produksi.
