#!/usr/bin/env bash
# install-docker-wsl.sh — Install Docker Engine native di WSL2 (Ubuntu/Debian).
#
# Pakai: bash scripts/install-docker-wsl.sh
# Setelah selesai: logout & login ulang ke WSL agar grup 'docker' aktif.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERR ]${NC} $*"; }

# Cek WSL
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  warn "Sistem ini tampak BUKAN WSL — tetap dilanjutkan."
fi

# Cek Ubuntu/Debian
if ! command -v apt >/dev/null 2>&1; then
  err "Script ini hanya support distro berbasis apt (Ubuntu/Debian)."
  exit 1
fi

if command -v docker >/dev/null 2>&1; then
  warn "Docker sudah terinstall: $(docker --version)"
  read -p "Lanjutkan reinstall? (y/N) " ans
  [[ "${ans:-N}" =~ ^[Yy]$ ]] || exit 0
fi

log "Step 1/7 — Update apt..."
sudo apt update

log "Step 2/7 — Install prasyarat..."
sudo apt install -y ca-certificates curl gnupg lsb-release

log "Step 3/7 — Tambah GPG key Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
if [[ -f /etc/apt/keyrings/docker.gpg ]]; then
  warn "GPG key Docker sudah ada — overwrite."
  sudo rm -f /etc/apt/keyrings/docker.gpg
fi
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

log "Step 4/7 — Tambah repo Docker..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

log "Step 5/7 — Install Docker Engine + Compose plugin..."
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "Step 6/7 — Tambahkan user '$USER' ke grup docker..."
sudo usermod -aG docker "$USER"

log "Step 7/7 — Start Docker daemon..."
sudo service docker start || warn "Gagal start (mungkin sudah running)"

# Test
sleep 2
if sudo docker run --rm hello-world >/dev/null 2>&1; then
  log "Docker berfungsi normal!"
else
  warn "Test docker run gagal — coba manual: sudo docker run hello-world"
fi

log ""
log "=========================================="
log " Docker berhasil terinstall!"
log "=========================================="
log " Versi : $(docker --version 2>/dev/null || sudo docker --version)"
log " Compose: $(docker compose version 2>/dev/null || sudo docker compose version)"
log "=========================================="
log ""
warn "WAJIB: Logout & login ulang ke WSL agar grup 'docker' aktif"
warn "       (atau jalankan: newgrp docker)"
warn ""
warn "Setiap restart WSL, jalankan: sudo service docker start"
warn ""
log "Setelah login ulang, lanjut:"
log "  bash scripts/start-stack.sh"
log "  bash scripts/init-infra.sh"
