#!/usr/bin/env bash
# Bring-up end-to-end:
#   1) Docker stack (Hadoop + Kafka)
#   2) init topic + folder HDFS (idempotent)
#   3) producers (API + RSS)
#   4) consumer ke HDFS
#   5) Dashboard Flask (foreground)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash "$ROOT/scripts/start-stack.sh"

echo "[INFO] Tunggu Hadoop/Kafka siap (45 detik)..."
sleep 45

bash "$ROOT/scripts/init-infra.sh" || true

bash "$ROOT/scripts/run-producers.sh"
bash "$ROOT/scripts/run-consumer.sh"

echo
echo "============================================="
echo "  Pipeline jalan di background."
echo "  Dashboard akan mulai di port \${PORT:-5000}."
echo "  Stop pipeline:  bash scripts/stop-pipeline.sh"
echo "  Stop stack   :  bash scripts/stop-stack.sh"
echo "============================================="
echo

exec bash "$ROOT/scripts/run-dashboard.sh"
