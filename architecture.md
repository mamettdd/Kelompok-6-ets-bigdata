# Arsitektur Sistem — AirQuality Alert (Kelompok 6)

Dokumen ini menjelaskan **arsitektur**, **alur data**, dan **cara kerja** pipeline end-to-end. Setiap bagian dimulai dengan **lapisan teknis** (untuk engineer / asisten dosen), lalu **lapisan eksekutif** (untuk stakeholder non-teknis / presentasi singkat).

---

## 1. Gambaran arsitektur

### Teknis

Stack mengikuti pola **ingest → message bus → penyimpanan terdistribusi → pemrosesan batch/analitik → presentation API**.

| Lapisan | Teknologi | Peran |
|---------|-----------|--------|
| Ingest | `producer_api.py`, `producer_rss.py` | Mengambil data dari **AQICN** (atau simulator) dan **RSS** (HTTP + `feedparser`), serialisasi JSON, mengirim ke **Apache Kafka** dengan *key* deterministik (kota / hash URL). |
| Message bus | Kafka + Zookeeper | Dua topik: `airquality-api`, `airquality-rss`. Penyimpanan log ter-append, *consumer group* terpisah per topik untuk paralelisme logis. |
| Sink / storage | `consumer_to_hdfs.py`, HDFS | *Thread* per topik, *buffer* waktu/jumlah record, flush ke path HDFS `/data/airquality/{api,rss}/`. Mirror file JSON ke host (`dashboard/data/`) untuk latensi rendah ke UI. |
| Processing | PySpark, `analysis.ipynb` | Membaca JSON historis dari HDFS, menjalankan **tiga analisis wajib** (DataFrame + Spark SQL), menulis hasil Parquet ke `/data/airquality/hasil/` dan ringkasan agregat ke `spark_results.json`. |
| Presentation | Flask, `app.py` | Melayani HTML + endpoint `GET /api/data` menggabungkan Spark + live API + RSS; fallback demo jika file belum ada. |

Replikasi HDFS (mis. faktor 2) memastikan blok data tersimpan di lebih dari satu DataNode sesuai konfigurasi cluster Docker.

**Komunikasi antar komponen (ringkas):**

```
[Sumber eksternal]     [Producers]        [Kafka topics]      [Consumer]           [HDFS paths]
AQICN / simulator  →  producer_api   →  airquality-api   →  thread API    →  .../api/*.json
RSS feeds          →  producer_rss   →  airquality-rss   →  thread RSS    →  .../rss/*.json
                                               ↓
                                    [Spark batch]  →  .../hasil/* + spark_results.json
                                               ↓
                                    [Flask]  ←  mirror + JSON hasil analisis
```

### Eksekutif

Secara bisnis, sistem ini **mengumpulkan sinyal kualitas udara per kota** dan **berita lingkungan**, menyimpannya secara **terpusat dan tahan lama**, lalu **meringkas pola** (misalnya jam puncak polusi, kota paling buruk) untuk **dashboard** yang bisa dipantau Dinas Kesehatan atau tim operasional. Alurnya sama dengan prinsip *data lake*: data mentah masuk dulu, analisis dijalankan di atasnya, lalu hasilnya ditampilkan tanpa mengunci format sumber awal.

---

## 2. Alur data (end-to-end)

### Teknis

1. **Producer API** — interval baca (sesuai konfigurasi, rubrik 15 menit) endpoint WAQI per slug kota; jika gagal, fallback **simulator** deterministik-stokastik. Pesan berisi AQI, polutan, stempel waktu, sumber. `KafkaProducer` memakai `acks=all`, *retry*, *key* = slug kota.
2. **Producer RSS** — interval baca feed; **deduplikasi** dengan `seen_ids.json`; *key* = MD5 URL. Filter keyword opsional + fallback top-N jika kosong.
3. **Consumer** — dua *consumer* dengan *group id* berbeda; buffer `BUFFER_FLUSH_SEC` / `BUFFER_MAX_RECORDS`; pada flush: tulis batch baris-JSON ke file HDFS (strategi `docker_exec` ke `namenode` jika WebHDFS dari host bermasalah di WSL2), update mirror `live_api.json` / `live_rss.json`.
4. **Spark** — skema baca JSON → normalisasi kolom waktu & AQI → tiga analisis → output Parquet + `spark_results.json`.
5. **Dashboard** — polling/refresh klien ke `/api/data`; Chart.js untuk seri agregat; tema light/dark opsional.

### Eksekutif

Alurnya berurutan: **ambil data dari luar** → **antrekan di Kafka** supaya tidak hilang saat picu tinggi → **simpan ke penyimpanan besar (HDFS)** sebagai jejak audit → **hitung ringkasan statistik** dengan Spark → **tampilkan** di web. Stakeholder cukup memahami: *data mengalir satu arah dari sumber ke layar, dengan perhentian jelas di “antrian” dan “gudang data”.*

