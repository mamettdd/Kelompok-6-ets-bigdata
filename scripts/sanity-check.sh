#!/usr/bin/env bash
# sanity-check.sh — Verifikasi end-to-end Kafka & HDFS sebelum lanjut Fase 2.
#
# Tes:
#   1. 8 container: 3 DataNode HDFS + NameNode/RM/NM + Kafka + Zookeeper
#   2. HDFS: dfs.replication = 2 (dari hadoop.env)
#   3. HDFS: 3 live DataNode terdaftar di NameNode
#   4. Kafka: produce-consume 1 pesan
#   5. HDFS: put file + fsck cek min replication
#   6. WebHDFS + port 9092
#
# Pakai: bash scripts/sanity-check.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[ OK ]${NC} $*"; }
test_log() { echo -e "${BLUE}[TEST]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[FAIL]${NC} $*"; }

PASS=0
FAIL=0
mark_pass() { ((PASS++)) || true; }
mark_fail() { ((FAIL++)) || true; }

# ============================================================
# Tes 1 — Semua container running
# ============================================================
test_log "Tes 1: Cek 8 container (6 Hadoop: 1 NN + 3 DN + RM + NM; 2 Kafka stack)..."

EXPECTED_CONTAINERS=(
  namenode
  datanode1
  datanode2
  datanode3
  resourcemanager
  nodemanager
  kafka-broker
  zookeeper
)
MISSING=()

for c in "${EXPECTED_CONTAINERS[@]}"; do
  if docker ps --format '{{.Names}}' | grep -q "^${c}$"; then
    log "Container '${c}' running"
  else
    err "Container '${c}' TIDAK running"
    MISSING+=("$c")
  fi
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
  mark_pass
else
  mark_fail
  err "Container hilang: ${MISSING[*]}"
  err "Jalankan: bash scripts/start-stack.sh"
  err "Jika barusan upgrade dari 1 DataNode, restart stack + init:"
  err "  bash scripts/stop-stack.sh --volumes   # hati-hati: hapus data HDFS lokal"
  err "  bash scripts/start-stack.sh && bash scripts/init-infra.sh"
  exit 1
fi

echo ""

# ============================================================
# Tes 1b — dfs.replication = 2
# ============================================================
test_log "Tes 1b: Cek HDFS default replication = 2 (hadoop.env)..."

REP_CONF=$(docker exec namenode hdfs getconf -confKey dfs.replication 2>/dev/null | tr -d '\r' || true)
if [[ "${REP_CONF}" == "2" ]]; then
  log "dfs.replication = 2 (sesuai soal: replikasi 2)"
  mark_pass
else
  err "dfs.replication = '${REP_CONF:-kosong}' (diharapkan 2)"
  mark_fail
fi

echo ""

# ============================================================
# Tes 1c — 3 live DataNode
# ============================================================
test_log "Tes 1c: Cek 3 live DataNode terdaftar..."

# Contoh output: "Live datanodes (3):"
LIVE_LINE=$(docker exec namenode hdfs dfsadmin -report 2>/dev/null | grep -E "Live datanodes \([0-9]+\):" || true)
if echo "${LIVE_LINE}" | grep -q "Live datanodes (3):"; then
  log "${LIVE_LINE}"
  mark_pass
else
  err "Belum 3 live DataNode. Report: ${LIVE_LINE:-<kosong>}"
  mark_fail
  warn "Tunggu 30–60 detik lalu jalankan script lagi, atau: docker restart datanode1 datanode2 datanode3"
fi

echo ""

# ============================================================
# Tes 2 — Kafka produce-consume
# ============================================================
test_log "Tes 2: Kafka produce-consume di topic 'airquality-api'..."

TEST_MSG="sanity-test-$(date +%s)"

echo "${TEST_MSG}" | docker exec -i kafka-broker \
  kafka-console-producer.sh \
  --topic airquality-api \
  --bootstrap-server localhost:9092 \
  >/dev/null 2>&1

