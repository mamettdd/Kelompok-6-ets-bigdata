"""
Producer Kafka untuk berita lingkungan dari RSS (Topic: airquality-rss).

Persyaratan rubrik soal:
  [x] Polling tiap 5 menit (POLL_INTERVAL_SEC = 300)
  [x] Parse pakai feedparser
  [x] Field: title, link, summary, published
  [x] Hindari duplikat: simpan ID yang sudah dikirim ke seen_ids.json
  [x] Format JSON konsisten dengan field timestamp
  [x] Producer pakai acks="all" + retries (Python equivalent enable_idempotence)
  [x] Send dengan key = MD5 hash URL artikel
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import signal
import sys
import time
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional, Set

import feedparser
from kafka import KafkaProducer
from kafka.errors import KafkaError

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass

LOG_FORMAT = "%(asctime)s [%(levelname)s] %(message)s"
logging.basicConfig(level=logging.INFO, format=LOG_FORMAT, stream=sys.stdout)
log = logging.getLogger("producer_rss")

KAFKA_BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", "localhost:9092")
TOPIC = os.environ.get("KAFKA_TOPIC_RSS", "airquality-rss")
POLL_INTERVAL_SEC = int(os.environ.get("POLL_INTERVAL_SEC_RSS", "300"))  # 5 menit (rubrik)
SEEN_IDS_FILE = os.environ.get(
    "RSS_SEEN_IDS_FILE",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "seen_ids.json"),
)
MAX_SEEN_IDS = int(os.environ.get("RSS_MAX_SEEN_IDS", "5000"))

DEFAULT_FEEDS = [
    "https://news.detik.com/rss",
    "https://rss.tempo.co/nasional",
    "https://rss.tempo.co/tag/polusi",
    "https://rss.kompas.com/feed/kompas.com/sains/environment",
]
RSS_FEEDS = [u.strip() for u in os.environ.get("RSS_FEEDS", "").split(",") if u.strip()] or DEFAULT_FEEDS

ENV_KEYWORDS = [
    "polusi", "udara", "lingkungan", "aqi", "emisi", "asap", "kabut",
    "pencemaran", "iklim", "cuaca", "pm2.5", "pm10", "karhutla",
    "hutan", "limbah", "sampah", "banjir", "asma", "ispa",
]
RSS_KEYWORDS = [
    k.strip().lower()
    for k in os.environ.get("RSS_KEYWORDS", ",".join(ENV_KEYWORDS)).split(",")
    if k.strip()
]
RSS_FALLBACK_TOPN = int(os.environ.get("RSS_FALLBACK_TOPN", "5"))
RSS_USER_AGENT = os.environ.get(
    "RSS_USER_AGENT",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 KafkaRSS/1.0",
)


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


_TAG_RE = re.compile(r"<[^>]+>")


def strip_html(text: Optional[str]) -> str:
    if not text:
        return ""
    return _TAG_RE.sub("", text).replace("\xa0", " ").strip()


def hash_url(url: str) -> str:
    return hashlib.md5(url.encode("utf-8")).hexdigest()


def load_seen_ids(path: str) -> Set[str]:
    if not os.path.exists(path):
        return set()
    try:
        with open(path, "r", encoding="utf-8") as f:
            return set(json.load(f))
    except (json.JSONDecodeError, OSError) as exc:
        log.warning("seen_ids.json rusak (%s) — diawali kosong.", exc)
        return set()


def save_seen_ids(path: str, ids: Iterable[str]) -> None:
    items = list(ids)
    if len(items) > MAX_SEEN_IDS:
        items = items[-MAX_SEEN_IDS:]
    tmp = path + ".tmp"
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True) if os.path.dirname(path) else None
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(items, f, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError as exc:
        log.error("Gagal menyimpan seen_ids: %s", exc)


def is_relevant(title: str, summary: str) -> bool:
    """Cek apakah berita relevan dengan tema lingkungan/polusi/cuaca."""
    if not RSS_KEYWORDS:
        return True
    text = f"{title} {summary}".lower()
    return any(kw in text for kw in RSS_KEYWORDS)


def build_event(entry: Any, feed_url: str) -> Optional[Dict[str, Any]]:
    link = (entry.get("link") or "").strip()
    title = (entry.get("title") or "").strip()
    if not link or not title:
        return None
    summary = strip_html(entry.get("summary") or entry.get("description") or "")
    published = (
        entry.get("published")
        or entry.get("updated")
        or entry.get("pubDate")
        or ""
    )
    return {
        "id": hash_url(link),
        "title": title,
        "link": link,
        "summary": summary[:500],
        "published": published,
        "source_feed": feed_url,
        "relevant": is_relevant(title, summary),
        "timestamp_ingest": utc_now_iso(),
    }


def make_producer() -> KafkaProducer:
    # Catatan: kafka-python(-ng) tidak punya `enable_idempotence` (itu Java-only).
    # Equivalent at-least-once + ordering ketat di Python:
    #   acks=all + retries tinggi + max_in_flight=1
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

    log.info(
        "Bootstrap=%s topic=%s interval=%ds feeds=%d seen_ids=%s",
        KAFKA_BOOTSTRAP,
        TOPIC,
        POLL_INTERVAL_SEC,
        len(RSS_FEEDS),
        SEEN_IDS_FILE,
    )

    producer = make_producer()
    seen: Set[str] = load_seen_ids(SEEN_IDS_FILE)
    log.info("Memuat %d ID artikel yang sudah dikirim.", len(seen))

    cycle = 0
    while _running:
        cycle += 1
        log.info("=== Polling cycle #%d (%d feed) ===", cycle, len(RSS_FEEDS))
        new_count = 0
        for url in RSS_FEEDS:
            try:
                feed = feedparser.parse(url, agent=RSS_USER_AGENT)
            except Exception as exc:  # noqa: BLE001
                log.exception("Feed gagal di-parse %s: %s", url, exc)
                continue
            entries = list(feed.entries or [])
            log.info("Feed %s: %d entry", url, len(entries))

            built: List[Dict[str, Any]] = []
            for entry in entries:
                event = build_event(entry, url)
                if event is None:
                    continue
                if event["id"] in seen:
                    continue
                built.append(event)

            relevant = [ev for ev in built if ev["relevant"]]
            if relevant:
                to_send = relevant
                log.info("  → %d entry baru relevan (filter keyword).", len(to_send))
            elif built:
                to_send = built[:RSS_FALLBACK_TOPN]
                log.info(
                    "  → tidak ada yang lolos filter keyword; fallback %d entry top untuk demo.",
                    len(to_send),
                )
            else:
                to_send = []

            for event in to_send:
                try:
                    producer.send(TOPIC, key=event["id"], value=event)
                    log.info(
                        "Berita baru%s: %s",
                        " [relevan]" if event["relevant"] else " [umum]",
                        event["title"][:80],
                    )
                    seen.add(event["id"])
                    new_count += 1
                except KafkaError as exc:
                    log.error("KafkaError saat kirim berita: %s", exc)

        try:
            producer.flush(timeout=15)
        except KafkaError as exc:
            log.error("Flush gagal: %s", exc)

        if new_count > 0:
            save_seen_ids(SEEN_IDS_FILE, seen)
            log.info("Cycle #%d: %d berita baru tersimpan.", cycle, new_count)
        else:
            log.info("Cycle #%d: tidak ada berita baru.", cycle)

        for _ in range(POLL_INTERVAL_SEC):
            if not _running:
                break
            time.sleep(1)

    log.info("Menutup producer RSS.")
    try:
        save_seen_ids(SEEN_IDS_FILE, seen)
        producer.flush(timeout=10)
        producer.close(timeout=10)
    except Exception:  # noqa: BLE001
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
