# Alamat & Tujuan Source Code — AirQuality Alert (Kelompok 6)

Dokumen ini menjelaskan **di mana file/folder berada** di repositori dan **untuk apa** dipakai. Berguna saat navigasi kode, demo, atau onboarding anggota baru. Untuk alur arsitektur lengkap, lihat [`architecture.md`](./architecture.md).

---

## Akar repositori (`/`)

| Lokasi | Tujuan |
|--------|--------|
| `README.md` | Dokumentasi utama: setup, demo, troubleshooting. |
| `architecture.md` | Arsitektur, alur data, penjelasan teknis + eksekutif. |
| `address.md` | **Dokumen ini** — peta file & path runtime (HDFS, Kafka, dll.). |
| `CHECKLIST.md` | Checklist pengerjaan / verifikasi rubrik. |
| `requirements.txt` | Dependensi Python (Flask, PySpark, kafka-python-ng, hdfs, dll.). |
| `.env` | **Rahasia lokal** — token AQICN, interval, path HDFS, consumer group, RSS, buffer. **Jangan di-commit.** |
| `.env.example` | Contoh variabel (tanpa rahasia) untuk disalin ke `.env`. |
| `.gitignore` | Mengabaikan `.venv/`, `.env`, log, JSON data dashboard, `seen_ids.json`, dll. |
| `hadoop.env` | Variabel lingkungan untuk image Hadoop (termasuk `fs.defaultFS`, `dfs.replication`, dll.). |
| `docker-compose-hadoop.yml` | Definisi cluster Hadoop: NameNode, **3× DataNode**, ResourceManager, NodeManager, jaringan & volume. |
| `docker-compose-kafka.yml` | Zookeeper + **Kafka broker** (topik tidak otomatis dibuat kecuali diset lain — lihat init). |

---

## Skrip bantu (`scripts/`)

| File | Tujuan |
|------|--------|
| `start-stack.sh` | Menjalankan Docker Compose Kafka + Hadoop. |
| `stop-stack.sh` | Menghentikan stack; opsi `--volumes` untuk reset data HDFS lokal. |
| `init-infra.sh` | Membuat topik Kafka & folder HDFS awal. |
| `sanity-check.sh` | Cek cepat: container, Kafka, HDFS, port. |
| `run-producers.sh` | Menjalankan `producer_api.py` + `producer_rss.py` ke background + log. |
| `run-consumer.sh` | Menjalankan `consumer_to_hdfs.py` ke background + log. |
| `run-dashboard.sh` | Menjalankan Flask `dashboard/app.py` (foreground). |
| `run-all.sh` | Alur: stack → tunggu → init → producer → consumer → dashboard. |
| `stop-pipeline.sh` | Menghentikan proses Python producer/consumer (bukan Docker). |
| `install-docker-wsl.sh` | Bantuan instalasi Docker di WSL (opsional). |

---

## Kafka — kode & data (`kafka/`)

| File | Tujuan |
|------|--------|
| `producer_api.py` | Membaca **AQICN** (atau **simulator** bila token kosong/gagal), mengirim event JSON ke topik **`airquality-api`**, kunci = slug kota, interval default 15 menit. |
| `producer_rss.py` | Membaca **RSS** (URL dari `RSS_FEEDS`), filter keyword, deduplikasi, mengirim ke topik **`airquality-rss`**, kunci = hash URL, interval default 5 menit. |
| `consumer_to_hdfs.py` | Dua *thread* consumer (satu per topik), **buffer** lalu **flush** ke HDFS; mirror ke `dashboard/data/live_*.json`; opsi `HDFS_WRITE_MODE=docker_exec` untuk WSL2. |
| `seen_ids.json` | Menyimpan ID artikel RSS yang sudah pernah dikirim (dedup). **Dibuat saat runtime**, biasanya di `.gitignore`. |

### Topik Kafka (nama bawaan)

| Topik | Isi | Producer | Consumer (group) |
|-------|-----|----------|-------------------|
| `airquality-api` | Event AQI per kota | `producer_api.py` | `consumer_to_hdfs.py` (group dari `CONSUMER_GROUP_API`) |
| `airquality-rss` | Item berita | `producer_rss.py` | `consumer_to_hdfs.py` (group dari `CONSUMER_GROUP_RSS`) |

Nama topik & group bisa di-override lewat **`.env`**.

---

## HDFS — path logis (di cluster)

Lokasi default dasar: **`/data/airquality`** (diset lewat `HDFS_BASE_DIR` di `.env`).

