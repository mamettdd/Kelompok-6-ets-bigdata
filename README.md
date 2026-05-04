# AirQuality Alert: Monitoring Kualitas Udara Jawa Timur

ETS Big Data & Data Lakehouse - Kelompok 6

> **Fokus README**
> README ini menjelaskan sistem, arsitektur, alur data, file, konfigurasi, cara jalan, validasi, troubleshooting, dan alasan desain.
> Catatan pengerjaan, checklist fase, dan item kerja tetap berada di `CHECKLIST.md`.

---

## Daftar Isi

- Ringkasan Cepat
- Latar Belakang
- Tujuan dan Pertanyaan Bisnis
- Arsitektur Utama
- Alur Data Lengkap
- Struktur Repository
- Komponen Infrastruktur
- Pipeline Kafka
- Penyimpanan HDFS
- Analisis Spark
- Dashboard Flask
- Konfigurasi Environment
- Cara Menjalankan
- Verifikasi
- Troubleshooting
- Argumentasi Desain
- Batasan dan Rekomendasi
- Glosarium
- Lampiran Rinci
- Kesimpulan

---

## Ringkasan Cepat

Proyek ini adalah pipeline Big Data untuk memantau kualitas udara beberapa kota di Jawa Timur.

| Bagian | Teknologi | Peran |
| --- | --- | --- |
| Ingest AQI | `producer_api.py` | Mengambil data AQI dari AQICN atau simulator. |
| Ingest RSS | `producer_rss.py` | Mengambil berita dari RSS dan melakukan deduplikasi. |
| Message broker | Apache Kafka | Menjadi antrian data untuk API dan RSS. |
| Storage | Hadoop HDFS | Menyimpan data historis dalam file batch. |
| Analytics | Apache Spark | Menghitung distribusi kategori, rata-rata per jam, dan ranking kota. |
| Presentation | Flask + Chart.js | Menampilkan data live dan hasil analisis dalam dashboard. |

**Teknis:** Alur utama adalah `AQICN/RSS -> Producer -> Kafka -> Consumer -> HDFS -> Spark -> Dashboard`.

**Maksud sederhana:** Data diambil, diantrikan, disimpan, dihitung, lalu ditampilkan.

## Latar Belakang

### Kualitas udara berubah menurut waktu

**Teknis:** AQI adalah data time-series karena nilainya berubah dari waktu ke waktu.

**Maksud sederhana:** Kondisi udara pagi, siang, dan malam bisa berbeda.

### Kualitas udara berbeda antar kota

**Teknis:** Surabaya, Sidoarjo, Gresik, Mojokerto, dan Malang memiliki karakter aktivitas berbeda.

**Maksud sederhana:** Setiap kota punya risiko dan pola kualitas udara sendiri.

### Data angka butuh konteks

**Teknis:** AQI memberi angka, sedangkan RSS memberi konteks berita lingkungan.

**Maksud sederhana:** Pengguna tidak hanya melihat angka, tetapi juga konteks kejadian.

### Big Data cocok untuk pola historis

**Teknis:** Data disimpan di HDFS agar bisa dianalisis ulang oleh Spark.

**Maksud sederhana:** Data lama tetap berguna untuk menemukan pola.

### Dashboard memudahkan konsumsi informasi

**Teknis:** Flask menyajikan ringkasan dalam bentuk API dan halaman web.

**Maksud sederhana:** Hasil analisis bisa dibaca tanpa membuka notebook atau terminal.

## Tujuan dan Pertanyaan Bisnis

| Pertanyaan | Jawaban Teknis | Maksud Sederhana |
| --- | --- | --- |
| Jam berapa kualitas udara paling buruk? | Spark SQL menghitung rata-rata AQI per kota per jam. | Menemukan jam rawan polusi. |
| Kota mana yang kualitas udaranya paling buruk? | Spark membuat ranking berdasarkan rata-rata AQI. | Menentukan kota prioritas perhatian. |
| Seberapa sering kota masuk kategori buruk? | Spark menghitung distribusi kategori AQI per kota. | Melihat seberapa sering udara tidak sehat. |
| Apa konteks beritanya? | Producer RSS mengirim berita ke Kafka dan HDFS. | Menampilkan berita lingkungan terkait. |
| Bagaimana semua komponen tersambung? | README ini memetakan producer, Kafka, HDFS, Spark, dan Flask. | Pembaca bisa mengikuti alur dari sumber data sampai dashboard. |

## Arsitektur Utama

