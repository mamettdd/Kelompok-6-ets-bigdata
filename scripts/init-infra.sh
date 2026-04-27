#!/usr/bin/env bash
# init-infra.sh — Inisialisasi infrastruktur Kafka topics dan HDFS folders.
# Jalankan SETELAH semua container Docker (Kafka + Hadoop) running.

set -euo pipefail

# Warna untuk output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERR ]${NC} $*"; }

KAFKA_CONTAINER="kafka-broker"
NAMENODE_CONTAINER="namenode"
TOPICS=("airquality-api" "airquality-rss")
HDFS_DIRS=(
  "/data/airquality/api"
  "/data/airquality/rss"
  "/data/airquality/hasil"
)

# Cek container running
check_container() {
  local name="$1"
  if ! docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
    err "Container '${name}' tidak running. Jalankan dulu docker compose up -d"
    exit 1
  fi
}

log "Cek container Kafka & Hadoop running..."
check_container "${KAFKA_CONTAINER}"
check_container "${NAMENODE_CONTAINER}"

log "Tunggu Kafka siap (max 60 detik)..."
for i in {1..30}; do
  if docker exec "${KAFKA_CONTAINER}" kafka-topics.sh \
       --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
    log "Kafka siap."
    break
  fi
  if [[ $i -eq 30 ]]; then
    err "Kafka tidak siap dalam 60 detik."
    exit 1
  fi
  sleep 2
done

# Buat 2 topic
for topic in "${TOPICS[@]}"; do
  if docker exec "${KAFKA_CONTAINER}" kafka-topics.sh \
       --bootstrap-server localhost:9092 --list 2>/dev/null | grep -q "^${topic}$"; then
    warn "Topic '${topic}' sudah ada — skip."
  else
    log "Membuat topic '${topic}'..."
    docker exec "${KAFKA_CONTAINER}" kafka-topics.sh \
      --bootstrap-server localhost:9092 \
      --create \
      --topic "${topic}" \
      --partitions 1 \
      --replication-factor 1
  fi
done

log "Daftar topic Kafka:"
docker exec "${KAFKA_CONTAINER}" kafka-topics.sh \
  --bootstrap-server localhost:9092 --list

log "Tunggu HDFS siap (max 60 detik)..."
for i in {1..30}; do
  if docker exec "${NAMENODE_CONTAINER}" hdfs dfsadmin -report >/dev/null 2>&1; then
    log "HDFS siap."
    break
  fi
  if [[ $i -eq 30 ]]; then
    err "HDFS tidak siap dalam 60 detik."
    exit 1
  fi
  sleep 2
done

# Buat folder HDFS
for dir in "${HDFS_DIRS[@]}"; do
  if docker exec "${NAMENODE_CONTAINER}" hdfs dfs -test -d "${dir}" 2>/dev/null; then
    warn "Folder HDFS '${dir}' sudah ada — skip."
  else
    log "Membuat folder HDFS '${dir}'..."
    docker exec "${NAMENODE_CONTAINER}" hdfs dfs -mkdir -p "${dir}"
  fi
done

log "Struktur HDFS /data/airquality/:"
docker exec "${NAMENODE_CONTAINER}" hdfs dfs -ls -R /data/airquality

log ""
log "=========================================="
log " Infrastruktur siap!"
log "=========================================="
log "  Kafka topics : ${TOPICS[*]}"
log "  HDFS folders : ${HDFS_DIRS[*]}"
log "  Web UI HDFS  : http://localhost:9870"
log "  Web UI YARN  : http://localhost:8088"
log "=========================================="