| Path HDFS | Isi | Ditulis oleh | Dibaca oleh |
|-----------|-----|--------------|-------------|
| `/data/airquality/api/` | File **JSONL** (satu file per flush) berisi batch event **API** | `consumer_to_hdfs.py` | `spark/analysis.ipynb` |
| `/data/airquality/rss/` | File **JSONL** per flush berisi batch **RSS** | `consumer_to_hdfs.py` | (opsional analisis) Spark / notebook |
| `/data/airquality/hasil/` | Keluaran **Parquet** (Spark): distribusi, rata-rata per jam, ranking | `analysis.ipynb` | Verifikasi / job lain |

**Akses dari host**

- **RPC:** `hdfs://localhost:9000` (default `HDFS_NAMENODE_RPC`).
- **Web UI NameNode:** `http://localhost:9870` — jelajah file & cek replikasi.
- **WebHDFS:** `http://localhost:9870` — dipakai kode Python `hdfs` untuk list/mkdir; tulis isi file besar sering lewat **`docker exec namenode hdfs dfs -put`** agar aman di WSL2.

**Container yang relevan:** nama service/`container_name` sering **`namenode`** — dipakai perintah `docker exec` di consumer & notebook bila perlu.

---

## Spark (`spark/`)

| File | Tujuan |
|------|--------|
| `analysis.ipynb` | Baca data historis API dari HDFS (native + **fallback** `docker exec` / lokal jika WSL2), **3 analisis wajib** (DataFrame + Spark SQL), simpan Parquet ke `.../hasil/`, ringkasan JSON ke `dashboard/data/spark_results.json`. |

---

## Dashboard (`dashboard/`)

| Path | Tujuan |
|------|--------|
| `app.py` | Aplikasi Flask: `/`, `/api/data`, normalisasi data, flag demo, render template. |
| `templates/index.html` | UI: panel Spark, chart, tabel AQI, RSS, tema gelap/terang, auto-refresh. |
| `static/style.css` | Gaya tampilan (tema tegas, variabel light/dark). |
| `data/.gitkeep` | Menjaga folder `data/` di Git tanpa men-commit JSON isi. |
| `data/live_api.json` | **Mirror** consumer — kota & AQI terbaru (dibuat saat consumer flush). |
| `data/live_rss.json` | **Mirror** consumer — daftar berita (hingga 50 item). |
| `data/spark_results.json` | **Output notebook** — struktur 3 analisis untuk grafik & tabel historis. |

**Catatan:** File di `data/*.json` (selain `.gitkeep`) sering di-ignore Git — isi berasal dari **pipeline** atau **notebook**, bukan template statis.

---

## Log & runtime lokal

| Lokasi | Tujuan |
|--------|--------|
| `logs/producer_api.log` | Stdout/stderr `producer_api.py` jika dijalankan lewat skrip `nohup`. |
| `logs/producer_rss.log` | Idem untuk `producer_rss.py`. |
| `logs/consumer.log` | Idem untuk `consumer_to_hdfs.py` (termasuk baris `FLUSH` ke HDFS). |
| `.venv/` | Virtual environment Python — **jangan di-commit** (lihat `.gitignore`). |

---

## Ringkasan alur data (file vs cluster)

```
AQICN / RSS  →  producers  →  Kafka topics  →  consumer  →  HDFS /data/airquality/{api,rss}/
                                   ↓
                            mirror JSON  →  dashboard/data/live_*.json  →  Flask
     
HDFS {api}  →  Spark notebook  →  HDFS hasil/ + dashboard/data/spark_results.json  →  Flask
```

---

## Cepat: variabel `.env` yang memengaruhi “alamat”

| Variabel (contoh) | Efek |
|-------------------|------|
| `KAFKA_BOOTSTRAP` | Alamat broker (biasanya `localhost:9092`). |
| `KAFKA_TOPIC_API` / `KAFKA_TOPIC_RSS` | Nama topik. |
| `HDFS_NAMENODE_URL` / `HDFS_NAMENODE_RPC` | Web UI + URI HDFS untuk client. |
| `HDFS_BASE_DIR` | Akar folder proyek di HDFS (default `/data/airquality`). |
| `HDFS_NAMENODE_CONTAINER` | Nama container untuk `docker exec` (default `namenode`). |
| `HDFS_WRITE_MODE` | `docker_exec` (disarankan WSL) vs `webhdfs`. |
| `BUFFER_FLUSH_SEC` / `BUFFER_MAX_RECORDS` | Seberapa sering file baru di HDFS + mirror. |
| `RSS_FEEDS` / `RSS_KEYWORDS` | Sumber & filter berita. |
| `PORT` | Port dashboard Flask. |

---

*Dokumen ini sejajar dengan layout repositori `Kelompok-6-ets-bigdata` terkini. Jika file dipindah, perbarui tabel di atas.*