```text
+----------------------+       +----------------------+
| AQICN API            |       | RSS Feeds            |
| atau Simulator       |       | Kontan/Liputan6/Tempo/CNBC/CNN/Jawa Pos |
+----------+-----------+       +----------+-----------+
           |                              |
           v                              v
+----------------------+       +----------------------+
| producer_api.py      |       | producer_rss.py      |
| key = city_slug      |       | key = md5(link)      |
+----------+-----------+       +----------+-----------+
           |                              |
           +--------------+---------------+
                          v
+------------------------------------------------------+
| Apache Kafka                                         |
| topic: airquality-api                                |
| topic: airquality-rss                                |
+-------------------------+----------------------------+
                          |
                          v
+------------------------------------------------------+
| consumer_to_hdfs.py                                 |
| dua thread, buffer, flush HDFS, mirror dashboard     |
+-------------------------+----------------------------+
                          |
          +---------------+---------------+
          |                               |
          v                               v
+-------------------------+     +------------------------+
| HDFS                    |     | dashboard/data JSON    |
| api, rss, hasil         |     | live_api, live_rss     |
+------------+------------+     +-----------+------------+
             |                              |
             v                              v
+-------------------------+     +------------------------+
| spark/analysis.ipynb    |     | dashboard/app.py       |
| tiga analisis utama     |     | Flask API + HTML       |
+------------+------------+     +-----------+------------+
             |                              |
             +---------------+--------------+
                             v
                       Browser pengguna
```

**Teknis:** Arsitektur memisahkan ingestion, broker, storage, analytics, dan presentation.

**Maksud sederhana:** Setiap bagian punya tugas sendiri sehingga sistem mudah dipahami dan diuji.

## Alur Data Lengkap

### 1. Producer API membaca data

**Teknis:** `producer_api.py` membaca AQICN atau simulator untuk lima kota.

**Maksud sederhana:** Data kualitas udara masuk ke sistem.

### 2. Producer RSS membaca berita

**Teknis:** `producer_rss.py` membaca feed RSS, filter keyword, dan dedup link.

**Maksud sederhana:** Berita terbaru masuk sebagai konteks.

### 3. Kafka menyimpan message

**Teknis:** Kafka menyimpan event API dan RSS di dua topic terpisah.

**Maksud sederhana:** Data menunggu di antrian.

### 4. Consumer membaca Kafka

**Teknis:** `consumer_to_hdfs.py` membaca dua topic dengan dua thread.

**Maksud sederhana:** Dua aliran diproses paralel.

### 5. Consumer menulis HDFS

**Teknis:** Data di-buffer lalu ditulis ke HDFS sebagai NDJSON.

**Maksud sederhana:** Data menjadi arsip historis.

### 6. Consumer membuat mirror

**Teknis:** Snapshot terbaru ditulis ke `dashboard/data/live_*.json`.

**Maksud sederhana:** Dashboard punya data cepat dibaca.

### 7. Spark membaca HDFS

**Teknis:** Notebook membaca data API dari `/data/airquality/api/`.

**Maksud sederhana:** Data historis dihitung.

### 8. Spark menulis hasil

**Teknis:** Hasil analisis ditulis ke HDFS dan `spark_results.json`.

**Maksud sederhana:** Insight siap ditampilkan.

### 9. Flask menyajikan dashboard

**Teknis:** Flask membaca JSON lokal dan menyajikan `/api/data`.

**Maksud sederhana:** Pengguna melihat hasil di browser.

## Struktur Repository

| Path | Fungsi | Catatan Baca |
| --- | --- | --- |
| `README.md` | Dokumentasi utama. | Fokus pada sistem, bukan progres. |
| `CHECKLIST.md` | Checklist pengerjaan dan status. | Tempat catatan progres. |
| `architecture.md` | Ringkasan arsitektur. | Versi pendek desain sistem. |
| `address.md` | Peta path dan alamat. | Membantu navigasi repo. |
| `requirements.txt` | Dependency Python. | Dipakai untuk setup venv. |
| `.env.example` | Template environment. | Disalin menjadi `.env`. |
| `.gitignore` | Aturan file yang tidak di-commit. | Melindungi secrets dan runtime output. |
| `docker-compose-kafka.yml` | Kafka dan Zookeeper. | Stack message broker. |
| `docker-compose-hadoop.yml` | Hadoop cluster lokal. | Stack HDFS dan YARN. |
| `hadoop.env` | Konfigurasi Hadoop. | Termasuk replikasi HDFS. |
| `scripts/` | Script operasional. | Start, stop, init, run, check. |
| `kafka/` | Producer dan consumer. | Logika ingestion dan sink. |
| `spark/` | Notebook analisis. | Logika agregasi data. |
| `dashboard/` | Flask app dan frontend. | Layer presentasi. |