RECEIVED=$(docker exec kafka-broker \
  timeout 15 kafka-console-consumer.sh \
  --topic airquality-api \
  --from-beginning \
  --bootstrap-server localhost:9092 \
  --max-messages 200 2>/dev/null | grep -F "${TEST_MSG}" | head -n1 || true)

if [[ -n "${RECEIVED}" ]]; then
  log "Pesan tes berhasil produce & consume: '${RECEIVED}'"
  mark_pass
else
  err "Pesan tes tidak diterima dalam 15 detik"
  mark_fail
fi

echo ""

# ============================================================
# Tes 3 — HDFS write, fsck (replication), read, delete
# ============================================================
test_log "Tes 3: HDFS put file + cek min replication + baca isi + hapus..."

TEST_FILE="/data/airquality/.sanity-check-$(date +%s).txt"
TEST_CONTENT="sanity-check-content-$(date +%s)"

echo "${TEST_CONTENT}" | docker exec -i namenode \
  hdfs dfs -put - "${TEST_FILE}" 2>/dev/null

# Biarkan block selesai di-replicate (replikasi 2)
sleep 3

FSCK_OUT=$(docker exec namenode hdfs fsck "${TEST_FILE}" -files -blocks 2>&1 || true)
if echo "${FSCK_OUT}" | grep -qi "Min replication: 2"; then
  log "fsck: Min replication: 2 (file tersebar 2+ DataNode)"
  mark_pass
else
  err "fsck tidak menunjuk Min replication: 2. Potensi under-replicated. Cuplikan:"
  err "$(echo "${FSCK_OUT}" | head -n 8)"
  mark_fail
fi

HDFS_CONTENT=$(docker exec namenode hdfs dfs -cat "${TEST_FILE}" 2>/dev/null || true)
if [[ "${HDFS_CONTENT}" == "${TEST_CONTENT}" ]]; then
  log "HDFS baca isi file OK"
  mark_pass
else
  err "HDFS read return: '${HDFS_CONTENT}' (expected: '${TEST_CONTENT}')"
  mark_fail
fi

docker exec namenode hdfs dfs -rm -f "${TEST_FILE}" >/dev/null 2>&1 || true

echo ""

# ============================================================
# Tes 4 — WebHDFS REST
# ============================================================
test_log "Tes 4: WebHDFS REST accessible dari host..."

if curl -fsS "http://localhost:9870/webhdfs/v1/data/airquality?op=LISTSTATUS" >/dev/null 2>&1; then
  log "WebHDFS REST OK di http://localhost:9870/webhdfs/v1/"
  mark_pass
else
  err "WebHDFS tidak accessible"
  mark_fail
fi

echo ""

# ============================================================
# Tes 5 — Port Kafka 9092 dari host
# ============================================================
test_log "Tes 5: Kafka port 9092 accessible dari host..."

if (echo > /dev/tcp/localhost/9092) >/dev/null 2>&1; then
  log "Port 9092 reachable dari host (producer/consumer lokal OK)"
  mark_pass
else
  err "Port 9092 tidak reachable"
  mark_fail
fi

echo ""

# ============================================================
# Ringkasan
# ============================================================
echo "=========================================="
TOTAL=$((PASS + FAIL))
if [[ $FAIL -eq 0 ]]; then
  log "SEMUA TES LULUS! ${PASS} tes lulus, 0 gagal."
  echo "=========================================="
  echo "HDFS: 3 DataNode, replikasi 2, cluster siap."
  echo "Lanjut Fase 2: producer (AQICN + RSS)."
  exit 0
else
  err "Ada ${FAIL} tes GAGAL (${PASS} lulus, total cek: ${TOTAL})."
  echo "=========================================="
  echo "Periksa log di atas. Under-replikasi: tunggu, lalu ulang; atau re-create vol dengan stop-stack --volumes."
  exit 1
fi