---

## 3. Komponen Kafka

### Teknis

- **Topic `airquality-api`:** partisi default; *key* kota untuk co-lokasi logis per kota.
- **Topic `airquality-rss`:** *key* hash URL untuk menyebarkan beban dan membantu deduplikasi konsumen.
- **Consumer group** terpisah (`CONSUMER_GROUP_API`, `CONSUMER_GROUP_RSS`) agar offset commit independen; *lag* dapat dimonitor lewat tooling Kafka standar.

### Eksekutif

Kafka berperan sebagai **buffer aman** antara “pengirim cepat” (producer) dan “penulis ke disk” (consumer). Jika penulisan ke HDFS lebih lambat dari laju producer, data tetap menunggu di topik sehingga **tidak kehilangan event** dalam batas retensi topik.

---

## 4. Lapisan HDFS

### Teknis

- Path konfigurasi: `HDFS_BASE_DIR` (mis. `/data/airquality`).
- Subfolder `api/`, `rss/` berisi file JSON per flush (nama berbasis waktu UTC).
- Subfolder `hasil/` untuk artefak Spark (Parquet).
- **Namenode** menyimpan metadata; **DataNode** menyimpan blok; replikasi mengikuti `dfs.replication`.
- Akses dari aplikasi host ke HDFS sering via `localhost:9000` (RPC) dan `localhost:9870` (HTTP/WebHDFS); penulisan dari host WSL2 dapat memakai `docker exec namenode hdfs dfs -put` untuk menghindari redirect ke hostname DataNode yang tidak resolvable di host.

### Eksekutif

HDFS adalah **gudang file terdistribusi**: file besar dan banyak **terpecah dan digandakan** di beberapa server sehingga **tahan kerusakan disk** dan siap untuk analisis batch. Untuk demonstrasi, yang penting: **data historis API dan RSS tertinggal rapi di folder** dan bisa diperiksa lewat UI Namenode.

---

## 5. Pemrosesan Spark

### Teknis

- `SparkSession` dengan `fs.defaultFS` mengarah ke Namenode.
- Baca JSON multi-file; normalisasi timezone (Asia/Jakarta).
- Analisis: (1) distribusi kategori AQI per kota, (2) agregat per jam + ranking jam puncak dengan **Spark SQL / window**, (3) ranking kota + hitung event “Tidak Sehat+”.
- Output: Parquet di HDFS + JSON terstruktur untuk konsumsi Flask.

### Eksekutif

Spark menjawab pertanyaan bisnis: **“Kapan polusi puncak?”** dan **“Kota mana yang paling sering tidak sehat?”** dengan menghitung **dari seluruh riwayat** yang sudah tersimpan, bukan hanya snapshot terakhir di layar.

---

## 6. Dashboard Flask

### Teknis

- `build_payload()` menggabungkan tiga sumber: `spark_results.json`, `live_api.json`, `live_rss.json`.
- Flag `is_demo` / `_demo` menandai data bawaan vs file pipeline.
- Frontend: fetch periodik, render tabel + Chart.js; tema `data-theme` + `localStorage`.

### Eksekutif

Dashboard adalah **satu pintu** melihat **kondisi terkini** (live) dan **tren/ringkasan** (Spark). Cocok untuk **monitoring harian** dan **presentasi hasil analisis** dalam satu halaman.

---

## 7. Ringkasan satu halaman (eksekutif)

| Pertanyaan | Jawaban singkat |
|------------|------------------|
| Data dari mana? | API kualitas udara (dan/atau simulator) + berita RSS. |
| Mengapa Kafka? | Menstabilkan laju data dan memisahkan ingest dari penyimpanan. |
| Mengapa HDFS? | Menyimpan jejak historis skala besar untuk analisis. |
| Apa peran Spark? | Menghitung agregat dan jawaban analitik dari data historis. |
| Apa yang dilihat user? | Dashboard web dengan angka live, grafik, dan tabel agregat. |

---

## 8. Istilah referensi cepat

| Istilah | Teknis | Eksekutif |
|---------|--------|-----------|
| Producer | Aplikasi yang `send` ke Kafka | Pengirim data ke sistem antrian |
| Consumer | Aplikasi yang `poll` topic dan commit offset | Penerima yang menulis ke HDFS / file lokal |
| Topic | Log ter-partisi di broker | “Saluran” data berlabel |
| HDFS | Filesystem terdistribusi Hadoop | Penyimpanan file besar ter-replikasi |
| Spark | Engine komputasi terdistribusi (DataFrame/SQL) | Alat hitung statistik atas data besar |

---

*Dokumen ini selaras dengan implementasi repositori `Kelompok-6-ets-bigdata` (Kafka, HDFS multi-DataNode, Spark notebook, Flask dashboard).*