## Komponen Infrastruktur

### Zookeeper

**Teknis:** Service `zookeeper` memakai image `wurstmeister/zookeeper` dan port `2181`.

**Maksud sederhana:** Komponen pendukung Kafka.

### Kafka broker

**Teknis:** Service Kafka memakai container `kafka-broker` dengan port `9092` dan `29092`.

**Maksud sederhana:** Server antrian utama.

### NameNode

**Teknis:** `namenode` membuka UI `9870` dan RPC `9000`.

**Maksud sederhana:** Pusat metadata HDFS.

### DataNode

**Teknis:** `datanode1`, `datanode2`, dan `datanode3` menyimpan block HDFS.

**Maksud sederhana:** Rak penyimpanan data.

### ResourceManager

**Teknis:** `resourcemanager` membuka UI YARN di `8088`.

**Maksud sederhana:** Pengelola resource Hadoop.

### NodeManager

**Teknis:** `nodemanager` menjadi worker YARN.

**Maksud sederhana:** Pekerja cluster.

## Pipeline Kafka

### Topic API

**Teknis:** `airquality-api` berisi event AQI.

**Maksud sederhana:** Saluran angka kualitas udara.

### Topic RSS

**Teknis:** `airquality-rss` berisi event berita.

**Maksud sederhana:** Saluran konteks berita.

### Kafka key API

**Teknis:** Key memakai `city_slug`.

**Maksud sederhana:** Setiap kota punya identitas.

### Kafka key RSS

**Teknis:** Key memakai MD5 dari link.

**Maksud sederhana:** Setiap berita punya identitas.

### Manual topic creation

**Teknis:** `KAFKA_AUTO_CREATE_TOPICS_ENABLE=false`.

**Maksud sederhana:** Topic dibuat sengaja, bukan otomatis.

### Consumer group

**Teknis:** API dan RSS memakai group berbeda.

**Maksud sederhana:** Posisi baca dua aliran dipisah.

## Penyimpanan HDFS

### Path API

**Teknis:** `/data/airquality/api/` menyimpan NDJSON AQI.

**Maksud sederhana:** Arsip angka kualitas udara.

### Path RSS

**Teknis:** `/data/airquality/rss/` menyimpan NDJSON berita.

**Maksud sederhana:** Arsip konteks berita.

### Path hasil

**Teknis:** `/data/airquality/hasil/` menyimpan output Spark.

**Maksud sederhana:** Arsip hasil analisis.

### Replikasi

**Teknis:** `dfs.replication=2`.

**Maksud sederhana:** Setiap block punya salinan.

### Write mode

**Teknis:** `docker_exec` menjadi default.

**Maksud sederhana:** Lebih aman untuk WSL2.

### Format

**Teknis:** File batch memakai JSON per baris.

**Maksud sederhana:** Mudah dibaca Spark.

## Analisis Spark

### Input

**Teknis:** Spark membaca `/data/airquality/api/*.json`.

**Maksud sederhana:** Bahan analisis adalah data historis.

### Normalisasi waktu

**Teknis:** `observed_at` diprioritaskan, lalu `timestamp_ingest`.

**Maksud sederhana:** Pakai waktu terbaik yang tersedia.

### Kategori AQI

**Teknis:** AQI dipetakan ke Baik, Sedang, Tidak Sehat, Berbahaya.

**Maksud sederhana:** Angka jadi label mudah dibaca.

### Analisis 1

**Teknis:** Distribusi kategori AQI per kota.

**Maksud sederhana:** Melihat komposisi kondisi udara.

### Analisis 2

**Teknis:** Rata-rata AQI per kota per jam.

**Maksud sederhana:** Menemukan jam rawan.

### Analisis 3

**Teknis:** Ranking kota berdasarkan rata-rata AQI dan event >100.

**Maksud sederhana:** Menentukan prioritas kota.

## Dashboard Flask

### Route utama

**Teknis:** `/` merender `index.html`.

**Maksud sederhana:** Halaman dashboard.

### API data

**Teknis:** `/api/data` menggabungkan Spark, API, dan RSS.

**Maksud sederhana:** Satu endpoint untuk browser.

### API status

**Teknis:** `/api/status` menjadi alias.

**Maksud sederhana:** Kompatibilitas endpoint.

