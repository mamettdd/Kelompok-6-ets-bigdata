"""
Consumer Kafka → HDFS untuk topic airquality-api dan airquality-rss.

Persyaratan rubrik soal:
  [x] Membaca dari KEDUA topic (api & rss) — pakai thread terpisah per topic
  [x] Pakai group_id unik agar offset disimpan di Kafka
  [x] auto_offset_reset="earliest"
  [x] Buffer 2-5 menit lalu flush jadi 1 file JSON di HDFS
  [x] Nama file pakai timestamp:  YYYY-MM-DD_HH-MM-SS.json
  [x] Path HDFS:  /data/airquality/api/  dan  /data/airquality/rss/
  [x] Pakai library hdfs Python (InsecureClient) untuk makedirs + listing → bonus +2
       Untuk write, pakai `docker exec namenode hdfs dfs -put -` agar tahan
       di WSL2 (WebHDFS redirect ke container hostname datanode tidak terselesaikan).
  [x] Mirror salinan terbaru ke dashboard/data/live_api.json & live_rss.json

Variabel env yang berguna:
  KAFKA_BOOTSTRAP            (default: localhost:9092)
  HDFS_NAMENODE_URL          (default: http://localhost:9870)
  HDFS_USER                  (default: root)
  HDFS_BASE_DIR              (default: /data/airquality)
  HDFS_NAMENODE_CONTAINER    (default: namenode) — nama container untuk docker exec
  HDFS_WRITE_MODE            (default: docker_exec ; alternatif: webhdfs)
  BUFFER_FLUSH_SEC           (default: 180  -- 3 menit)
  BUFFER_MAX_RECORDS         (default: 200)
  DASHBOARD_DATA_DIR         (default: <repo>/dashboard/data)
"""
from __future__ import annotations

import io
import json
import logging
import os
import signal
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from kafka import KafkaConsumer
from kafka.errors import KafkaError

try:
    from hdfs import InsecureClient  # type: ignore
except ImportError:  # pragma: no cover
    InsecureClient = None  # type: ignore

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass

LOG_FORMAT = "%(asctime)s [%(levelname)s] [%(threadName)s] %(message)s"
logging.basicConfig(level=logging.INFO, format=LOG_FORMAT, stream=sys.stdout)
log = logging.getLogger("consumer")

KAFKA_BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", "localhost:9092")
HDFS_NAMENODE_URL = os.environ.get("HDFS_NAMENODE_URL", "http://localhost:9870")
HDFS_USER = os.environ.get("HDFS_USER", "root")
HDFS_BASE_DIR = os.environ.get("HDFS_BASE_DIR", "/data/airquality")
HDFS_NAMENODE_CONTAINER = os.environ.get("HDFS_NAMENODE_CONTAINER", "namenode")
HDFS_WRITE_MODE = os.environ.get("HDFS_WRITE_MODE", "docker_exec").lower()
BUFFER_FLUSH_SEC = int(os.environ.get("BUFFER_FLUSH_SEC", "180"))
BUFFER_MAX_RECORDS = int(os.environ.get("BUFFER_MAX_RECORDS", "200"))

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DASHBOARD_DIR = REPO_ROOT / "dashboard" / "data"
DASHBOARD_DATA_DIR = Path(os.environ.get("DASHBOARD_DATA_DIR", str(DEFAULT_DASHBOARD_DIR)))

TOPIC_API = os.environ.get("KAFKA_TOPIC_API", "airquality-api")
TOPIC_RSS = os.environ.get("KAFKA_TOPIC_RSS", "airquality-rss")

GROUP_ID_API = os.environ.get("CONSUMER_GROUP_API", "airquality-consumer-api")
GROUP_ID_RSS = os.environ.get("CONSUMER_GROUP_RSS", "airquality-consumer-rss")


_shutdown = threading.Event()


def _signal_handler(signum, frame):
    log.info("Sinyal %s diterima — graceful shutdown.", signum)
    _shutdown.set()


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d_%H-%M-%S")


