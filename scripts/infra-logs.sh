#!/usr/bin/env bash
# infra-logs.sh — Live log lengkap infrastruktur AirQuality Alert.
#
# Pakai:
#   bash scripts/infra-logs.sh              # live, jalan terus sampai Ctrl+C
#   bash scripts/infra-logs.sh --lines 300  # live dengan backlog awal 300 baris
#   bash scripts/infra-logs.sh --snapshot   # laporan sekali jalan, tidak follow
#   bash scripts/infra-logs.sh --save       # live + simpan output ke file
#
# Cakupan:
#   - proses Python lokal: producer API, producer RSS, consumer, dashboard
#   - Docker container: Kafka, Zookeeper, Hadoop NameNode/DataNode/RM/NM
#   - Kafka: daftar topic, detail topic, consumer group
#   - HDFS: folder proyek, file terbaru, kapasitas, DataNode
#   - RSS: feed, keyword, log producer RSS
#   - dashboard: port/socket dan HTTP endpoint

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

LINES=160
SAVE=0
MODE="follow"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lines)
      LINES="${2:-160}"
      shift 2
      ;;
    --save)
      SAVE=1
      shift
      ;;
    --snapshot|--once)
      MODE="snapshot"
      shift
      ;;
    --follow|--live)
      MODE="follow"
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

KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-localhost:9092}"
KAFKA_TOPIC_API="${KAFKA_TOPIC_API:-airquality-api}"
KAFKA_TOPIC_RSS="${KAFKA_TOPIC_RSS:-airquality-rss}"
CONSUMER_GROUP_API="${CONSUMER_GROUP_API:-airquality-consumer-api}"
CONSUMER_GROUP_RSS="${CONSUMER_GROUP_RSS:-airquality-consumer-rss}"
HDFS_BASE_DIR="${HDFS_BASE_DIR:-/data/airquality}"
HDFS_NAMENODE_CONTAINER="${HDFS_NAMENODE_CONTAINER:-namenode}"
PORT="${PORT:-5000}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

section() {
  echo
  echo -e "${BLUE}${BOLD}============================================================${NC}"
  echo -e "${BLUE}${BOLD}$*${NC}"
  echo -e "${BLUE}${BOLD}============================================================${NC}"
}