### Fallback demo

**Teknis:** Backend punya data contoh jika file belum ada.

**Maksud sederhana:** Dashboard tetap bisa dibuka.

### Auto refresh

**Teknis:** Frontend fetch ulang setiap 30 detik.

**Maksud sederhana:** Data diperbarui otomatis.

### Theme

**Teknis:** Tema light/dark disimpan di localStorage.

**Maksud sederhana:** Tampilan nyaman dibaca lama.

## Konfigurasi Environment

### KAFKA_BOOTSTRAP

**Teknis:** `KAFKA_BOOTSTRAP` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `KAFKA_BOOTSTRAP` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### KAFKA_TOPIC_API

**Teknis:** `KAFKA_TOPIC_API` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `KAFKA_TOPIC_API` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### KAFKA_TOPIC_RSS

**Teknis:** `KAFKA_TOPIC_RSS` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `KAFKA_TOPIC_RSS` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### AQICN_TOKEN

**Teknis:** `AQICN_TOKEN` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `AQICN_TOKEN` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### FORCE_SIMULATOR

**Teknis:** `FORCE_SIMULATOR` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `FORCE_SIMULATOR` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### POLL_INTERVAL_SEC

**Teknis:** `POLL_INTERVAL_SEC` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `POLL_INTERVAL_SEC` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### HTTP_TIMEOUT_SEC

**Teknis:** `HTTP_TIMEOUT_SEC` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `HTTP_TIMEOUT_SEC` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### POLL_INTERVAL_SEC_RSS

**Teknis:** `POLL_INTERVAL_SEC_RSS` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `POLL_INTERVAL_SEC_RSS` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### RSS_FEEDS

**Teknis:** `RSS_FEEDS` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `RSS_FEEDS` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### RSS_KEYWORDS

**Teknis:** `RSS_KEYWORDS` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `RSS_KEYWORDS` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### RSS_FALLBACK_TOPN

**Teknis:** `RSS_FALLBACK_TOPN` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `RSS_FALLBACK_TOPN` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### RSS_USER_AGENT

**Teknis:** `RSS_USER_AGENT` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `RSS_USER_AGENT` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### RSS_SEEN_IDS_FILE

**Teknis:** `RSS_SEEN_IDS_FILE` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `RSS_SEEN_IDS_FILE` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### RSS_MAX_SEEN_IDS

**Teknis:** `RSS_MAX_SEEN_IDS` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `RSS_MAX_SEEN_IDS` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### HDFS_NAMENODE_URL

**Teknis:** `HDFS_NAMENODE_URL` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `HDFS_NAMENODE_URL` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### HDFS_NAMENODE_RPC

**Teknis:** `HDFS_NAMENODE_RPC` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `HDFS_NAMENODE_RPC` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### HDFS_USER

**Teknis:** `HDFS_USER` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `HDFS_USER` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### HDFS_BASE_DIR

**Teknis:** `HDFS_BASE_DIR` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `HDFS_BASE_DIR` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### HDFS_NAMENODE_CONTAINER

**Teknis:** `HDFS_NAMENODE_CONTAINER` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `HDFS_NAMENODE_CONTAINER` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### HDFS_WRITE_MODE

**Teknis:** `HDFS_WRITE_MODE` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `HDFS_WRITE_MODE` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### BUFFER_FLUSH_SEC

**Teknis:** `BUFFER_FLUSH_SEC` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `BUFFER_FLUSH_SEC` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### BUFFER_MAX_RECORDS

**Teknis:** `BUFFER_MAX_RECORDS` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `BUFFER_MAX_RECORDS` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### CONSUMER_GROUP_API

**Teknis:** `CONSUMER_GROUP_API` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `CONSUMER_GROUP_API` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### CONSUMER_GROUP_RSS

**Teknis:** `CONSUMER_GROUP_RSS` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `CONSUMER_GROUP_RSS` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### DASHBOARD_DATA_DIR

**Teknis:** `DASHBOARD_DATA_DIR` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `DASHBOARD_DATA_DIR` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

### PORT

**Teknis:** `PORT` mengubah perilaku runtime komponen terkait.

**Maksud sederhana:** `PORT` adalah tuas konfigurasi agar proyek bisa menyesuaikan mesin dan kebutuhan demo.

## Cara Menjalankan

### Clone repository

```bash
git clone https://github.com/mamettdd/Kelompok-6-ets-bigdata.git
```

**Teknis:** Command `git clone https://github.com/mamettdd/Kelompok-6-ets-bigdata.git` menjalankan tahap clone repository.

