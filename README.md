# AirQuality Alert: Monitoring Jawa Timur

**ETS Big Data & Data Lakehouse — Kelompok 6**

Pipeline data end-to-end yang mengintegrasikan **Apache Kafka**, **Hadoop HDFS**, dan **Apache Spark** untuk memantau kualitas udara di kawasan Gerbangkertasusila (Surabaya, Sidoarjo, Gresik, Mojokerto, Malang) secara real-time, lengkap dengan dashboard monitoring berbasis Flask.

**Skrip presentasi & demonstrasi (materi digabung dari README + arsitektur + peta alamat; bilingual: teknis lalu ringkasan eksekutif):** [`README-PRESENTASI-DEMO.md`](./README-PRESENTASI-DEMO.md)

---

## Anggota Kelompok

| Nama | NRP | Kontribusi |
|---|---|---|
| Hansen Chang | 5027241028 | _diisi sesuai pembagian tim_ |
| Ahmad Ibnu Athaillah | 5027241024 | _diisi sesuai pembagian tim_ |
| Naila Raniyah Hanan | 5027241078 | _diisi sesuai pembagian tim_ |
| Diva Aulia Rosa | 5027241003 | _diisi sesuai pembagian tim_ |
| Ahmad Rabbani Fata | 5027241046 | _diisi sesuai pembagian tim_ |

---

## Topik & Justifikasi

Topik yang diangkat dalam proyek ini adalah **sistem pemantauan kualitas udara dan peringatan dini berbasis data real-time** untuk wilayah Jawa Timur. Pemilihan topik ini didasari oleh urgensi masalah polusi udara di kawasan padat penduduk dan industri seperti Surabaya, Sidoarjo, dan Gresik yang berdampak langsung pada kesehatan masyarakat. Hal yang membuat proyek ini menarik adalah penggabungan **data kuantitatif** dari API kualitas udara dengan **data kualitatif** dari berita RSS, sehingga sistem tidak hanya menyajikan angka tetapi juga memberikan konteks peristiwa di lapangan. Dengan mengimplementasikan arsitektur Data Lakehouse menggunakan Kafka, HDFS, dan Spark, proyek ini mendemonstrasikan bagaimana teknologi Big Data dapat memberikan solusi edukatif bagi masyarakat untuk menghindari paparan polusi pada jam-jam puncak berdasarkan hasil analisis historis.

**Pertanyaan bisnis:** _"Pada jam berapa kualitas udara paling buruk, dan apakah berita lingkungan mencerminkan kondisi tersebut?"_

---

## Arsitektur Sistem

```
                    ┌─────────────────┐    ┌─────────────────────────────┐
                    │ AQICN /         │    │  RSS (Detik, Tempo, dll.)   │
                    │  Simulator      │    │  — filter keyword lingkungan│
                    └────────┬────────┘    └──────────────┬──────────────┘
                             │ poll 15 mnt                 │ poll 5 mnt
                             ▼                             ▼
                    ┌─────────────────┐    ┌─────────────────┐
                    │  producer_api.py│    │  producer_rss.py│
                    └────────┬────────┘    └────────┬────────┘
                             │                      │
                             ▼                      ▼
                  ┌──────────────────────────────────────────┐
                  │              Apache Kafka                 │
                  │  topic: airquality-api                    │
                  │  topic: airquality-rss                    │
                  └────────────────────┬─────────────────────┘
                                       │
                                       ▼
                            ┌──────────────────────┐
                            │ consumer_to_hdfs.py  │  threading 2 topic
                            └──────────┬───────────┘  + buffer + mirror
                                       │
                                       ▼
                  ┌──────────────────────────────────────────┐
                  │              Hadoop HDFS (replikasi 2)     │
                  │  /data/airquality/api/                     │
                  │  /data/airquality/rss/                    │
                  │  /data/airquality/hasil/  ← output Spark  │
                  └────────────────────┬───────────────────────┘
                                       │
                                       ▼
                            ┌──────────────────────┐
                            │   Apache Spark        │  3 analisis wajib
                            │   analysis.ipynb     │  + Spark SQL
                            └──────────┬───────────┘
                                       │
                                       ▼
                            ┌──────────────────────┐
                            │   Flask Dashboard    │  http://localhost:5000
                            │   Chart.js, AQI 4   │  auto-refresh 30 s
                            └──────────────────────┘
```

---

## Panduan demonstrasi (ETS)

Dokumentasi ini dirancang agar dosen/audience bisa mengikuti alur **Kafka → HDFS → Spark → Dashboard** dalam satu sesi demo (~20–30 menit, atau dipersingkat dengan konfigurasi di bawah).

### Ringkasan alur demonstrasi