ok() { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
info() { echo -e "${BOLD}[INFO]${NC} $*"; }

have() {
  command -v "$1" >/dev/null 2>&1
}

run_or_warn() {
  local label="$1"
  shift
  echo
  echo -e "${BOLD}>>> ${label}${NC}"
  "$@" 2>&1 || warn "Command gagal: $*"
}

tail_file() {
  local file="$1"
  local label="$2"
  echo
  echo -e "${BOLD}>>> ${label}: ${file}${NC}"
  if [[ -f "$file" ]]; then
    tail -n "$LINES" "$file"
  else
    warn "File log belum ada: $file"
  fi
}

follow_file() {
  local file="$1"
  local label="$2"
  echo -e "${BOLD}>>> LIVE ${label}: ${file}${NC}"
  tail -n "$LINES" -F "$file" 2>/dev/null | sed -u "s/^/[${label}] /" &
}

follow_docker() {
  local svc="$1"
  if have docker && docker ps --format '{{.Names}}' | grep -q "^${svc}$"; then
    echo -e "${BOLD}>>> LIVE docker logs: ${svc}${NC}"
    docker logs --tail "$LINES" -f "$svc" 2>&1 | sed -u "s/^/[docker:${svc}] /" &
  else
    warn "Container ${svc} tidak running, live docker logs dilewati."
  fi
}

status_loop() {
  while true; do
    section "LIVE STATUS $(date -Is)"
    check_tcp localhost 9092 "Kafka broker"
    check_tcp localhost 9000 "HDFS NameNode RPC"
    check_tcp localhost 9870 "HDFS NameNode Web UI"
    check_tcp localhost "$PORT" "Dashboard Flask"

    if have docker; then
      docker ps --format "[docker] {{.Names}} | {{.Status}}" 2>/dev/null || true
    fi

    if have docker && docker ps --format '{{.Names}}' | grep -q "^${HDFS_NAMENODE_CONTAINER}$"; then
      docker exec "$HDFS_NAMENODE_CONTAINER" hdfs dfs -ls "$HDFS_BASE_DIR" 2>/dev/null \
        | sed -u 's/^/[hdfs] /' || true
    fi

    if have curl; then
      local code
      code="$(curl -sS -o /dev/null -w "%{http_code}" "http://localhost:${PORT}/api/status" 2>/dev/null || true)"
      echo "[dashboard] /api/status HTTP ${code:-gagal}"
    fi

    sleep 15
  done
}

check_tcp() {
  local host="$1"
  local port="$2"
  local label="$3"
  if (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
    ok "${label} reachable di ${host}:${port}"
  else
    fail "${label} tidak reachable di ${host}:${port}"
  fi
}

http_check() {
  local url="$1"
  local label="$2"
  if have curl; then
    local code
    code="$(curl -sS -o /tmp/airquality-http-check.out -w "%{http_code}" "$url" 2>/dev/null || true)"
    if [[ "$code" =~ ^2|3 ]]; then
      ok "${label} HTTP ${code}: ${url}"
      sed -n '1,8p' /tmp/airquality-http-check.out
    else
      fail "${label} HTTP ${code:-gagal}: ${url}"
    fi
  else
    warn "curl tidak tersedia, skip HTTP check: $url"
  fi
}

main_report() {
  section "Ringkasan Workspace"
  info "Root: $ROOT"
  info "Waktu: $(date -Is)"
  info "Jumlah baris log per file/service: $LINES"
  info "Kafka bootstrap: $KAFKA_BOOTSTRAP"
  info "Kafka topics: $KAFKA_TOPIC_API, $KAFKA_TOPIC_RSS"
  info "HDFS base dir: $HDFS_BASE_DIR"
  info "Dashboard port: $PORT"
  info "Catatan: script ini tidak menampilkan token atau rahasia dari .env."

  section "Socket dan Port dari Host"
  check_tcp localhost 9092 "Kafka broker"
  check_tcp localhost 9000 "HDFS NameNode RPC"
  check_tcp localhost 9870 "HDFS NameNode Web UI"
  check_tcp localhost 8088 "YARN ResourceManager Web UI"
  check_tcp localhost "$PORT" "Dashboard Flask"

  if have ss; then
    run_or_warn "Socket listening terkait port proyek" ss -ltnp
  else
    warn "Command ss tidak tersedia."
  fi

  section "HTTP Dashboard dan WebHDFS"
  http_check "http://localhost:${PORT}/" "Dashboard halaman utama"
  http_check "http://localhost:${PORT}/api/status" "Dashboard status API"
  http_check "http://localhost:9870/webhdfs/v1${HDFS_BASE_DIR}?op=LISTSTATUS" "WebHDFS list ${HDFS_BASE_DIR}"

  section "Proses Python Lokal"
  run_or_warn "Producer API process" pgrep -af "kafka/producer_api.py"
  run_or_warn "Producer RSS process" pgrep -af "kafka/producer_rss.py"
  run_or_warn "Consumer HDFS process" pgrep -af "kafka/consumer_to_hdfs.py"
  run_or_warn "Dashboard Flask process" pgrep -af "dashboard/app.py|flask"

  section "Docker Container"
  if have docker; then
    run_or_warn "docker ps" docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  else
    fail "Docker tidak tersedia di PATH."
  fi

  section "Kafka Status"
  if have docker && docker ps --format '{{.Names}}' | grep -q '^kafka-broker$'; then
    run_or_warn "Kafka topic list" docker exec kafka-broker kafka-topics.sh --bootstrap-server localhost:9092 --list
    run_or_warn "Kafka topic describe: ${KAFKA_TOPIC_API}" docker exec kafka-broker kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic "$KAFKA_TOPIC_API"
    run_or_warn "Kafka topic describe: ${KAFKA_TOPIC_RSS}" docker exec kafka-broker kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic "$KAFKA_TOPIC_RSS"
    run_or_warn "Kafka consumer group API" docker exec kafka-broker kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group "$CONSUMER_GROUP_API"
    run_or_warn "Kafka consumer group RSS" docker exec kafka-broker kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group "$CONSUMER_GROUP_RSS"
  else
    warn "Container kafka-broker belum running."
  fi

  section "HDFS dan Hadoop Status"
  if have docker && docker ps --format '{{.Names}}' | grep -q "^${HDFS_NAMENODE_CONTAINER}$"; then
    run_or_warn "HDFS dfsadmin report ringkas" docker exec "$HDFS_NAMENODE_CONTAINER" hdfs dfsadmin -report
    run_or_warn "HDFS ls base dir" docker exec "$HDFS_NAMENODE_CONTAINER" hdfs dfs -ls -R "$HDFS_BASE_DIR"
    run_or_warn "HDFS du base dir" docker exec "$HDFS_NAMENODE_CONTAINER" hdfs dfs -du -h "$HDFS_BASE_DIR"
  else
    warn "Container ${HDFS_NAMENODE_CONTAINER} belum running."
  fi

  section "RSS Konfigurasi dan Relevansi"
  info "RSS_FEEDS: ${RSS_FEEDS:-default producer_rss.py}"
  info "RSS_KEYWORDS: ${RSS_KEYWORDS:-default producer_rss.py}"
  info "RSS_FALLBACK_TOPN: ${RSS_FALLBACK_TOPN:-0}"
  info "RSS_SEEN_IDS_FILE: ${RSS_SEEN_IDS_FILE:-kafka/seen_ids.json}"
  if [[ -f "${RSS_SEEN_IDS_FILE:-kafka/seen_ids.json}" ]]; then
    run_or_warn "Ukuran seen_ids RSS" wc -c "${RSS_SEEN_IDS_FILE:-kafka/seen_ids.json}"
  fi

  section "Log Pipeline Lokal"
  tail_file "logs/producer_api.log" "Producer API log"
  tail_file "logs/producer_rss.log" "Producer RSS log"
  tail_file "logs/consumer.log" "Consumer HDFS log"
  tail_file "logs/dashboard.log" "Dashboard log jika ada"

  section "Log Docker Kafka dan Hadoop"
  if have docker; then
    for svc in zookeeper kafka-broker namenode datanode1 datanode2 datanode3 resourcemanager nodemanager; do
      if docker ps --format '{{.Names}}' | grep -q "^${svc}$"; then
        echo
        echo -e "${BOLD}>>> docker logs ${svc} --tail ${LINES}${NC}"
        docker logs --tail "$LINES" "$svc" 2>&1 || warn "Gagal membaca docker logs ${svc}"
      else
        warn "Container ${svc} tidak running, skip docker logs."
      fi
    done
  fi

  section "Ringkasan Selesai"
  ok "Laporan selesai. Untuk simpan ke file: bash scripts/infra-logs.sh --save"
}

live_report() {
  mkdir -p logs
  section "LIVE LOG MODE"
  info "Mode ini jalan terus sampai dihentikan dengan Ctrl+C."
  info "Backlog awal per stream: ${LINES} baris."
  info "Gunakan --snapshot kalau hanya ingin laporan singkat sekali jalan."
  info "Catatan: token/rahasia .env tidak dicetak."

  section "Live Log Pipeline Lokal"
  follow_file "logs/producer_api.log" "producer_api"
  follow_file "logs/producer_rss.log" "producer_rss"
  follow_file "logs/consumer.log" "consumer_hdfs"
  follow_file "logs/dashboard.log" "dashboard"

  section "Live Docker Logs"
  for svc in zookeeper kafka-broker namenode datanode1 datanode2 datanode3 resourcemanager nodemanager; do
    follow_docker "$svc"
  done

  status_loop &

  trap 'echo; warn "Menghentikan live log..."; jobs -p | xargs -r kill 2>/dev/null; exit 0' INT TERM
  wait
}

if [[ "$SAVE" -eq 1 ]]; then
  mkdir -p logs
  OUT="logs/infra-live-log-$(date +%Y%m%d-%H%M%S).log"
  if [[ "$MODE" == "snapshot" ]]; then
    main_report | tee "$OUT"
  else
    live_report | tee "$OUT"
  fi
  echo
  ok "Output tersimpan di $OUT"
else
  if [[ "$MODE" == "snapshot" ]]; then
    main_report
  else
    live_report
  fi
fi
