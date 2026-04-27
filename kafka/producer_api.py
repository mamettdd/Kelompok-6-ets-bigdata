"""
Producer Kafka untuk data AQI real-time (Topic: airquality-api).

Sumber data:
  - Utama   : AQICN World Air Quality Index API (butuh token AQICN_TOKEN di .env)
              https://aqicn.org/data-platform/token/
  - Fallback: Simulator (random realistis) — otomatis aktif jika token kosong/error

Persyaratan rubrik soal:
  [x] Polling tiap 15 menit (POLL_INTERVAL_SEC = 900)
  [x] Format JSON konsisten dengan field timestamp
  [x] Producer pakai acks="all" (delivery durability)
      + retries=10 + max_in_flight=1 (Python equivalent dari Java enable_idempotence)
  [x] Send dengan key = nama kota (lower-case, snake-case)
  [x] 5 kota Gerbangkertasusila: Surabaya, Malang, Sidoarjo, Gresik, Mojokerto
"""
from __future__ import annotations

import json
import logging
import os
import random
import signal
import sys
import time
from datetime import datetime, timezone
from typing import Any, Dict, Optional

import requests
from kafka import KafkaProducer
from kafka.errors import KafkaError

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass

LOG_FORMAT = "%(asctime)s [%(levelname)s] %(message)s"
logging.basicConfig(level=logging.INFO, format=LOG_FORMAT, stream=sys.stdout)
log = logging.getLogger("producer_api")

KAFKA_BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", "localhost:9092")
TOPIC = os.environ.get("KAFKA_TOPIC_API", "airquality-api")
POLL_INTERVAL_SEC = int(os.environ.get("POLL_INTERVAL_SEC", "900"))  # 15 menit (rubrik)
HTTP_TIMEOUT_SEC = int(os.environ.get("HTTP_TIMEOUT_SEC", "10"))
AQICN_TOKEN = os.environ.get("AQICN_TOKEN", "").strip()
FORCE_SIMULATOR = os.environ.get("FORCE_SIMULATOR", "0").lower() in ("1", "true", "yes")

CITIES = [
    {"name": "Surabaya", "slug": "surabaya"},
    {"name": "Malang", "slug": "malang"},
    {"name": "Sidoarjo", "slug": "sidoarjo"},
    {"name": "Gresik", "slug": "gresik"},
    {"name": "Mojokerto", "slug": "mojokerto"},
]


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def fetch_aqicn(slug: str, token: str) -> Optional[Dict[str, Any]]:
    """Panggil AQICN. Return dict event terstandarisasi, atau None bila gagal."""
    url = f"https://api.waqi.info/feed/{slug}/?token={token}"
    try:
        r = requests.get(url, timeout=HTTP_TIMEOUT_SEC)
        r.raise_for_status()
        body = r.json()
    except (requests.RequestException, ValueError) as exc:
        log.warning("AQICN gagal untuk %s: %s", slug, exc)
        return None
    if body.get("status") != "ok":
        log.warning("AQICN status != ok untuk %s: %s", slug, body.get("data"))
        return None
    data = body.get("data", {})
    iaqi = data.get("iaqi", {}) or {}

    def _g(k: str) -> Optional[float]:
        v = iaqi.get(k, {})
        if isinstance(v, dict):
            val = v.get("v")
            try:
                return float(val) if val is not None else None
            except (TypeError, ValueError):
                return None
        return None

    aqi_raw = data.get("aqi")
    try:
        aqi_val = float(aqi_raw)
    except (TypeError, ValueError):
        return None
    return {
        "aqi": aqi_val,
        "pm25": _g("pm25"),
        "pm10": _g("pm10"),
        "o3": _g("o3"),
        "no2": _g("no2"),
        "so2": _g("so2"),
        "co": _g("co"),
        "dominent_pollutant": data.get("dominentpol"),
        "station_name": (data.get("city") or {}).get("name"),
        "observed_at": (data.get("time") or {}).get("iso"),
        "source": "aqicn",
    }