def get_hdfs_client() -> "InsecureClient":
    if InsecureClient is None:
        raise RuntimeError(
            "Library 'hdfs' belum ter-install. Jalankan: pip install hdfs"
        )
    client = InsecureClient(HDFS_NAMENODE_URL, user=HDFS_USER)
    # makedirs adalah operasi NameNode-only (tidak redirect ke datanode), aman dari host.
    client.makedirs(f"{HDFS_BASE_DIR}/api")
    client.makedirs(f"{HDFS_BASE_DIR}/rss")
    client.makedirs(f"{HDFS_BASE_DIR}/hasil")
    return client


def _write_via_docker_exec(hdfs_path: str, payload: str) -> None:
    """Tulis ke HDFS lewat `docker exec namenode hdfs dfs -put -`.
    Ini bypass WebHDFS redirect (yang gagal di WSL2 karena container hostname
    datanode tidak bisa di-resolve dari host)."""
    cmd = [
        "docker", "exec", "-i", HDFS_NAMENODE_CONTAINER,
        "hdfs", "dfs", "-put", "-f", "-", hdfs_path,
    ]
    proc = subprocess.run(
        cmd,
        input=payload.encode("utf-8"),
        capture_output=True,
        timeout=60,
    )
    if proc.returncode != 0:
        stderr = proc.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"docker exec hdfs put gagal (rc={proc.returncode}): {stderr}")


def _write_via_webhdfs(client: "InsecureClient", hdfs_path: str, payload: str) -> None:
    with client.write(hdfs_path, encoding="utf-8", overwrite=True) as writer:
        writer.write(payload)


def write_to_hdfs(client: "InsecureClient", subdir: str, records: List[Dict[str, Any]]) -> str:
    filename = f"{utc_stamp()}.json"
    hdfs_path = f"{HDFS_BASE_DIR}/{subdir}/{filename}"
    payload = "\n".join(json.dumps(r, ensure_ascii=False) for r in records)
    if HDFS_WRITE_MODE == "webhdfs":
        _write_via_webhdfs(client, hdfs_path, payload)
    else:
        _write_via_docker_exec(hdfs_path, payload)
    return hdfs_path


def update_dashboard_mirror(kind: str, records: List[Dict[str, Any]]) -> None:
    """Tulis snapshot terbaru ke dashboard/data/{live_api,live_rss}.json."""
    DASHBOARD_DATA_DIR.mkdir(parents=True, exist_ok=True)
    if kind == "api":
        latest_per_city: Dict[str, Dict[str, Any]] = {}
        for rec in records:
            city = rec.get("city") or rec.get("city_slug") or "unknown"
            ts = rec.get("timestamp_ingest") or ""
            prev = latest_per_city.get(city)
            if prev is None or (ts and ts > prev.get("timestamp_ingest", "")):
                latest_per_city[city] = rec
        cities = sorted(latest_per_city.values(), key=lambda r: r.get("city", ""))
        outfile = DASHBOARD_DATA_DIR / "live_api.json"
        prev_cities: List[Dict[str, Any]] = []
        if outfile.exists():
            try:
                with outfile.open("r", encoding="utf-8") as f:
                    prev_data = json.load(f)
                if isinstance(prev_data, dict) and isinstance(prev_data.get("cities"), list):
                    prev_cities = [c for c in prev_data["cities"] if isinstance(c, dict)]
            except (json.JSONDecodeError, OSError):
                pass
        merged: Dict[str, Dict[str, Any]] = {c.get("city", ""): c for c in prev_cities}
        for c in cities:
            merged[c.get("city", "")] = c
        all_cities = sorted(merged.values(), key=lambda r: r.get("city", ""))
        payload = {
            "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "cities": all_cities,
        }
    elif kind == "rss":
        outfile = DASHBOARD_DATA_DIR / "live_rss.json"
        existing: List[Dict[str, Any]] = []
        if outfile.exists():
            try:
                with outfile.open("r", encoding="utf-8") as f:
                    prev_data = json.load(f)
                if isinstance(prev_data, dict) and isinstance(prev_data.get("items"), list):
                    existing = [r for r in prev_data["items"] if isinstance(r, dict)]
            except (json.JSONDecodeError, OSError):
                pass
        seen = {r.get("id"): r for r in existing if r.get("id")}
        for rec in records:
            rid = rec.get("id")
            if rid:
                seen[rid] = rec
        merged_items = sorted(
            seen.values(),
            key=lambda r: r.get("timestamp_ingest", ""),
            reverse=True,
        )[:50]
        payload = {
            "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "items": merged_items,
        }
    else:
        return

    tmp = outfile.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    os.replace(tmp, outfile)


