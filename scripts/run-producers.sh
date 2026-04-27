#!/usr/bin/env bash
# Menjalankan kedua producer (API + RSS) di background.
# Output dialihkan ke logs/producer_api.log & logs/producer_rss.log
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

API_LOG="logs/producer_api.log"
RSS_LOG="logs/producer_rss.log"

if pgrep -f "kafka/producer_api.py" >/dev/null; then
  echo "[INFO] producer_api.py sudah jalan (skip)."
else
  echo "[INFO] Start producer_api.py -> $API_LOG"
  nohup python kafka/producer_api.py >>"$API_LOG" 2>&1 &
  echo "       PID=$!"
fi

if pgrep -f "kafka/producer_rss.py" >/dev/null; then
  echo "[INFO] producer_rss.py sudah jalan (skip)."
else
  echo "[INFO] Start producer_rss.py -> $RSS_LOG"
  nohup python kafka/producer_rss.py >>"$RSS_LOG" 2>&1 &
  echo "       PID=$!"
fi

sleep 1
echo
echo "Cek proses:"
pgrep -f "kafka/producer_(api|rss).py" -a || true
echo
echo "Pantau log:"
echo "  tail -f $API_LOG"
echo "  tail -f $RSS_LOG"
