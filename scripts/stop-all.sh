#!/usr/bin/env bash
# stop-all.sh — Stop total AirQuality Alert.
#
# Pakai:
#   bash scripts/stop-all.sh
#   bash scripts/stop-all.sh --volumes     # ikut hapus volume Docker/HDFS lokal
#   bash scripts/stop-all.sh --force       # SIGKILL jika proses bandel
#
# Script ini membatasi kill ke proses/port proyek:
#   - producer_api.py, producer_rss.py, consumer_to_hdfs.py
#   - dashboard/app.py, flask yang berjalan dari folder proyek
#   - proses live log scripts/infra-logs.sh
#   - port default proyek: Kafka 9092, HDFS 9000/9870, YARN 8088, dashboard PORT
#   - docker compose Kafka + Hadoop dan container bernama service proyek

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WITH_VOLUMES=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --volumes)
      WITH_VOLUMES=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      sed -n '1,18p' "$0"
      exit 0
      ;;
    *)
      echo "[WARN] Argumen tidak dikenal: $1"
      shift
      ;;
  esac
done

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a; source .env; set +a
fi

PORT="${PORT:-5000}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }

kill_pattern() {
  local pattern="$1"
  local label="$2"
  local pids
  pids="$(pgrep -f "$pattern" || true)"
  if [[ -z "$pids" ]]; then
    info "${label}: tidak ada proses."
    return
  fi

  info "Stop ${label} PID: ${pids//$'\n'/ }"
  pkill -TERM -f "$pattern" || true
  sleep 1

  local remain
  remain="$(pgrep -f "$pattern" || true)"
  if [[ -n "$remain" && "$FORCE" -eq 1 ]]; then
    warn "${label}: masih jalan, kirim SIGKILL PID: ${remain//$'\n'/ }"
    pkill -KILL -f "$pattern" || true
  elif [[ -n "$remain" ]]; then
    warn "${label}: masih jalan. Jalankan dengan --force jika ingin SIGKILL."
  fi
}

kill_port() {
  local port="$1"
  local label="$2"
  local pids=""

  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  elif command -v fuser >/dev/null 2>&1; then
    pids="$(fuser "$port"/tcp 2>/dev/null || true)"
  fi

  if [[ -z "$pids" ]]; then
    info "Port ${port} (${label}): tidak ada listener lokal yang perlu dimatikan."
    return
  fi

  warn "Stop listener port ${port} (${label}) PID: ${pids//$'\n'/ }"
  kill -TERM $pids 2>/dev/null || true
  sleep 1

  if [[ "$FORCE" -eq 1 ]]; then
    kill -KILL $pids 2>/dev/null || true
  fi
}

compose_down() {
  local file="$1"
  local label="$2"
  local extra=()
  if [[ "$WITH_VOLUMES" -eq 1 ]]; then
    extra+=(--volumes)
  fi

  if [[ -f "$file" ]]; then
    info "Docker compose down: ${label}"
    docker compose -f "$file" down "${extra[@]}" || warn "Gagal docker compose down ${file}"
  else
    warn "File compose tidak ada: ${file}"
  fi
}

stop_named_container() {
  local name="$1"
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
    info "Stop/remove container ${name}"
    docker stop "$name" >/dev/null 2>&1 || true
    docker rm "$name" >/dev/null 2>&1 || true
  fi
}

echo "=========================================="
info "STOP TOTAL AirQuality Alert"
info "Root: $ROOT"
if [[ "$WITH_VOLUMES" -eq 1 ]]; then
  warn "--volumes aktif: volume Docker/HDFS lokal ikut dihapus."
fi
echo "=========================================="

info "1) Stop proses Python proyek"
kill_pattern "kafka/producer_api.py" "Producer API"
kill_pattern "kafka/producer_rss.py" "Producer RSS"
kill_pattern "kafka/consumer_to_hdfs.py" "Consumer HDFS"
kill_pattern "dashboard/app.py" "Dashboard Flask"
kill_pattern "scripts/infra-logs.sh" "Live infra logs"

info "2) Stop listener port proyek"
kill_port "$PORT" "Dashboard Flask"
kill_port 9092 "Kafka broker host listener"
kill_port 9000 "HDFS NameNode RPC"
kill_port 9870 "HDFS NameNode Web UI"
kill_port 8088 "YARN ResourceManager"

info "3) Docker compose down"
if command -v docker >/dev/null 2>&1; then
  compose_down "docker-compose-kafka.yml" "Kafka"
  compose_down "docker-compose-hadoop.yml" "Hadoop"

  info "4) Stop container service proyek yang tersisa"
  for c in zookeeper kafka-broker namenode datanode1 datanode2 datanode3 resourcemanager nodemanager; do
    stop_named_container "$c"
  done
else
  warn "Docker tidak tersedia di PATH, skip Docker cleanup."
fi

echo "=========================================="
info "Verifikasi sisa proses"
pgrep -af "kafka/producer_api.py|kafka/producer_rss.py|kafka/consumer_to_hdfs.py|dashboard/app.py|scripts/infra-logs.sh" || true
if command -v docker >/dev/null 2>&1; then
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || true
fi
echo "=========================================="
info "Stop-all selesai."