**Maksud sederhana:** Tahap ini membawa proyek satu langkah lebih dekat ke dashboard berjalan.

### Masuk folder proyek

```bash
cd Kelompok-6-ets-bigdata
```

**Teknis:** Command `cd Kelompok-6-ets-bigdata` menjalankan tahap masuk folder proyek.

**Maksud sederhana:** Tahap ini membawa proyek satu langkah lebih dekat ke dashboard berjalan.

### Buat virtual environment

```bash
python3 -m venv .venv
```

**Teknis:** Command `python3 -m venv .venv` menjalankan tahap buat virtual environment.

**Maksud sederhana:** Tahap ini membawa proyek satu langkah lebih dekat ke dashboard berjalan.

### Aktifkan virtual environment

```bash
source .venv/bin/activate
```

**Teknis:** Command `source .venv/bin/activate` menjalankan tahap aktifkan virtual environment.

**Maksud sederhana:** Tahap ini membawa proyek satu langkah lebih dekat ke dashboard berjalan.

### Install dependency

```bash
pip install -r requirements.txt
```

**Teknis:** Command `pip install -r requirements.txt` menjalankan tahap install dependency.

**Maksud sederhana:** Tahap ini membawa proyek satu langkah lebih dekat ke dashboard berjalan.

### Salin environment

```bash
cp .env.example .env
```

**Teknis:** Command `cp .env.example .env` menjalankan tahap salin environment.

**Maksud sederhana:** Tahap ini membawa proyek satu langkah lebih dekat ke dashboard berjalan.

### Start stack

```bash
bash scripts/start-stack.sh
```

**Teknis:** Command `bash scripts/start-stack.sh` menjalankan tahap start stack.

**Maksud sederhana:** Tahap ini membawa proyek satu langkah lebih dekat ke dashboard berjalan.

### Init infrastruktur

```bash
bash scripts/init-infra.sh
```

**Teknis:** Command `bash scripts/init-infra.sh` menjalankan tahap init infrastruktur.

**Maksud sederhana:** Tahap ini membawa proyek satu langkah lebih dekat ke dashboard berjalan.

### Sanity check

```bash
bash scripts/sanity-check.sh
```

**Teknis:** Command `bash scripts/sanity-check.sh` menjalankan tahap sanity check.

**Maksud sederhana:** Tahap ini membawa proyek satu langkah lebih dekat ke dashboard berjalan.

### Run producers

```bash
bash scripts/run-producers.sh
```

**Teknis:** Command `bash scripts/run-producers.sh` menjalankan tahap run producers.

**Maksud sederhana:** Tahap ini membawa proyek satu langkah lebih dekat ke dashboard berjalan.

### Run consumer

```bash
bash scripts/run-consumer.sh
```

**Teknis:** Command `bash scripts/run-consumer.sh` menjalankan tahap run consumer.

**Maksud sederhana:** Tahap ini membawa proyek satu langkah lebih dekat ke dashboard berjalan.

### Run Spark notebook

```bash
jupyter notebook spark/analysis.ipynb
```

**Teknis:** Command `jupyter notebook spark/analysis.ipynb` menjalankan tahap run spark notebook.

**Maksud sederhana:** Tahap ini membawa proyek satu langkah lebih dekat ke dashboard berjalan.

### Run dashboard

```bash
bash scripts/run-dashboard.sh
```

**Teknis:** Command `bash scripts/run-dashboard.sh` menjalankan tahap run dashboard.

**Maksud sederhana:** Tahap ini membawa proyek satu langkah lebih dekat ke dashboard berjalan.

## Verifikasi

### Cek container

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

**Teknis:** docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

**Maksud sederhana:** Memastikan container hidup.

### Cek topic Kafka

```bash
docker exec kafka-broker kafka-topics.sh --bootstrap-server localhost:9092 --list
```

**Teknis:** docker exec kafka-broker kafka-topics.sh --bootstrap-server localhost:9092 --list

**Maksud sederhana:** Memastikan saluran data ada.

### Cek folder HDFS

```bash
docker exec namenode hdfs dfs -ls -R /data/airquality/
```

**Teknis:** docker exec namenode hdfs dfs -ls -R /data/airquality/

**Maksud sederhana:** Memastikan gudang data siap.

### Cek API dashboard

```bash
curl -s http://127.0.0.1:5000/api/data
```

**Teknis:** `curl -s http://127.0.0.1:5000/api/data`

