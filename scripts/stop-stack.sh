#!/usr/bin/env bash
# stop-stack.sh — Matikan semua infrastruktur.
# Tambah --volumes untuk hapus juga data HDFS.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

cd "$(dirname "$0")/.."

EXTRA=""
if [[ "${1:-}" == "--volumes" ]]; then
  warn "Mode --volumes: data HDFS juga akan dihapus!"
  EXTRA="--volumes"
fi

log "Stop Kafka stack..."
docker compose -f docker-compose-kafka.yml down $EXTRA

log "Stop Hadoop stack..."
docker compose -f docker-compose-hadoop.yml down $EXTRA

log "Selesai."
