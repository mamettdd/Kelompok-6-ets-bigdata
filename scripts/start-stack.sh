#!/usr/bin/env bash
# start-stack.sh — Nyalakan semua infrastruktur (Hadoop + Kafka).

set -euo pipefail

GREEN='\033[0;32m'
NC='\033[0m'
log() { echo -e "${GREEN}[INFO]${NC} $*"; }

# Pindah ke root repo (folder di atas scripts/)
cd "$(dirname "$0")/.."

log "Start Hadoop stack..."
docker compose -f docker-compose-hadoop.yml up -d

log "Start Kafka stack..."
docker compose -f docker-compose-kafka.yml up -d

log "Status container:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

log ""
log "Tunggu container siap (~30 detik), lalu jalankan:"
log "  bash scripts/init-infra.sh"
