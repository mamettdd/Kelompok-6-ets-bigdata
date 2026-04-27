# ✅ Checklist Pengerjaan ETS Big Data — Kelompok 6

> **Topik**: AirQuality Alert: Indeks Kualitas Udara Jawa Timur
> **Deadline**: 2 minggu sejak rilis
> **Total skor**: 100 poin + 10 bonus

---

## 🎯 Cara Pakai Checklist Ini

- Centang `[x]` setiap kali sub-task selesai
- Setiap fase punya **PIC (Person In Charge)** yang bisa dikerjakan paralel
- Lakukan **fase secara berurutan** karena saling bergantung
- Item bertanda 🔥 = **wajib di rubrik**, jangan dilewati
- Item bertanda 🎁 = **bonus** (kerjakan kalau sempat)

---

## 📋 FASE 0 — Persiapan Lingkungan (1 jam, semua anggota)

### Prasyarat Sistem
- [ ] Docker Engine + Docker Compose terpasang (`docker --version && docker compose version`)
- [ ] Python 3.9+ terpasang (`python3 --version`); **3.12** didukung (`kafka-python-ng`)
- [ ] Java JDK **8–21** terpasang untuk PySpark (`java -version`); Spark 3.5 + Java 17/21 biasanya butuh flag `--add-opens` (lihat README / notebook)
- [ ] Git terpasang dan ter-konfigurasi
- [ ] (WSL/Linux) User di grup `docker` agar `docker exec` / stack jalan tanpa `sudo` (`groups` memuat `docker`)

### Setup Repo Lokal
- [ ] Clone repo: `git clone https://github.com/mamettdd/Kelompok-6-ets-bigdata.git`
- [ ] Masuk ke folder: `cd Kelompok-6-ets-bigdata`
- [ ] Buat virtual env: `python3 -m venv .venv`
- [ ] Aktifkan venv: `source .venv/bin/activate`
- [ ] Upgrade pip: `pip install --upgrade pip`
- [ ] Install paket: `pip install -r requirements.txt`
- [ ] Tambahkan `.venv/` ke `.gitignore`

---

## 🐳 FASE 1 — Infrastruktur Docker (1–2 jam, PIC: Anggota 1)

### 1.1 Perbaiki `docker-compose-kafka.yml` 🔥
- [x] Tambah `container_name: kafka-broker` (wajib agar perintah verifikasi soal jalan)
- [x] Ganti `KAFKA_ADVERTISED_HOST_NAME` dengan `KAFKA_LISTENERS` + `KAFKA_ADVERTISED_LISTENERS`
- [x] Hapus volume `/var/run/docker.sock` (tidak diperlukan)
- [x] Tambah `KAFKA_AUTO_CREATE_TOPICS_ENABLE: "false"` (biar topic dibuat manual)

### 1.2 Perbaiki `docker-compose-hadoop.yml` 🔥
- [x] Tambah port DataNode: `9864`, `9865`, `9866` (tiga DataNode)
- [x] Tambah volume persistence untuk namenode & **tiga** datanode
- [x] Tambah `resourcemanager` + `nodemanager` + **3× datanode** (6 container Hadoop + 2 Kafka = 8 container total)
- [x] Set `dfs.replication=2` di `hadoop.env` (tiap block disalin ke 2 DataNode)