**Maksud sederhana:** Memastikan Flask memberi data.

### Cek consumer group API

```bash
docker exec kafka-broker kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group airquality-consumer-api
```

**Teknis:** docker exec kafka-broker kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group airquality-consumer-api

**Maksud sederhana:** Memastikan consumer API terlacak.

## Troubleshooting

| Gejala | Penyebab | Solusi |
| --- | --- | --- |
| Docker permission denied | User belum masuk grup `docker`. | Tambahkan user ke grup docker lalu login ulang. |
| Kafka tidak connect | Container belum siap atau port belum terbuka. | Jalankan stack dan tunggu beberapa detik. |
| Topic tidak ada | Init belum dijalankan. | Jalankan `bash scripts/init-infra.sh`. |
| Consumer belum flush | Buffer belum mencapai batas waktu atau jumlah. | Turunkan `BUFFER_FLUSH_SEC` untuk demo. |
| HDFS gagal via WebHDFS | Redirect hostname DataNode bermasalah di WSL2. | Gunakan `HDFS_WRITE_MODE=docker_exec`. |
| Notebook error module hdfs | Kernel tidak memakai venv yang benar. | Install requirements dan pilih kernel venv. |
| Dashboard masih demo | File JSON runtime belum tersedia. | Jalankan producer, consumer, dan Spark. |
| RSS terlalu umum | Fallback Top-N aktif atau keyword terlalu longgar. | Atur `RSS_KEYWORDS` dan `RSS_FEEDS`. |

## Argumentasi Desain

### Mengapa Kafka?

**Teknis:** Kafka memisahkan producer dan consumer menggunakan topic dan offset.

**Maksud sederhana:** Pengambil data tidak terganggu jika penyimpan sedang lambat.

### Mengapa HDFS?

**Teknis:** HDFS menyimpan file historis dengan replikasi.

**Maksud sederhana:** Data lama tetap aman sebagai arsip.

### Mengapa Spark?

**Teknis:** Spark cocok untuk agregasi historis dan SQL.

**Maksud sederhana:** Data mentah berubah menjadi insight.

### Mengapa Flask?

**Teknis:** Flask cukup ringan untuk API dan dashboard lokal.

**Maksud sederhana:** Hasil mudah dibuka di browser.

### Mengapa JSON mirror?

**Teknis:** Dashboard membaca file ringkas, bukan HDFS langsung.

**Maksud sederhana:** Halaman lebih cepat dan sederhana.

### Mengapa simulator?

**Teknis:** Simulator menjaga pipeline tetap testable saat API gagal.

**Maksud sederhana:** Demo tetap berjalan.

## Batasan dan Rekomendasi

| Area | Batasan | Rekomendasi |
| --- | --- | --- |
| Token contoh | Token nyata tidak ideal di `.env.example`. | Ganti dengan placeholder sebelum publik. |
| Kafka | Satu broker dan replication factor topic 1. | Tambah broker untuk produksi. |
| RSS | Filter keyword sederhana. | Tambahkan NLP jika butuh presisi. |
| Spark | RSS belum dianalisis formal. | Tambahkan join RSS dan AQI per jam. |
| Notebook | `HDFS_BASE` hardcoded. | Baca dari environment agar fleksibel. |
| Flask | Debug mode cocok lokal saja. | Matikan debug untuk publik. |

## Glosarium

### AQI

**Teknis:** `AQI` adalah istilah teknis dalam sistem ini.

**Maksud sederhana:** Indeks kualitas udara

### Producer

**Teknis:** `Producer` adalah istilah teknis dalam sistem ini.

**Maksud sederhana:** Pengirim data

### Consumer

**Teknis:** `Consumer` adalah istilah teknis dalam sistem ini.

**Maksud sederhana:** Pembaca data

### Topic

**Teknis:** `Topic` adalah istilah teknis dalam sistem ini.

**Maksud sederhana:** Saluran Kafka

### Offset

**Teknis:** `Offset` adalah istilah teknis dalam sistem ini.

**Maksud sederhana:** Posisi baca

### HDFS

**Teknis:** `HDFS` adalah istilah teknis dalam sistem ini.

**Maksud sederhana:** Gudang file terdistribusi

### Istilah NameNode

**Teknis:** `NameNode` adalah istilah teknis dalam sistem ini.

**Maksud sederhana:** Daftar isi HDFS

### Istilah DataNode

**Teknis:** `DataNode` adalah istilah teknis dalam sistem ini.

**Maksud sederhana:** Penyimpan block

### Spark

