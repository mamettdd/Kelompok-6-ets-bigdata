#!/usr/bin/env bash
# Hentikan producer & consumer pipeline.
set -euo pipefail

for pat in "kafka/producer_api.py" "kafka/producer_rss.py" "kafka/consumer_to_hdfs.py"; do
  pids=$(pgrep -f "$pat" || true)
  if [ -n "$pids" ]; then
    echo "[INFO] Kill $pat (PID: $pids)"
    pkill -f "$pat" || true
  fi
done

sleep 1
remaining=$(pgrep -f "kafka/(producer_api|producer_rss|consumer_to_hdfs).py" || true)
if [ -z "$remaining" ]; then
  echo "[OK] Semua proses pipeline berhenti."
else
  echo "[WARN] Masih jalan:"
  pgrep -f "kafka/(producer_api|producer_rss|consumer_to_hdfs).py" -a || true
fi