### 1.3 Jalankan Stack (eksekusi manual oleh user)
- [x] `bash scripts/start-stack.sh` (menjalankan kedua compose sekaligus)
- [x] Verifikasi semua running: `docker ps` (harus **8** container: namenode, datanode1, datanode2, datanode3, resourcemanager, nodemanager, kafka-broker, zookeeper)
- [x] Buka HDFS Web UI: [http://localhost:9870](http://localhost:9870) ✅
- [x] Buka YARN Web UI: [http://localhost:8088](http://localhost:8088) ✅

### 1.4 Buat Kafka Topic 🔥 (eksekusi manual)
- [x] `bash scripts/init-infra.sh` (auto-buat 2 topic + 3 folder HDFS)
- [x] Verifikasi: `docker exec -it kafka-broker kafka-topics.sh --list --bootstrap-server localhost:9092`

### 1.5 Buat Folder HDFS 🔥 (sudah otomatis di init-infra.sh)
- [x] Sudah handled oleh `scripts/init-infra.sh`
- [x] Verifikasi: `docker exec -it namenode hdfs dfs -ls -R /data/`

---

## 📡 FASE 2 — Producer Kafka (4–6 jam, PIC: Anggota 2 & 3)

### 2.1 Pilih Sumber Data API (Anggota 2)
- [x] Pilih salah satu:
  - [ ] Daftar token AQICN gratis: https://aqicn.org/data-platform/token/ ← **TODO user**
  - [x] Atau **simulator fallback** (otomatis aktif kalau token kosong, sudah dokumented di README)
- [x] Simpan token di `.env` (jangan commit!) — file `.env.example` sudah disediakan
- [x] Tambahkan `.env` ke `.gitignore`

### 2.2 Rombak `kafka/producer_api.py` 🔥 (Anggota 2)
- [x] Pakai **`kafka-python-ng`** (kompatibel Python 3.12); *bukan* `enable_idempotence` (hanya client Java) — gunakan setara: `acks="all"`, `retries` tinggi, `max_in_flight_requests_per_connection=1`
- [x] Tambah `key_serializer` + `value_serializer` (JSON UTF-8)
- [x] Kirim dengan key: `producer.send(topic, key=city_slug, value=data)`
- [x] Tambah kota **Mojokerto** (total 5 kota)
- [x] Tambah field `timestamp_ingest` (UTC ISO format)
- [x] Skema field konsisten: `{city, aqi, pm25, pm10, dominent_pollutant, timestamp_ingest, ...}`
- [x] Tambah `producer.flush()` di akhir loop
- [x] Interval polling 15 menit (`POLL_INTERVAL_SEC=900`)
- [ ] Test jalan tanpa error minimal 30 menit ← **eksekusi user**

### 2.3 Rombak `kafka/producer_rss.py` 🔥 (Anggota 3)
- [x] Sama seperti API: `acks="all"` + retry + `max_in_flight=1` (tanpa `enable_idempotence`)
- [x] Tambah `key_serializer` / `value_serializer`
- [x] Implementasi **dedup**: simpan set `seen_ids` ke `kafka/seen_ids.json` (atomic write)
- [x] Hash URL untuk key: `hashlib.md5(entry.link.encode()).hexdigest()`
- [x] Tambah field `timestamp_ingest`
- [x] Ubah interval ke **5 menit** (`POLL_INTERVAL_SEC_RSS=300`)
- [x] **Feed RSS**: default mencakup sumber yang hidup (mis. Detik root, Tempo nasional) + cadangan rubrik; `RSS_FEEDS` / `RSS_KEYWORDS` / `RSS_FALLBACK_TOPN` di `.env` (lihat README)
- [x] `feedparser` + **User-Agent**; filter keyword lingkungan + fallback top-N jika filter kosong
- [ ] Test: jalankan 2 kali, pastikan tidak ada duplikat di topic ← **eksekusi user**

### 2.4 Verifikasi Producer
- [ ] Jalankan kedua producer: `bash scripts/run-producers.sh`
- [ ] Cek event masuk dengan console consumer:
  ```bash
  docker exec -it kafka-broker kafka-console-consumer.sh \
    --topic airquality-api --from-beginning --bootstrap-server localhost:9092
  ```
- [ ] Screenshot output console consumer untuk README

---

## 💾 FASE 3 — Consumer ke HDFS (3–4 jam, PIC: Anggota 3)

### 3.1 Rombak `kafka/consumer_to_hdfs.py` 🔥
- [x] Tambah `group_id` per topic (`CONSUMER_GROUP_API` / `CONSUMER_GROUP_RSS` di `.env`)
- [x] Implementasi **buffering** per topic (`BUFFER_FLUSH_SEC` / `BUFFER_MAX_RECORDS`, default rubrik ~3 menit / 200 record)
- [x] Implementasi **threading** untuk 2 topic paralel
- [x] Format nama file timestamp: `2026-04-27_14-30-00.json` (UTC)
- [x] **Tulis HDFS**: default `HDFS_WRITE_MODE=docker_exec` (`docker exec namenode hdfs dfs -put`) — **WSL2-friendly** (hindari redirect WebHDFS ke hostname DataNode di host)
- [x] Library `hdfs` (`InsecureClient`) untuk **mkdir / list** (NameNode) → bonus +2 🎁
- [x] **Mirror ke dashboard**:
  - [x] `dashboard/data/live_api.json` — `{updated_at, cities[]}` (terbaru per kota)
  - [x] `dashboard/data/live_rss.json` — `{updated_at, items[]}` (hingga 50 item)

### 3.2 Verifikasi
- [ ] Jalankan consumer + 2 producer bersamaan: `bash scripts/run-all.sh`
- [ ] Cek file di HDFS: `docker exec -it namenode hdfs dfs -ls -R /data/airquality/`
- [ ] Cek isi salah satu file: `docker exec -it namenode hdfs dfs -cat /data/airquality/api/<file>.json`
- [ ] Cek file dashboard local: `cat dashboard/data/live_api.json | jq .`
- [ ] Verifikasi consumer group:
  ```bash
  docker exec -it kafka-broker kafka-consumer-groups.sh \
    --bootstrap-server localhost:9092 --describe --group airquality-consumer-api
  ```
- [ ] **Screenshot** HDFS Web UI dengan file yang muncul → simpan ke `docs/screenshots/`

---

## 🔬 FASE 4 — Spark Analysis (4–6 jam, PIC: Anggota 4)

### 4.1 Persiapan
- [ ] Pastikan data sudah terkumpul **minimal 1–2 cycle producer** (≥10 event API) ← **eksekusi user**
- [x] Buka `spark/analysis.ipynb` di Jupyter / VS Code

### 4.2 Cell — Init Spark Session 🔥
- [x] Konfigurasi `spark.hadoop.fs.defaultFS` ke `hdfs://localhost:9000`
- [x] AppName: `AirQualityAnalysis`
- [x] Timezone Asia/Jakarta + `dfs.client.use.datanode.hostname=true`

### 4.3 Cell — Load Data dari HDFS 🔥
- [x] Baca dari `hdfs://localhost:9000/data/airquality/api/*.json` (native Spark dulu)
- [x] **Fallback** jika native/read WebHDFS gagal (umum **WSL2**): list via WebHDFS + unduh isi file lewat `docker exec namenode hdfs dfs -cat` → Spark baca lokal
- [x] `df.printSchema()` & `df.show(5)`
- [x] `createOrReplaceTempView("airquality")`

### 4.4 Cell — Analisis 1: Distribusi Kategori AQI per Kota 🔥
- [x] Klasifikasi 4 level: Baik (0–50), Sedang (51–100), Tidak Sehat (101–150), Berbahaya (>150)
- [x] Hitung **persentase per kota** (DataFrame API + Window function)
- [x] Pivot menjadi 4 kolom (`baik_pct, sedang_pct, tidak_sehat_pct, berbahaya_pct`)
- [x] **Markdown cell**: narasi interpretasi bisnis

### 4.5 Cell — Analisis 2: Rata-rata AQI per Kota per Jam 🔥
- [x] Pakai **Spark SQL** murni (`spark.sql(...)` dengan `GROUP BY city, hour`)
- [x] Plus query Window Function untuk top-3 jam puncak per kota
- [x] **Markdown cell**: narasi (jam berapa terburuk?)

### 4.6 Cell — Analisis 3: Ranking Kota Terburuk 🔥
- [x] Group by kota, hitung rata-rata AQI (Spark SQL)
- [x] Tambah kolom `unhealthy_or_worse_events` (CASE WHEN aqi > 100)
- [x] Order by rata-rata AQI desc
- [x] **Markdown cell**: narasi interpretasi

### 4.7 (opsional) Cross-check dengan RSS — boleh ditambah saat refleksi
- [ ] Hitung jumlah berita yang mengandung kata "polusi" / "udara"
- [ ] Korelasikan dengan periode AQI buruk

### 4.8 Cell — Bonus MLlib 🎁 (+5 poin) — opsional, belum diimplement
- [ ] K-Means clustering kota berdasarkan pola AQI per jam
- [ ] Atau Linear Regression prediksi AQI besok

### 4.9 Cell — Simpan Hasil ke HDFS 🔥
- [x] `df_dist_pivot` → `hdfs:///data/airquality/hasil/distribusi_kategori`
- [x] `df_avg_hour`  → `hdfs:///data/airquality/hasil/avg_aqi_per_jam`
- [x] `df_rank`      → `hdfs:///data/airquality/hasil/ranking_kota`
- [x] Jika **native Parquet ke HDFS gagal**: fallback tulis lokal lalu `docker cp` + `hdfs dfs -put` (selaras strategi consumer)
- [ ] Verifikasi: `docker exec -it namenode hdfs dfs -ls -R /data/airquality/hasil/` ← **eksekusi user**

### 4.10 Cell — Simpan Ringkasan untuk Dashboard 🔥
- [x] Konversi ke struktur `{generated_at, analysis1, analysis2, analysis3}` (kompatibel dengan dashboard)
- [x] Simpan atomic ke `dashboard/data/spark_results.json`

---

## 📺 FASE 5 — Dashboard (3–4 jam, PIC: Anggota 5)

### 5.1 Rombak `dashboard/app.py` 🔥
- [x] Endpoint `/api/data` + alias `/api/status`
- [x] Return JSON terstruktur untuk 3 panel (`spark`, `api`, `rss`)
- [x] Error handling jika file tidak ada (fallback demo data + flag `is_demo` / `_demo`)
- [x] Normalisasi format lama vs baru (legacy ranking → struktur baru)
- [x] Context template: `body_class` untuk tema UI (mis. `dashboard dashboard--sharp`)

### 5.2 Rombak `dashboard/templates/index.html` 🔥
- [x] Title `"Kelompok 6"` (via variabel `kelompok`)
- [x] **Tema gelap / terang**: `data-theme` + `localStorage` + tombol di header; skrip di `<head>` mengurangi flash
- [x] **Bar status** demo / parsial (hanya jika relevan; tidak selalu “full demo”)
- [x] **Panel 1**: Tabel AQI per kota dengan **4 indikator warna**:
  - [x] 🟢 Hijau untuk Baik (0–50)
  - [x] 🟡 Kuning untuk Sedang (51–100)
  - [x] 🟠 Oranye untuk Tidak Sehat (101–150)
  - [x] 🔴 Merah untuk Berbahaya (>150)
- [x] **Panel 2**: Hasil 3 analisis Spark (tabel + chart)
- [x] **Panel 3**: List berita RSS terbaru
- [x] Auto-refresh: `setInterval(fetchData, 30000)`; Chart.js **borderRadius: 0** + warna mengikuti tema

### 5.2b Gaya `dashboard/static/style.css`
- [x] Sudut **0px** (tampilan tegas / profesional)
- [x] Variabel CSS untuk **light & dark** (`html[data-theme="light|dark"]`)

### 5.3 Bonus Chart.js 🎁 (+3 poin)
- [x] Tambah CDN Chart.js
- [x] Buat bar chart rata-rata AQI per jam puncak (analysis2)

### 5.4 Test
- [x] `python dashboard/app.py` jalan di port 5000
- [x] http://localhost:5000 bisa dibuka
- [ ] Verifikasi 3 panel tampil **data nyata** (perlu producer+consumer+spark berjalan ≥1 cycle) ← **eksekusi user**
- [x] Auto-refresh tiap 30s (Network tab DevTools)
- [ ] **Screenshot** dashboard untuk README ← **eksekusi user**

---

## 📝 FASE 6 — README & Finalisasi (3–4 jam, semua anggota)

### 6.1 Rombak `README.md` 🔥
- [x] **Header**: Judul + ringkasan proyek
- [ ] **Anggota Kelompok**: tabel — isi kolom **kontribusi spesifik** per orang
- [x] **Topik & justifikasi**
- [x] **Diagram arsitektur** (ASCII di README; opsional: gambar draw.io tambahan)
- [x] **Prasyarat sistem** (Docker, Python, Java, catatan WSL/docker group)
- [x] **Panduan demonstrasi** + cara menjalankan step-by-step (`run-all.sh`, skrip `scripts/`, `.env`, RSS, buffer demo)
- [x] **Troubleshooting** (Kafka, HDFS WSL2, SPARK_HOME, tema, dll.)
- [ ] **Screenshot wajib** (isi repo, mis. `docs/screenshots/`):
  - [ ] HDFS Web UI — file di `/data/airquality/`
  - [ ] Kafka console consumer (opsional)
  - [ ] Dashboard berjalan (+opsional dark mode)
- [x] **Tantangan & solusi** (ringkas; bisa dilengkapi refleksi tim)
- [ ] **Lisensi & credit** (jika rubrik meminta)

### 6.1b Dokumentasi `architecture.md`
- [x] File **`architecture.md`**: arsitektur, alur, cara kerja — **lapisan teknis** + **lapisan eksekutif**
- [ ] (Opsional) Tambahkan link dari README ke `architecture.md` jika belum

### 6.2 Konsolidasi
- [ ] Rapikan / hapus `ibnu-Readme-dulu.md` jika masih ada dan sudah tidak dipakai
- [x] `.gitignore`: `.venv/`, `.env`, `dashboard/data/*.json` (kecuali `.gitkeep`), `kafka/seen_ids.json`, `logs/`, dll.
- [ ] Cek tidak ada **credentials** ter-commit (token AQICN di `.env` hanya lokal)

### 6.3 Test End-to-End Final 🔥
- [ ] Matikan semua container: `docker compose down`
- [ ] Hapus venv: `rm -rf .venv`
- [ ] Jalankan ulang dari nol mengikuti instruksi di README **kamu sendiri**
- [ ] Pastikan semua step bisa dijalankan tanpa error

### 6.4 Persiapan Demo (10 menit)
- [ ] Siapkan slide pengantar (1 menit)
- [ ] Demo flow:
  1. Tampilkan repo GitHub
  2. Tunjukkan Docker container running
  3. Tunjukkan event masuk Kafka via console consumer
  4. Tunjukkan file di HDFS Web UI
  5. Tunjukkan notebook Spark dengan 3 analisis & narasi
  6. Tunjukkan dashboard auto-refresh
- [ ] Latihan demo minimal 2x agar pas 7 menit
- [ ] Siapkan jawaban untuk pertanyaan umum:
  - "Kenapa pakai Kafka, bukan langsung tulis ke HDFS?"
  - "Bagaimana kalau producer crash, data hilang?"
  - "Bagaimana skala kalau 100 kota?"

### 6.5 Submission
- [ ] `git add .`
- [ ] `git commit -m "feat: complete pipeline implementation"`
- [ ] `git push origin main`
- [ ] Pastikan repo public di GitHub
- [ ] Submit link repo ke LMS **sebelum deadline**

---

## 🏁 Checklist Final Sebelum Demo

### Kafka 🔥
- [ ] `docker compose` (Kafka) berjalan — `kafka-broker` aktif
- [ ] `kafka-topics.sh --list` menampilkan 2 topic
- [ ] `producer_api.py` berjalan dan output terlihat
- [ ] `producer_rss.py` berjalan dan output terlihat
- [ ] `consumer_to_hdfs.py` berjalan
- [ ] `kafka-consumer-groups.sh --describe` menampilkan group + LAG

### HDFS 🔥
- [ ] `docker compose` (Hadoop) berjalan
- [ ] `hdfs dfs -ls /data/airquality/api/` menampilkan file JSON
- [ ] `hdfs dfs -ls /data/airquality/rss/` menampilkan file JSON
- [ ] Screenshot HDFS Web UI ada di README

### Spark 🔥
- [ ] Analisis 1 (kategori AQI) jalan tanpa error dari HDFS
- [ ] Analisis 2 (Spark SQL per jam) jalan
- [ ] Analisis 3 (ranking kota) jalan
- [ ] `hdfs dfs -ls /data/airquality/hasil/` menampilkan output Spark
- [ ] `dashboard/data/spark_results.json` ada dan berisi 3 hasil

### Dashboard 🔥
- [ ] `bash scripts/run-dashboard.sh` atau `python dashboard/app.py` berjalan
- [ ] http://localhost:5000 bisa dibuka
- [ ] Panel data Spark menampilkan data nyata (`spark_results.json` dari notebook)
- [ ] Panel data live menampilkan event terbaru (`live_api.json`)
- [ ] Panel berita menampilkan artikel terbaru (`live_rss.json`)
- [ ] Auto-refresh terbukti (Network tab ~30s)
- [ ] (Opsional) Tema gelap/terang & preferensi tersimpan (`localStorage`)

### Repository 🔥
- [ ] GitHub repo public
- [ ] Semua file kode ada (tidak ada yang lupa di-push)
- [ ] README berisi: nama anggota + **kontribusi per orang** + cara menjalankan + screenshot + refleksi
- [x] `architecture.md` tersedia untuk asisten dosen / lampiran
- [ ] Link repository sudah dikirim ke LMS

### Bonus 🎁
- [ ] +2: Consumer pakai library `hdfs` Python langsung (sudah di repo)
- [ ] +3: Dashboard ada chart Chart.js / Plotly.js
- [ ] +5: Spark MLlib (K-Means / Linear Regression) ada di notebook

---

## 📊 Estimasi Total Waktu

| Fase | Estimasi | PIC |
|---|---|---|
| 0. Persiapan | 1 jam | Semua |
| 1. Docker | 1–2 jam | Anggota 1 |
| 2. Producer | 4–6 jam | Anggota 2 & 3 |
| 3. Consumer | 3–4 jam | Anggota 3 |
| 4. Spark | 4–6 jam | Anggota 4 |
| 5. Dashboard | 3–4 jam | Anggota 5 |
| 6. README & finalisasi | 3–4 jam | Semua |
| **Total** | **~20–27 jam** | |

Disebar ke 5 anggota × 14 hari → **realistis & santai**.

---

## 🧭 Pembagian Tugas (sesuai saran soal)

| Anggota | Tanggung Jawab Utama |
|---|---|
| **Hansen Chang** (5027241028) | _isi sesuai pembagian tim_ |
| **Ahmad Ibnu Athaillah** (5027241024) | _isi sesuai pembagian tim_ |
| **Naila Raniyah Hanan** (5027241078) | _isi sesuai pembagian tim_ |
| **Diva Aulia Rosa** (5027241003) | _isi sesuai pembagian tim_ |
| **Ahmad Rabbani Fata** (5027241046) | _isi sesuai pembagian tim_ |

> **Saran pembagian**: 1) Infra Docker, 2) Producer API, 3) Producer RSS + Consumer, 4) Spark Analysis, 5) Dashboard + README polish.

---

**Update progress di sini setiap selesai 1 item. Good luck team.**

---

## Catatan versi (sinkron kode)

| Aspek | Keterangan |
|-------|------------|
| **Sample data** | Demo di `app.py` bila JSON dashboard kosong; pipeline memakai AQICN/simulator + RSS + HDFS. |
| **Producer** | `kafka-python-ng`, tanpa `enable_idempotence` (setara: `acks=all` + `max_in_flight=1`). |
| **Consumer → HDFS** | Prefer `HDFS_WRITE_MODE=docker_exec` di WSL2. |
| **Spark** | Baca/ tulis HDFS + fallback `docker exec`; `SPARK_HOME` ke `pyspark` di `.venv` bila perlu. |
| **Dokumentasi** | `README.md` (demo), `architecture.md` (teknis + eksekutif). |