**Teknis:** `Spark` adalah istilah teknis dalam sistem ini.

**Maksud sederhana:** Mesin analisis

### Flask

**Teknis:** `Flask` adalah istilah teknis dalam sistem ini.

**Maksud sederhana:** Server web

### Parquet

**Teknis:** `Parquet` adalah istilah teknis dalam sistem ini.

**Maksud sederhana:** Format kolumnar

### NDJSON

**Teknis:** `NDJSON` adalah istilah teknis dalam sistem ini.

**Maksud sederhana:** JSON per baris

## Lampiran Rinci

### Lampiran 1: Producer API

**Teknis:** Producer API bertugas membangun event AQI. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer API adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 2: Producer RSS

**Teknis:** Producer RSS bertugas membangun event RSS. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer RSS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 3: Kafka

**Teknis:** Kafka bertugas menyimpan message. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Kafka adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 4: Consumer

**Teknis:** Consumer bertugas menulis batch. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Consumer adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 5: HDFS

**Teknis:** HDFS bertugas menyimpan historis. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** HDFS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 6: Spark

**Teknis:** Spark bertugas menghitung insight. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Spark adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 7: Flask

**Teknis:** Flask bertugas menyediakan API. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Flask adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 8: Browser

**Teknis:** Browser bertugas menampilkan dashboard. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Browser adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 9: Producer API

**Teknis:** Producer API bertugas membangun event AQI. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer API adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 10: Producer RSS

**Teknis:** Producer RSS bertugas membangun event RSS. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer RSS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 11: Kafka

**Teknis:** Kafka bertugas menyimpan message. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Kafka adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 12: Consumer

**Teknis:** Consumer bertugas menulis batch. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Consumer adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 13: HDFS

**Teknis:** HDFS bertugas menyimpan historis. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** HDFS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 14: Spark

**Teknis:** Spark bertugas menghitung insight. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Spark adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 15: Flask

**Teknis:** Flask bertugas menyediakan API. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Flask adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 16: Browser

**Teknis:** Browser bertugas menampilkan dashboard. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Browser adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 17: Producer API

**Teknis:** Producer API bertugas membangun event AQI. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer API adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 18: Producer RSS

**Teknis:** Producer RSS bertugas membangun event RSS. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer RSS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 19: Kafka

**Teknis:** Kafka bertugas menyimpan message. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Kafka adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 20: Consumer

**Teknis:** Consumer bertugas menulis batch. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Consumer adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 21: HDFS

**Teknis:** HDFS bertugas menyimpan historis. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** HDFS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 22: Spark

**Teknis:** Spark bertugas menghitung insight. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Spark adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 23: Flask

**Teknis:** Flask bertugas menyediakan API. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Flask adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 24: Browser

**Teknis:** Browser bertugas menampilkan dashboard. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Browser adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 25: Producer API

**Teknis:** Producer API bertugas membangun event AQI. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer API adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 26: Producer RSS

**Teknis:** Producer RSS bertugas membangun event RSS. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer RSS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 27: Kafka

**Teknis:** Kafka bertugas menyimpan message. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Kafka adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 28: Consumer

**Teknis:** Consumer bertugas menulis batch. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Consumer adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 29: HDFS

**Teknis:** HDFS bertugas menyimpan historis. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** HDFS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 30: Spark

**Teknis:** Spark bertugas menghitung insight. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Spark adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 31: Flask

**Teknis:** Flask bertugas menyediakan API. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Flask adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 32: Browser

**Teknis:** Browser bertugas menampilkan dashboard. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Browser adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 33: Producer API

**Teknis:** Producer API bertugas membangun event AQI. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer API adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 34: Producer RSS

**Teknis:** Producer RSS bertugas membangun event RSS. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer RSS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 35: Kafka

**Teknis:** Kafka bertugas menyimpan message. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Kafka adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 36: Consumer

**Teknis:** Consumer bertugas menulis batch. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Consumer adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 37: HDFS

**Teknis:** HDFS bertugas menyimpan historis. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** HDFS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 38: Spark

**Teknis:** Spark bertugas menghitung insight. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Spark adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 39: Flask

**Teknis:** Flask bertugas menyediakan API. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Flask adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 40: Browser

**Teknis:** Browser bertugas menampilkan dashboard. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Browser adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 41: Producer API

**Teknis:** Producer API bertugas membangun event AQI. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer API adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 42: Producer RSS