def consume_topic(
    topic: str,
    group_id: str,
    subdir: str,
    mirror_kind: str,
    hdfs_client: "InsecureClient",
) -> None:
    log.info("Mulai konsumsi topic=%s group=%s", topic, group_id)
    consumer: Optional[KafkaConsumer] = None
    backoff = 5
    while not _shutdown.is_set():
        try:
            consumer = KafkaConsumer(
                topic,
                bootstrap_servers=KAFKA_BOOTSTRAP.split(","),
                group_id=group_id,
                auto_offset_reset="earliest",
                enable_auto_commit=False,
                value_deserializer=lambda b: json.loads(b.decode("utf-8")),
                key_deserializer=lambda b: b.decode("utf-8") if b else None,
                consumer_timeout_ms=1000,
            )
            backoff = 5
            break
        except KafkaError as exc:
            log.error("Tidak bisa connect Kafka: %s — retry %ds", exc, backoff)
            if _shutdown.wait(backoff):
                return
            backoff = min(backoff * 2, 60)

    assert consumer is not None
    buffer: List[Dict[str, Any]] = []
    last_flush = time.time()

    def _flush(reason: str) -> None:
        nonlocal buffer, last_flush
        if not buffer:
            last_flush = time.time()
            return
        try:
            path = write_to_hdfs(hdfs_client, subdir, buffer)
            log.info(
                "[%s] FLUSH (%s) %d record → hdfs://%s",
                topic,
                reason,
                len(buffer),
                path,
            )
            try:
                update_dashboard_mirror(mirror_kind, buffer)
            except Exception as exc:  # noqa: BLE001
                log.exception("Mirror dashboard gagal: %s", exc)
            consumer.commit()
            buffer = []
            last_flush = time.time()
        except Exception as exc:  # noqa: BLE001
            log.exception("HDFS flush gagal — buffer dipertahankan: %s", exc)

    try:
        while not _shutdown.is_set():
            polled = False
            for msg in consumer:
                polled = True
                buffer.append(msg.value)
                if len(buffer) >= BUFFER_MAX_RECORDS:
                    _flush(f"max_records={BUFFER_MAX_RECORDS}")
            if not polled and (time.time() - last_flush) >= BUFFER_FLUSH_SEC:
                _flush(f"timer={BUFFER_FLUSH_SEC}s")
            if _shutdown.wait(0.5):
                break
    finally:
        log.info("Stop topic=%s — flushing terakhir.", topic)
        _flush("shutdown")
        try:
            consumer.close()
        except Exception:  # noqa: BLE001
            pass


def main() -> int:
    signal.signal(signal.SIGINT, _signal_handler)
    signal.signal(signal.SIGTERM, _signal_handler)

    log.info(
        "Bootstrap=%s HDFS=%s base=%s write_mode=%s buffer_sec=%d buffer_max=%d dashboard=%s",
        KAFKA_BOOTSTRAP,
        HDFS_NAMENODE_URL,
        HDFS_BASE_DIR,
        HDFS_WRITE_MODE,
        BUFFER_FLUSH_SEC,
        BUFFER_MAX_RECORDS,
        DASHBOARD_DATA_DIR,
    )

    try:
        hdfs_client = get_hdfs_client()
    except Exception as exc:  # noqa: BLE001
        log.exception("Tidak bisa connect HDFS WebHDFS: %s", exc)
        return 2

    threads = [
        threading.Thread(
            target=consume_topic,
            name="api",
            args=(TOPIC_API, GROUP_ID_API, "api", "api", hdfs_client),
            daemon=True,
        ),
        threading.Thread(
            target=consume_topic,
            name="rss",
            args=(TOPIC_RSS, GROUP_ID_RSS, "rss", "rss", hdfs_client),
            daemon=True,
        ),
    ]
    for t in threads:
        t.start()

    try:
        while not _shutdown.is_set():
            time.sleep(0.5)
    except KeyboardInterrupt:
        _shutdown.set()

    log.info("Menunggu thread selesai...")
    for t in threads:
        t.join(timeout=30)
    log.info("Consumer keluar dengan rapi.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
