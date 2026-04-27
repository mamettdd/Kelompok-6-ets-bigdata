#!/usr/bin/env bash
# Menjalankan consumer_to_hdfs.py di background.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -d ".venv" ]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi

if [ -f .env ]; then
  set -a; source .env; set +a
fi

mkdir -p logs
LOG="logs/consumer.log"

if pgrep -f "kafka/consumer_to_hdfs.py" >/dev/null; then
  echo "[INFO] consumer_to_hdfs.py sudah jalan (skip)."
else
  echo "[INFO] Start consumer_to_hdfs.py -> $LOG"
  nohup python kafka/consumer_to_hdfs.py >>"$LOG" 2>&1 &
  echo "       PID=$!"
fi

sleep 1
pgrep -f "kafka/consumer_to_hdfs.py" -a || true
echo
echo "Pantau log:"
echo "  tail -f $LOG"