**Teknis:** Producer RSS bertugas membangun event RSS. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer RSS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 43: Kafka

**Teknis:** Kafka bertugas menyimpan message. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Kafka adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 44: Consumer

**Teknis:** Consumer bertugas menulis batch. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Consumer adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 45: HDFS

**Teknis:** HDFS bertugas menyimpan historis. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** HDFS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 46: Spark

**Teknis:** Spark bertugas menghitung insight. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Spark adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 47: Flask

**Teknis:** Flask bertugas menyediakan API. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Flask adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 48: Browser

**Teknis:** Browser bertugas menampilkan dashboard. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Browser adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 49: Producer API

**Teknis:** Producer API bertugas membangun event AQI. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer API adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 50: Producer RSS

**Teknis:** Producer RSS bertugas membangun event RSS. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer RSS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 51: Kafka

**Teknis:** Kafka bertugas menyimpan message. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Kafka adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 52: Consumer

**Teknis:** Consumer bertugas menulis batch. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Consumer adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 53: HDFS

**Teknis:** HDFS bertugas menyimpan historis. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** HDFS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 54: Spark

**Teknis:** Spark bertugas menghitung insight. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Spark adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 55: Flask

**Teknis:** Flask bertugas menyediakan API. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Flask adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 56: Browser

**Teknis:** Browser bertugas menampilkan dashboard. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Browser adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 57: Producer API

**Teknis:** Producer API bertugas membangun event AQI. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer API adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 58: Producer RSS

**Teknis:** Producer RSS bertugas membangun event RSS. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer RSS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 59: Kafka

**Teknis:** Kafka bertugas menyimpan message. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Kafka adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 60: Consumer

**Teknis:** Consumer bertugas menulis batch. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Consumer adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 61: HDFS

**Teknis:** HDFS bertugas menyimpan historis. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** HDFS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 62: Spark

**Teknis:** Spark bertugas menghitung insight. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Spark adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 63: Flask

**Teknis:** Flask bertugas menyediakan API. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Flask adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 64: Browser

**Teknis:** Browser bertugas menampilkan dashboard. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Browser adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 65: Producer API

**Teknis:** Producer API bertugas membangun event AQI. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer API adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 66: Producer RSS

**Teknis:** Producer RSS bertugas membangun event RSS. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer RSS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 67: Kafka

**Teknis:** Kafka bertugas menyimpan message. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Kafka adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 68: Consumer

**Teknis:** Consumer bertugas menulis batch. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Consumer adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 69: HDFS

**Teknis:** HDFS bertugas menyimpan historis. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** HDFS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 70: Spark

**Teknis:** Spark bertugas menghitung insight. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Spark adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 71: Flask

**Teknis:** Flask bertugas menyediakan API. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Flask adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 72: Browser

**Teknis:** Browser bertugas menampilkan dashboard. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Browser adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 73: Producer API

**Teknis:** Producer API bertugas membangun event AQI. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer API adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 74: Producer RSS

**Teknis:** Producer RSS bertugas membangun event RSS. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Producer RSS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 75: Kafka

**Teknis:** Kafka bertugas menyimpan message. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Kafka adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 76: Consumer

**Teknis:** Consumer bertugas menulis batch. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Consumer adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 77: HDFS

**Teknis:** HDFS bertugas menyimpan historis. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** HDFS adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 78: Spark

**Teknis:** Spark bertugas menghitung insight. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Spark adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

### Lampiran 79: Flask

**Teknis:** Flask bertugas menyediakan API. Detail ini penting karena pipeline hanya mudah dirawat jika tanggung jawab setiap modul jelas.

**Maksud sederhana:** Flask adalah salah satu bagian rantai dari data mentah sampai tampilan pengguna.

## Kesimpulan

AirQuality Alert adalah pipeline Big Data dari ingestion sampai dashboard.

Kafka menjadi antrian data.

HDFS menjadi penyimpanan historis.

Spark menjadi mesin analisis.

Flask menjadi layer presentasi.

README utama ini menjelaskan sistem; catatan progres berada di `CHECKLIST.md`.

## Referensi

- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Apache Hadoop HDFS Design](https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-hdfs/HdfsDesign.html)
- [Apache Spark SQL Guide](https://spark.apache.org/docs/latest/sql-programming-guide.html)
- [Flask Documentation](https://flask.palletsprojects.com/)
- [AQICN API](https://aqicn.org/api/)
- [Chart.js Documentation](https://www.chartjs.org/docs/latest/)