| Urutan | Komponen | Yang ditunjukkan |
|--------|----------|------------------|
| 1 | Docker | Stack Hadoop (1 NameNode, 3 DataNode, YARN) + Zookeeper + Kafka jalan |
| 2 | Producer API | Pesan JSON AQI 5 kota ke topic `airquality-api` |
| 3 | Producer RSS | Berita ke topic `airquality-rss` (dedup, key hash URL) |
| 4 | Consumer | Buffer → flush ke HDFS + mirror `dashboard/data/live_*.json` |
| 5 | HDFS | File `.json` di `/data/airquality/api/` dan `/.../rss/` |
| 6 | Spark | Notebook: 3 analisis → `spark_results.json` + parquet di `hasil/` |
| 7 | Dashboard | Panel live AQI, berita, grafik + tabel hasil Spark |

### Checklist sebelum demo

- [ ] `docker` dan `docker compose` bisa dijalankan; user login ada di grup `docker` (lihat *Troubleshooting* jika `permission denied` ke socket).
- [ ] Python 3.9+ + venv: `python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt`
- [ ] File `.env` sudah disalin dari `.env.example` dan `AQICN_TOKEN` diisi (opsional; tanpa token pakai simulator).
- [ ] Port bebas: `5000` (Flask), `9092` (Kafka), `9870/9000/8088` (Hadoop).

### Opsi A — Satu perintah (stack + init + pipeline + dashboard)

Dari root repo:

```bash
bash scripts/run-all.sh
```

Script ini: menaikkan stack Docker, menunggu layanan, init topic + folder HDFS, menjalankan producer API & RSS, consumer, lalu **dashboard di foreground** di `http://127.0.0.1:5000` (port bisa di-override: `PORT=5001 bash scripts/run-all.sh`).

Di terminal **lain** (untuk verifikasi saat juri bertanya):

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'
docker exec namenode hdfs dfs -ls -R /data/airquality/ | head -40
tail -f logs/consumer.log
```

Stop pipeline (process Python, stack tetap jalan): `bash scripts/stop-pipeline.sh`  
Stop stack: `bash scripts/stop-stack.sh` (tambah `--volumes` untuk reset data HDFS lokal)

### Opsi B — Step-by-step (cocok untuk penjelasan di depan kelas)

1. **Infrastruktur**

   ```bash
   bash scripts/start-stack.sh
   # tunggu ~30–60 detik
   bash scripts/init-infra.sh
   bash scripts/sanity-check.sh
   ```

2. **Pipeline (background)**

   ```bash
   bash scripts/run-producers.sh
   bash scripts/run-consumer.sh
   ```

3. **Pantau log (opsional)**

   ```bash
   tail -f logs/producer_api.log
   # terminal lain: tail -f logs/producer_rss.log
   # terminal lain: tail -f logs/consumer.log
   ```

4. **Verifikasi HDFS** — pastikan muncul baris `FLUSH` di `consumer.log` dan file di HDFS:

   ```bash
   docker exec namenode hdfs dfs -ls /data/airquality/api/
   docker exec namenode hdfs dfs -ls /data/airquality/rss/
   ```

5. **Dashboard**

   ```bash
   bash scripts/run-dashboard.sh
   ```

   Buka browser: [http://127.0.0.1:5000](http://127.0.0.1:5000)

6. **Spark (setelah data cukup di HDFS, minimal beberapa flush)**

   Buka `spark/analysis.ipynb` di Jupyter, **Run All**, atau eksekusi headless (lihat *Spark di WSL2/Linux* di bawah).

### Konfigurasi `.env` untuk demo lebih cepat

Untuk ujian/demo singkat, perkecil interval buffer consumer agar file mirror dan HDFS terisi tanpa menunggu 3 menit:

```bash
# Consumer: flush tiap 10 detik (atau setelah cukup record)
BUFFER_FLUSH_SEC=10
BUFFER_MAX_RECORDS=200
```

Pastikan hanya **satu** baris `BUFFER_FLUSH_SEC` aktif (hindari duplikat di file).

**RSS — paste ke `.env` (4 feed: 2 sumber penuh + 2 cadangan rubrik):**

```bash
RSS_FEEDS=https://news.detik.com/rss,https://rss.tempo.co/nasional,https://rss.tempo.co/tag/polusi,https://rss.kompas.com/feed/kompas.com/sains/environment
RSS_KEYWORDS=polusi,udara,lingkungan,aqi,emisi,asap,kabut,pencemaran,iklim,cuaca,pm2.5,pm10,karhutla,hutan,limbah,sampah,banjir,asma,ispa
RSS_FALLBACK_TOPN=5
```

> Catatan: feed rubrik lama (mis. Tempo `/tag/polusi`) sering 0 entri; Detik + Tempo nasional memastikan data masuk. Setelah edit `.env`, restart producer RSS: `pkill -f kafka/producer_rss.py` lalu `bash scripts/run-producers.sh`.

### Verifikasi cepat: pipeline “hidup”

- **Log consumer** mengandung `FLUSH` untuk API dan RSS.
- **File lokal** (mirror untuk dashboard):
  - `dashboard/data/live_api.json` — 5 baris kota terakhir
  - `dashboard/data/live_rss.json` — daftar berita
- **API dashboard:** `curl -s http://127.0.0.1:5000/api/data | python3 -m json.tool` — cek `api.is_demo` dan `rss.is_demo` jadi `false` setelah data ada; `spark._demo` menjadi `false` setelah Spark menulis `spark_results.json`.

