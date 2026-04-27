"""
Dashboard Flask — Kelompok 6 ETS Big Data (AirQuality Alert).
Membaca spark_results.json, live_api.json, live_rss.json dari folder data/.
Jika file belum ada (pipeline belum jalan), mengembalikan contoh sehingga demo tetap jalan.
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Tuple

from flask import Flask, jsonify, render_template, request

app = Flask(__name__)
DATA_DIR = os.path.join(os.path.dirname(__file__), "data")

# Contoh agar demonstrasi jalan sebelum consumer & Spark selesai
DEMO_LIVE_API: List[Dict[str, Any]] = [
    {
        "city": "Surabaya",
        "aqi": 78,
        "pm25": 24.0,
        "source": "demo",
        "timestamp_ingest": "2026-04-27T10:00:00+00:00",
    },
    {
        "city": "Malang",
        "aqi": 42,
        "pm25": 12.0,
        "source": "demo",
        "timestamp_ingest": "2026-04-27T10:00:00+00:00",
    },
    {
        "city": "Sidoarjo",
        "aqi": 115,
        "pm25": 38.0,
        "source": "demo",
        "timestamp_ingest": "2026-04-27T10:00:00+00:00",
    },
    {
        "city": "Gresik",
        "aqi": 68,
        "pm25": 20.0,
        "source": "demo",
        "timestamp_ingest": "2026-04-27T10:00:00+00:00",
    },
    {
        "city": "Mojokerto",
        "aqi": 168,
        "pm25": 55.0,
        "source": "demo",
        "timestamp_ingest": "2026-04-27T10:00:00+00:00",
    },
]

DEMO_LIVE_RSS: List[Dict[str, Any]] = [
    {
        "title": "Contoh: Polusi di Jawa Timur Meningkat (demo)",
        "link": "https://www.tempo.co",
        "summary": "Aktifkan producer RSS agar data berita tampil di sini.",
        "published": "2026-04-27",
        "timestamp_ingest": "2026-04-27T10:00:00+00:00",
    }
]

DEMO_SPARK: Dict[str, Any] = {
    "generated_at": None,
    "analysis1": {
        "title": "1. Distribusi kategori AQI per kota (%)",
        "interpretation": "Contoh: setelah Spark jalan, persentase Baik/Sedang/Tidak Sehat/Berbahaya per kota muncul di sini.",
        "rows": [
            {
                "city": "Surabaya",
                "baik_pct": 25.0,
                "sedang_pct": 40.0,
                "tidak_sehat_pct": 30.0,
                "berbahaya_pct": 5.0,
            },
            {
                "city": "Malang",
                "baik_pct": 50.0,
                "sedang_pct": 35.0,
                "tidak_sehat_pct": 10.0,
                "berbahaya_pct": 5.0,
            },
        ],
    },
    "analysis2": {
        "title": "2. Rata-rata AQI per jam (puncak polusi) — Spark SQL",
        "interpretation": "Contoh: jam puncak polusi per kota; data dari historis HDFS.",
        "chart": [
            {"label": "Surabaya 07:00", "avg_aqi": 95.0},
            {"label": "Surabaya 18:00", "avg_aqi": 88.0},
            {"label": "Malang 08:00", "avg_aqi": 45.0},
        ],
    },
    "analysis3": {
        "title": "3. Ranking kota & event Tidak Sehat+",
        "interpretation": "Contoh: urutan rata-rata AQI tertinggi + jumlah hari/sampling dengan AQI ≥ 101.",
        "rows": [
            {"city": "Mojokerto", "avg_aqi": 120.0, "unhealthy_or_worse_events": 8},
            {"city": "Sidoarjo", "avg_aqi": 98.0, "unhealthy_or_worse_events": 5},
            {"city": "Surabaya", "avg_aqi": 85.0, "unhealthy_or_worse_events": 3},
        ],
    },
    "_demo": True,
}


def load_json_file(filename: str) -> Any:
    path = os.path.join(DATA_DIR, filename)
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return None


def aqi_label_and_class(aqi: float) -> Tuple[str, str]:
    if aqi <= 50:
        return "Baik", "aqi-bagus"
    if aqi <= 100:
        return "Sedang", "aqi-sedang"
    if aqi <= 150:
        return "Tidak Sehat", "aqi-tidak-sehat"
    return "Berbahaya", "aqi-berbahaya"


def normalize_spark(raw: Any) -> Dict[str, Any]:
    """Terima format baru {analysis1,2,3} atau lama: list ranking {city, average_pollution}."""
    now = datetime.now(timezone.utc).isoformat()
    if raw is None:
        out = json.loads(json.dumps(DEMO_SPARK))
        out["generated_at"] = now
        out["_demo"] = True
        return out
    if isinstance(raw, list):
        return {
            "generated_at": now,
            "analysis1": {
                "title": "1. Distribusi kategori AQI per kota (%)",
                "interpretation": "Lengkapi notebook untuk persentase per kategori.",
                "rows": [],
            },
            "analysis2": {
                "title": "2. Rata-rata AQI per jam (Spark SQL)",
                "interpretation": "",
                "chart": [],
            },
            "analysis3": {
                "title": "3. Ranking kota & event Tidak Sehat+",
                "interpretation": "",
                "rows": [
                    {
                        "city": r.get("city", ""),
                        "avg_aqi": float(r.get("average_pollution", 0) or 0),
                        "unhealthy_or_worse_events": int(
                            r.get("unhealthy_or_worse_events", 0) or 0
                        ),
                    }
                    for r in raw
                    if isinstance(r, dict)
                ],
            },
            "_legacy": True,
        }
    if isinstance(raw, dict):
        if all(k in raw for k in ("analysis1", "analysis2", "analysis3")):
            raw = dict(raw)
            raw.setdefault("generated_at", now)
            return raw
        merged = json.loads(json.dumps(DEMO_SPARK))
        merged.update(raw)
        merged.setdefault("generated_at", now)
        merged["_demo"] = raw.get("_demo", True)
        return merged
    return normalize_spark(None)


def normalize_live_api(raw: Any) -> List[Dict[str, Any]]:
    if raw is None:
        return [dict(x) for x in DEMO_LIVE_API]
    if isinstance(raw, dict):
        if raw.get("cities") and isinstance(raw["cities"], list):
            return [dict(x) for x in raw["cities"]]
        aqi = raw.get("aqi")
        if aqi is None and raw.get("value") is not None:
            try:
                aqi = float(raw["value"])
            except (TypeError, ValueError):
                aqi = 0.0
        if aqi is not None or raw.get("city"):
            city = raw.get("city", "—")
            aqi = float(aqi) if aqi is not None else 0.0
            return [
                {
                    "city": city,
                    "aqi": aqi,
                    "pm25": raw.get("pm25"),
                    "source": raw.get("source", "api"),
                    "timestamp_ingest": raw.get("timestamp_ingest")
                    or raw.get("timestamp")
                    or "",
                }
            ]
        return [dict(x) for x in DEMO_LIVE_API]
    if isinstance(raw, list) and raw:
        return [dict(x) for x in raw if isinstance(x, dict)]
    return [dict(x) for x in DEMO_LIVE_API]


def normalize_live_rss(raw: Any) -> List[Dict[str, Any]]:
    if raw is None:
        return [dict(x) for x in DEMO_LIVE_RSS]
    if isinstance(raw, dict) and raw.get("items") and isinstance(raw["items"], list):
        return [dict(x) for x in raw["items"]]
    if isinstance(raw, dict) and (raw.get("title") or raw.get("link")):
        return [dict(raw)]
    if isinstance(raw, list) and raw:
        return [dict(x) for x in raw if isinstance(x, dict)]
    return [dict(x) for x in DEMO_LIVE_RSS]


def build_payload(force_all_demo: bool = False) -> Dict[str, Any]:
    if force_all_demo:
        spark_raw = api_raw = rss_raw = None
    else:
        spark_raw = load_json_file("spark_results.json")
        api_raw = load_json_file("live_api.json")
        rss_raw = load_json_file("live_rss.json")

    spark = normalize_spark(spark_raw)
    live_api = normalize_live_api(api_raw)
    live_rss = normalize_live_rss(rss_raw)

    for row in live_api:
        aqi = float(row.get("aqi", 0) or 0)
        label, css = aqi_label_and_class(aqi)
        row["category_label"] = label
        row["category_class"] = css

    missing_api = force_all_demo or load_json_file("live_api.json") is None
    missing_rss = force_all_demo or load_json_file("live_rss.json") is None
    missing_spark = force_all_demo or load_json_file("spark_results.json") is None

    return {
        "spark": spark,
        "api": {
            "cities": live_api,
            "is_demo": missing_api,
        },
        "rss": {
            "items": live_rss,
            "is_demo": missing_rss,
        },
        "meta": {
            "spark_from_file": not missing_spark and not force_all_demo,
            "demo_spark": bool(spark.get("_demo")),
        },
    }


def _api_response():
    force_demo = request.args.get("demo", "").lower() in ("1", "true", "yes")
    payload = build_payload(force_all_demo=force_demo)
    payload["refreshed_at"] = datetime.now(timezone.utc).isoformat()
    return jsonify(payload)


@app.route("/")
def index():
    return render_template(
        "index.html",
        kelompok=6,
        body_class="dashboard dashboard--sharp",
    )


@app.route("/api/data")
def api_data():
    return _api_response()


@app.route("/api/status")
def api_status():
    """Alias kompatibel dengan kode lama."""
    return _api_response()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "5000"))
    app.run(host="0.0.0.0", port=port, debug=True)