def simulate_event(city_name: str) -> Dict[str, Any]:
    """Simulator dengan distribusi mirip kondisi Jatim:
    - Surabaya/Sidoarjo/Gresik cenderung lebih buruk (kawasan industri)
    - Malang lebih bersih (pegunungan)
    - Mojokerto sedang.
    """
    base = {
        "Surabaya": 95,
        "Sidoarjo": 105,
        "Gresik": 110,
        "Mojokerto": 80,
        "Malang": 55,
    }.get(city_name, 80)
    aqi = max(5, int(random.gauss(base, 25)))
    pm25 = round(max(1.0, aqi * 0.42 + random.uniform(-3, 3)), 1)
    pm10 = round(pm25 + random.uniform(5, 20), 1)
    return {
        "aqi": float(aqi),
        "pm25": pm25,
        "pm10": pm10,
        "o3": round(random.uniform(5, 50), 1),
        "no2": round(random.uniform(2, 30), 1),
        "so2": round(random.uniform(1, 10), 1),
        "co": round(random.uniform(0.1, 1.5), 2),
        "dominent_pollutant": "pm25",
        "station_name": f"Simulator {city_name}",
        "observed_at": utc_now_iso(),
        "source": "simulator",
    }


def build_event(city: Dict[str, str], use_simulator: bool, token: str) -> Optional[Dict[str, Any]]:
    if use_simulator:
        payload = simulate_event(city["name"])
    else:
        payload = fetch_aqicn(city["slug"], token)
        if payload is None:
            log.info("Fallback simulator untuk %s", city["name"])
            payload = simulate_event(city["name"])
    payload["city"] = city["name"]
    payload["city_slug"] = city["slug"]
    payload["timestamp_ingest"] = utc_now_iso()
    return payload


def make_producer() -> KafkaProducer:
    # Catatan: kafka-python(-ng) tidak punya `enable_idempotence` (itu Java-only).
    # Equivalent at-least-once + ordering ketat di Python:
    #   acks=all + retries tinggi + max_in_flight=1 (urutan dipertahankan saat retry)
    return KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP.split(","),
        acks="all",
        retries=10,
        max_in_flight_requests_per_connection=1,
        linger_ms=50,
        compression_type="gzip",
        key_serializer=lambda k: k.encode("utf-8") if isinstance(k, str) else k,
        value_serializer=lambda v: json.dumps(v, ensure_ascii=False).encode("utf-8"),
    )


_running = True


def _signal_handler(signum, frame):
    global _running
    log.info("Sinyal %s diterima — keluar setelah flush.", signum)
    _running = False


def main() -> int:
    signal.signal(signal.SIGINT, _signal_handler)
    signal.signal(signal.SIGTERM, _signal_handler)

    use_simulator = FORCE_SIMULATOR or not AQICN_TOKEN
    if use_simulator:
        log.warning(
            "Mode SIMULATOR aktif (token AQICN kosong / FORCE_SIMULATOR). "
            "Daftar token gratis: https://aqicn.org/data-platform/token/"
        )
    else:
        log.info("Mode AQICN aktif (token panjang %d karakter).", len(AQICN_TOKEN))

    log.info(
        "Bootstrap=%s topic=%s interval=%ds kota=%d",
        KAFKA_BOOTSTRAP,
        TOPIC,
        POLL_INTERVAL_SEC,
        len(CITIES),
    )

    producer = make_producer()

    cycle = 0
    while _running:
        cycle += 1
        log.info("=== Polling cycle #%d ===", cycle)
        sent = 0
        for city in CITIES:
            try:
                event = build_event(city, use_simulator=use_simulator, token=AQICN_TOKEN)
                if event is None:
                    continue
                future = producer.send(TOPIC, key=city["slug"], value=event)
                future.add_errback(lambda exc, c=city["name"]: log.error("Send fail %s: %s", c, exc))
                aqi_str = f"{event['aqi']:.0f}" if isinstance(event["aqi"], (int, float)) else "?"
                log.info(
                    "Kirim %-10s aqi=%s src=%s",
                    city["name"],
                    aqi_str,
                    event.get("source"),
                )
                sent += 1
            except KafkaError as exc:
                log.error("KafkaError saat kirim %s: %s", city["name"], exc)
            except Exception as exc:  # noqa: BLE001
                log.exception("Error tak terduga %s: %s", city["name"], exc)

        try:
            producer.flush(timeout=15)
            log.info("Cycle #%d selesai — %d/%d event terkirim.", cycle, sent, len(CITIES))
        except KafkaError as exc:
            log.error("Flush gagal: %s", exc)

        for _ in range(POLL_INTERVAL_SEC):
            if not _running:
                break
            time.sleep(1)

    log.info("Menutup producer.")
    try:
        producer.flush(timeout=10)
        producer.close(timeout=10)
    except Exception:  # noqa: BLE001
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