### Apa yang ditampilkan di layar (untuk juri)

1. **HDFS Web UI** — [http://localhost:9870](http://localhost:9870) → Browse Directory → `/data/airquality/`
2. **YARN** — [http://localhost:8088](http://localhost:8088) (jika job Spark di-submit ke cluster; notebook lokal sering hanya `local[*]`)
3. **Terminal** — `docker ps` menunjuk **8 container** (6 Hadoop + Zookeeper + Kafka) sesuai compose
4. **Dashboard** — legenda 4 warna AQI, tabel live, berita, chart dari Spark
5. **Jupyter/Notebook** — tiga blok analisis + interpretasi

### Screenshot (disarankan)

| Screenshot | Kapan diambil |
|------------|----------------|
| HDFS: isi folder `/data/airquality/api` dan `rss` | Setelah `FLUSH` terlihat di log |
| `docker ps` 8 service | Saat semua *healthy* / running |
| Dashboard penuh | Setelah `live_*.json` + `spark_results.json` terisi |
| Satu cell output Spark (analisis 1 atau 2) | Setelah Run All `analysis.ipynb` |
| (Opsional) Kafka: consume sekali | `docker exec -it kafka-broker kafka-console-consumer ...` |

Ganti tabel *TODO* lama jika semua gambar sudah disisipkan ke repo (`docs/screenshots/` disarankan).

---

## Prasyarat Sistem

| Tools | Catatan | Cek |
|-------|---------|-----|
| Docker Engine | 20+ | `docker --version` |
| Docker Compose | v2+ | `docker compose version` |
| Python | 3.9+ (3.12 OK) | `python3 --version` |
| Java (JDK) | Untuk PySpark, biasanya 8–21; **Spark 3.5 + Java 17/21** sering butuh flag `--add-opens` (lihat notebook / eksekusi headless) | `java -version` |
| Git | 2.x | `git --version` |

> **WSL2/Linux — Docker belum terpasang:** `bash scripts/install-docker-wsl.sh`  
> **User harus grup `docker`:** setelah `sudo usermod -aG docker $USER`, **logout/login** atau `newgrp docker` agar `docker ps` jalan tanpa `sudo`.

---

## Cara menjalankan (referensi teknis)

### Clone & setup Python

```bash
git clone https://github.com/mamettdd/Kelompok-6-ets-bigdata.git
cd Kelompok-6-ets-bigdata

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

### Stack & inisialisasi

```bash
bash scripts/start-stack.sh
# tunggu layanan ready
bash scripts/init-infra.sh
bash scripts/sanity-check.sh
```

### Konfigurasi

```bash
cp .env.example .env
# Edit .env: AQICN_TOKEN=... (opsional)
```

### Producer & consumer (manual)

```bash
# Helper (background + log):
bash scripts/run-producers.sh
bash scripts/run-consumer.sh

# Atau manual per proses:
python kafka/producer_api.py
python kafka/producer_rss.py
python kafka/consumer_to_hdfs.py
```

### Spark (`analysis.ipynb`)

- Baca data dari HDFS; di **WSL2** jika baca DataNode dari host bermasalah, notebook memakai **fallback** (list WebHDFS + `docker exec namenode hdfs dfs -cat` / strategi setara) sehingga data tetap dari cluster.
- **SPARK_HOME:** pakai PySpark bawaan venv, misalnya:
  - `export SPARK_HOME="$PWD/.venv/lib/python3.12/site-packages/pyspark"`
- **Akses Docker** dari proses yang memanggil `docker exec` harus sama seperti user yang bisa `docker ps` (grup `docker`).
- Setelah *Run All*, cek:
  - `dashboard/data/spark_results.json`
  - `hdfs:///data/airquality/hasil/*` (parquet)

Contoh eksekusi headless (setelah set `JAVA_HOME`, `SPARK_HOME`, dan flag `--add-opens` seperti di variabel `PYSPARK_SUBMIT_ARGS` pada sesi interaktif):

```bash
# Pastikan: source .venv/bin/activate, grup docker aktif, lalu:
jupyter nbconvert --to notebook --execute spark/analysis.ipynb --output analysis.ipynb
```

### Dashboard

```bash
bash scripts/run-dashboard.sh
# http://127.0.0.1:5000/   |   API: /api/data
# Paksa data contoh:       /api/data?demo=1
```

### Mematikan stack

```bash
bash scripts/stop-pipeline.sh   # hentikan proses Python pipeline
bash scripts/stop-stack.sh      # hentikan container
# Reset volume HDFS lokal:
bash scripts/stop-stack.sh --volumes
```

---

## Web UI

| Layanan | URL |
|---------|-----|
| HDFS NameNode | [http://localhost:9870](http://localhost:9870) |
| DataNode (1–3) | [http://localhost:9864](http://localhost:9864) · [9865](http://localhost:9865) · [9866](http://localhost:9866) |
| YARN ResourceManager | [http://localhost:8088](http://localhost:8088) |
| Kafka | `localhost:9092` |

---

## Struktur Repository

```
Kelompok-6-ets-bigdata/
├── README.md
├── CHECKLIST.md
├── requirements.txt
├── docker-compose-hadoop.yml
├── docker-compose-kafka.yml
├── hadoop.env
├── .env.example
│
├── scripts/
│   ├── install-docker-wsl.sh
│   ├── start-stack.sh
│   ├── stop-stack.sh
│   ├── init-infra.sh
│   ├── sanity-check.sh
│   ├── run-producers.sh
│   ├── run-consumer.sh
│   ├── run-dashboard.sh
│   ├── run-all.sh
│   └── stop-pipeline.sh
│
├── kafka/
│   ├── producer_api.py
│   ├── producer_rss.py
│   └── consumer_to_hdfs.py
│
├── spark/
│   └── analysis.ipynb
│
└── dashboard/
    ├── app.py
    ├── templates/index.html
    ├── static/style.css
    └── data/                    # live_api.json, live_rss.json, spark_results.json
```

---

## Troubleshooting (umum saat demonstrasi)

| Gejala | Penyebab umum | Tindakan |
|--------|----------------|----------|
| `permission denied` ke `/var/run/docker.sock` | User belum di grup `docker` atau session lama | `newgrp docker` atau logout/login; `groups` harus memuat `docker` |
| Consumer tidak menulis; error WebHDFS ke hostname aneh (container id) | Host tidak resolve nama DataNode (WSL2) | Pastikan `HDFS_WRITE_MODE=docker_exec` dan `HDFS_NAMENODE_CONTAINER=namenode` (default) |
| `ModuleNotFoundError: kafka.vendor.six.moves` | `kafka-python` lama di Python 3.12 | Pakai `kafka-python-ng` (sudah di `requirements.txt`); `pip install -r requirements.txt` ulang |
| Panel RSS kosong / producer RSS 0 entri | URL RSS rubrik deprek / 404 | Gunakan `RSS_FEEDS` dengan Detik + Tempo nasional (lihat bagian demo) |
| Bar info “demo” di dashboard | `spark_results.json` belum ada, atau sisi lain masih contoh | Isi HDFS + jalankan Spark; cek `api.is_demo` / `rss.is_demo` di `/api/data` |
| `FileNotFoundError: spark-submit` | `SPARK_HOME` menunjuk ke `/opt/spark` kosong | Set `SPARK_HOME` ke folder `pyspark` di dalam `.venv` (lihat bagian Spark) |

---

## Status implementasi

| Fase | Komponen | Status |
|------|----------|--------|
| 1 | Infrastruktur Docker (Kafka + Hadoop multi-DataNode, replikasi 2) | Selesai |
| 2 | Producer (AQICN + simulator, RSS + dedup) | Selesai |
| 3 | Consumer 2 topik, buffer, mirror dashboard | Selesai |
| 4 | Spark: 3 analisis + SQL | Selesai |
| 5 | Flask + Chart.js + AQI 4 kategori | Selesai |
| 6 | Dokumentasi demo + refleksi + screenshot | Lengkapi di kelas |

Detail checklist: [`CHECKLIST.md`](./CHECKLIST.md)

---

## Tantangan & solusi (ringkas)

- **WSL2 + HDFS:** client di host sering tidak bisa mengikuti redirect WebHDFS ke DataNode. Solusi: tulis/baca lewat `docker exec` di container NameNode, atau jaringan Docker yang sama.
- **RSS berubah URL:** feed rubrik lama sering 404. Solusi: ganti sumber (Detik root, Tempo nasional) + filter keyword + fallback top-N.
- **Konsistensi Python:** gunakan venv proyek dan `requirements.txt` yang sama di semua mesin demo.

---

## Referensi

- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Hadoop HDFS Design](https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-hdfs/HdfsDesign.html)
- [Apache Spark SQL](https://spark.apache.org/docs/latest/sql-programming-guide.html)
- [AQICN API](https://aqicn.org/api/)
- [bde2020 / big-data-europe Docker Hadoop](https://github.com/big-data-europe/docker-hadoop) (pola serupa)
