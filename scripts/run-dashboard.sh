#!/usr/bin/env bash
# Jalankan dashboard Flask di http://0.0.0.0:5000
# Pakai dari root repo: bash scripts/run-dashboard.sh

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .venv/bin/activate ]]; then
  # shellcheck source=/dev/null
  source .venv/bin/activate
fi

export FLASK_APP=dashboard.app:app
export PORT="${PORT:-5000}"
echo "Dashboard: http://127.0.0.1:${PORT}/  |  API: http://127.0.0.1:${PORT}/api/data"
echo "Tekan Ctrl+C untuk berhenti. (Ganti port: PORT=5001 bash $0)"
exec python -u dashboard/app.py
