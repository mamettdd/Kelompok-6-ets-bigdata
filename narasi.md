# Narasi proyek AirQuality Alert (sangat mudah dipahami)

Ini versi cerita proyek untuk orang yang **tidak harus paham IT**. Detail teknis dan perintah ada di `README.md`.

**Isi file ini:** kamus → tujuan proyek → **banyak diagram Mermaid** (dari gambar besar sampai detail operasional). Baca urut, atau lompat ke [Peta diagram lengkap](#peta-diagram-lengkap).

---

## Kamus singkat (baca ini dulu)

Istilah di bawah ini sering muncul di penjelasan proyek. **Baca sekali**, nanti tidak terasa “tiba-tiba” muncul kata asing.

| Istilah | Arti sederhana |
| --- | --- |
| **Kualitas udara / indeks** | Angka yang mewakili seberapa “bersih” atau “kotor” udaranya. Di proyek ini dipanggil juga **AQI** (*Air Quality Index*): semacam nilai rapor untuk udara. |
| **Sumber angka di internet** | Layanan **AQICN** memberi angka kualitas udara lewat internet. Kalau tidak pakai token, tim bisa pakai **simulator**: angka buatan supaya sistem tetap bisa diuji. |
| **RSS** | Cara sebuah **situs berita** menyediakan **daftar berita terbaru** dalam format mesin. Komputer ambil daftar itu seperti **langganan podcast**, tapi untuk berita. |
| **Zookeeper** | Program pendukung yang membantu **Kafka** berkoordinasi di dalam klaster. Di Docker Anda tidak perlu menyentuhnya manual; cukup tahu ia “teman Kafka”. |
| **Antrian pesan (Kafka)** | **Kafka** seperti **lorong antrian**: siapa saja bisa **menaruh pesan** di belakang, program lain **mengambil dari depan**. Nama saluran disebut **topik**. |
| **Topik** | “Lorong” bernama di Kafka. Di proyek ini ada **`airquality-api`** (angka) dan **`airquality-rss`** (berita). |
| **Kunci pesan (message key)** | **Label** pada pesan di antrian. Untuk angka, kuncinya **nama kota**. Untuk berita, kuncinya **sidik digital dari link** (MD5) supaya satu berita punya identitas tetap. |
| **Grup konsumen (consumer group)** | Nama tim penerima. **API** dan **RSS** pakai **grup berbeda** supaya jarak baca antrian tidak saling ganggu. Di kode: `airquality-consumer-api` dan `airquality-consumer-rss`. |
| **Pengirim (Producer)** | Program yang **mengambil data dari luar**, lalu **memasukkan ke Kafka**. |
| **Penerima (Consumer)** | Program yang **mengambil dari Kafka**, lalu **menyimpan** ke gudang dan file lokal. |
| **Hadoop** | Keluarga perangkat lunak untuk data besar. |
| **HDFS** | **Gudang file** Hadoop (*Hadoop Distributed File System*): file bisa besar dan **disalin ke beberapa mesin**. |
| **NameNode / DataNode** | **NameNode** = buku catatan “file apa di mana”. **DataNode** = rak penyimpanan sebenarnya (di tugas ini ada tiga rak demo). |
| **YARN** | Bagian Hadoop mengatur **sumber daya** pekerjaan (ResourceManager + NodeManager). Ikut jalan di Docker agar mirip klaster sungguhan. |
| **NDJSON** | **Satu baris = satu JSON** (banyak catatan bertumpuk vertikal). Mudah dibaca mesin per baris. |
| **Spark** | Alat **hitung massal** atas banyak file. Di tim ini lewat notebook **`spark/analysis.ipynb`**. |
| **Flask** | Kerangka **situs kecil** dan **API** (meja layanan data untuk halaman web). |
| **Docker** | **Kotak** berisi Hadoop, Kafka, Zookeeper jalan seragam di laptop tiap anggota. |
| **API (web)** | **Alamat** yang dipanggil browser untuk **minta data** (misalnya `/api/data`). |

---

## Proyek ini untuk apa?

Tim kuliah membangun **AirQuality Alert**: memantau **kualitas udara** beberapa kota di **Jawa Timur**, menampilkan **berita** sebagai konteks, berujung **satu halaman web**.

**Latar belakang singkat:** udara berubah sepanjang hari; tiap kota beda; angka saja kurang tanpa berita; **riwayat** membantu lihat pola; **dashboard** memudahkan baca hasil.

---

## Mau menjawab pertanyaan apa?

| Pertanyaan awam | Yang dicari sistem |
| --- | --- |
| Jam berapa udara cenderung paling buruk? | Rata-rata per kota **per jam** |
| Kota mana paling bermasalah? | **Peringkat** kota |
| Seberapa sering tidak sehat? | **Distribusi kategori** (baik / sedang / tidak sehat / berbahaya) |
| Konteks berita? | Item dari **RSS** yang lolos filter kata kunci |

---

## Peta diagram lengkap

Di bawah ini **diagram per diagram**. Tiap diagram menambah detail; yang belakang paling “mikro”.

### 1. Satu garis besar: dari dunia luar sampai mata

```mermaid
flowchart LR
  subgraph luar["Dari luar"]
    A1[Angka AQI]
    A2[Berita RSS]
  end
  subgraph mesin["Di mesin tim"]
    B[Pengirim]
    C[(Kafka)]
    D[Penerima]
    E[(HDFS)]
    F[Spark]
    G[Flask]
  end
  A1 --> B
  A2 --> B
  B --> C
  C --> D
  D --> E
  D --> G
  E --> F
  F --> G
  G --> H[Browser]
```

---

### 2. Dua “kotak Docker” yang harus hidup

Sistem penyimpanan antrian **terpisah** dari sistem gudang Hadoop; keduanya dihidupkan lewat Compose.

```mermaid
flowchart TB
  subgraph stackA["Berkas: docker-compose-kafka.yml"]
    ZK[Zookeeper port 2181]
    KB[kafka-broker port 9092 dan 29092]
    ZK --- KB
  end
  subgraph stackB["Berkas: docker-compose-hadoop.yml"]
    NN[NameNode UI 9870 RPC 9000]
    DN1[datanode1]
    DN2[datanode2]
    DN3[datanode3]
    RM[ResourceManager UI 8088]
    NM[NodeManager]
    NN --- DN1
    NN --- DN2
    NN --- DN3
    RM --- NM
  end
  stackA -->|pesan lewat KAFKA_BOOTSTRAP| PY[Program Python di host]
  stackB -->|arsip lewat WebHDFS atau docker exec| PY
```

---

### 3. Setelah container aktif: skrip init membuat “rak” di Kafka dan HDFS

Skrip `scripts/init-infra.sh` **membuat dua topik** kalau belum ada, dan **folder HDFS** untuk tiga jenis isi.

```mermaid
flowchart TD
  INIT[init-infra.sh]
  INIT --> T1[Topik airquality-api partisi 1 replikasi 1]
  INIT --> T2[Topik airquality-rss partisi 1 replikasi 1]
  INIT --> H1["Folder HDFS /data/airquality/api"]
  INIT --> H2["Folder HDFS /data/airquality/rss"]
  INIT --> H3["Folder HDFS /data/airquality/hasil"]
```

Catatan README: **topik tidak dibuat otomatis** oleh broker (`KAFKA_AUTO_CREATE_TOPICS_ENABLE=false`) sehingga **harus** lewat inisialisasi seperti ini.

---

### 4. Alur isi antrian: dua sumber → dua jenis pengirim → Kafka

```mermaid
flowchart TD
  AQ[AQICN di internet atau simulator]
  FEED[Situs berita lewat RSS]
  PA[kafka/producer_api.py]
  PR[kafka/producer_rss.py]
  TA[(Topik airquality-api)]
  TR[(Topik airquality-rss)]
  AQ --> PA
  FEED --> PR
  PA --> TA
  PR --> TR
```

---

### 5. Isi perut pengirim angka (producer API)

```mermaid
flowchart TD
  START([Jalan terus sampai dihentikan]) --> WAIT[Jeda polling default 900 dtk 15 menit]
  WAIT --> LOOP{Untuk tiap dari 5 kota GK}
  LOOP --> KOTA[Surabaya Malang Sidoarjo Gresik Mojokerto]
  KOTA --> CALL[Panggil AQICN pakai slug atau simulator]
  CALL --> KEY[Kunci Kafka slug kota contoh surabaya]
  KEY --> SEND[Kirim Kafka acks all plus retry]
  SEND --> START
```

Token `AQICN_TOKEN` dan `FORCE_SIMULATOR` mengatur pakai sumber sungguhan atau simulator (`README.md` / `.env`).

---

### 6. Isi perut pengirim berita (producer RSS)

```mermaid
flowchart TD
  START2([Jalan terus]) --> WAIT2[Jeda dari POLL_INTERVAL_SEC_RSS misalnya 720 jam]
  WAIT2 --> FETCH[Ambil beberapa feed RSS dari RSS_FEEDS atau default media nasional]
  FETCH --> PARSE[Parse judul link ringkasan waktu terbit]
  PARSE --> KW{Judul atau ringkasan mengandung RSS_KEYWORDS?}
  KW -->|tidak cukup| FALL[Ambil fallback top N RSS_FALLBACK_TOPN]
  KW -->|lolos| DEDUP{Sudah pernah dikirim KEY hash link di seen_ids?}
  FALL --> DEDUP
  DEDUP -->|sudah| START2
  DEDUP -->|baru| HASH[Kunci Kafka = MD5 dari URL]
  HASH --> SEND2[Kirim JSON konsisten + timestamp ingest]
  SEND2 --> SAVE[Update berkas seen_ids.json max RSS_MAX_SEEN_IDS]
  SAVE --> START2
```

---

### 7. Kafka: topik, kunci, dan grup konsumen (ringkas)

```mermaid
flowchart LR
  subgraph topicApi["Topik airquality-api"]
    KA[Kunci = city slug]
  end
  subgraph topicRss["Topik airquality-rss"]
    KR[Kunci = MD5 link]
  end
  topicApi --> GA[Grup airquality-consumer-api]
  topicRss --> GR[Grup airquality-consumer-rss]
  GA --> C[consumer_to_hdfs.py utas A]
  GR --> C2[consumer_to_hdfs.py utas B]
```

---

### 8. Penerima: dua utas, buffer, flush ke HDFS + cermin dashboard

```mermaid
flowchart TD
  KAFA[(Kafka)]
  KAFA --> TH1[Utas 1 baca topik API grup API]
  KAFA --> TH2[Utas 2 baca topik RSS grup RSS]
  TH1 --> BUF1[Buffer memori baris JSON]
  TH2 --> BUF2[Buffer memori baris JSON]
  BUF1 --> TRIG1{Waktu BUFFER_FLUSH_SEC capai atau jumlah BUFFER_MAX_RECORDS capai?}
  BUF2 --> TRIG2{Waktu BUFFER_FLUSH_SEC capai atau jumlah BUFFER_MAX_RECORDS capai?}
  TRIG1 -->|ya| FL1[Nama berkas YYYY-MM-DD_HH-MM-SS.json]
  TRIG2 -->|ya| FL2[Nama berkas sama pola timestamp]
  FL1 --> HDFS1["HDFS BASE DIR /api/"]
  FL2 --> HDFS2["HDFS BASE DIR /rss/"]
  FL1 --> M1["Cermin dashboard/data/live_api.json"]
  FL2 --> M2["Cermin dashboard/data/live_rss.json"]
```

Default dari kode: `BUFFER_FLUSH_SEC` 180 detik (3 menit), `BUFFER_MAX_RECORDS` 200, `auto_offset_reset=earliest`. Tulis HDFS default **`docker exec` ke kontainer namenode** agar aman di WSL2 (README menjabarkan `HDFS_WRITE_MODE`).

---

### 9. Peta folder HDFS dan salinan lokal dashboard

```mermaid
flowchart TB
  subgraph hdfs["HDFS Hadoop"]
    P1["/data/airquality/api/*.json NDJSON"]
    P2["/data/airquality/rss/*.json NDJSON"]
    P3["/data/airquality/hasil/ output Spark"]
  end
  subgraph lokal["Disk proyek dashboard/data"]
    L1[live_api.json]
    L2[live_rss.json]
    L3[spark_results.json]
  end
  hdfs --> |replikasi dfs.replication=2| REPL[Setiap potong data punya 2 salinan di DataNode berbeda]
  lokal --> FLASK[dibaca Flask]
```

---

### 10. Rangka Hadoop penyimpanan (siapa menyimpan apa)

```mermaid
flowchart TB
  NN[NameNode metadata jembatan 9870 dan 9000]
  NN --> D1[datanode1 rak blok]
  NN --> D2[datanode2 rak blok]
  NN --> D3[datanode3 rak blok]
  D1 -.-> NOTE[README dfs.replication=2 di hadoop.env]
  D2 -.-> NOTE
  D3 -.-> NOTE
```

---

### 11. Spark: dari arsip hingga tiga jawaban bisnis

```mermaid
flowchart TD
  IN[Baca /data/airquality/api berkas json] --> TIME[Pilih waktu observed_at lalu fallback timestamp_ingest]
  TIME --> CAT[Map AQI ke kategori Baik Sedang Tidak Sehat Berbahaya]
  CAT --> A1[Analisis 1 distribusi kategori per kota]
  CAT --> A2[Analisis 2 rata-rata AQI per kota per jam]
  CAT --> A3[Analisis 3 ranking kota rata-rata dan peristiwa AQI lebih dari 100]
  A1 & A2 & A3 --> OUT1[Tulis ke HDFS /hasil/]
  A1 & A2 & A3 --> OUT2[Tulis spark_results.json untuk dashboard]
```

---

### 12. Flask dashboard: sumber data dan rute

```mermaid
flowchart TD
  R0["GET / halaman index.html"]
  R1["GET /api/data JSON gabungan"]
  R2["GET /api/status alias kompatibilitas"]
  R1 --> SRC1[Baca spark_results.json normalisasi]
  R1 --> SRC2[Baca live_api.json]
  R1 --> SRC3[Baca live_rss.json]
  SRC1 & SRC2 & SRC3 --> MERGE[Satukan payload]
  MERGE --> NODATA1{Tidak ada file?}
  NODATA1 -->|ya| DEMO[Fallback data demo]
  NODATA1 -->|tidak| JSON[Jawaban JSON]
  R0 --> FE[Tampilan Chart.js]
  FE --> REFRESH[Fetch ulang sekitar 30 detik]
  FE --> THEME[Tema terang gelap di localStorage browser]
```

---

### 13. Urutan waktu: satu kali “gelombang” data dari sumber sampai layar

```mermaid
sequenceDiagram
  participant AQ as "AQICN atau simulator"
  participant PA as producer_api
  participant K as Kafka broker
  participant C as consumer_to_hdfs
  participant H as HDFS
  participant L as "File JSON lokal dashboard"
  participant SP as "Notebook Spark"
  participant F as Flask
  participant BR as Browser
  AQ->>PA: angka AQI
  PA->>K: kirim topik API
  K->>C: konsumsi pesan
  C->>H: flush batch API
  C->>L: tulis live_api.json
  SP->>H: baca arsip API
  SP->>H: tulis hasil
  SP->>L: tulis spark_results.json
  BR->>F: GET /
  BR->>F: GET /api/data
  F->>L: baca tiga sumber
  F->>BR: JSON + halaman grafi
```

*(Pengirim RSS mengikuti jalur paralel yang sama ke topik lain.)*

---

### 14. Menyalakan proyek: urutan operasional (bukan perintah)

```mermaid
flowchart TD
  S0[Clone repo] --> S1[vendor Python venv + pip requirements.txt]
  S1 --> S2[Salin .env.example ke .env isi token interval dsb]
  S2 --> S3[scripts/start-stack atau compose Kafka lalu Hadoop]
  S3 --> S4[scripts/init-infra topik + folder HDFS]
  S4 --> S5[scripts/sanity-check]
  S5 --> S6[scripts/run-producers API dan RSS]
  S6 --> S7[scripts/run-consumer]
  S7 --> S8[Jupyter buka spark/analysis.ipynb jalankan sel simpan output]
  S8 --> S9[scripts/run-dashboard buka browser]
```

---

### 15. Peta berkas penting di repositori

```mermaid
flowchart LR
  subgraph root["Akar repo"]
    README[README.md panduan penuh]
    CHECK[CHECKLIST.md progres tim]
    DC1[docker-compose-kafka.yml]
    DC2[docker-compose-hadoop.yml]
    HENV[hadoop.env replikasi dsb]
    ENVex[.env.example]
    REQ[requirements.txt]
  end
  subgraph kode["Kode utama"]
    K[kafka/ producers consumer]
    S[spark/ analysis.ipynb]
    D[dashboard/ app.py data templates]
    SCR[scripts/ start init run check]
  end
  root --> kode
```

---

## Cerita naratif singkat (mengikut nomor diagram)

1. **Luar** memberi angka AQI dan berita **RSS**.
2. **`producer_api.py`** lima kota, polling ~15 menit; **`producer_rss.py`** feed terkonfigurasi, filter kata kunci, dedup, interval RSS dari `.env` (mis. ~720 jam).
3. **Kafka** menyimpan dua aliran di **topik terpisah** dengan **kunci** berbeda.
4. **`consumer_to_hdfs.py`** dua **utas**, dua **grup konsumen**, buffer lalu **flush** ke **NDJSON** di HDFS dan ke **`live_*.json`**.
5. **`spark/analysis.ipynb`** membaca arsip API, menghasilkan **tiga analisis** dan menulis **HDFS hasil** + **`spark_results.json`**.
6. **`dashboard/app.py`** menyajikan **`/`** dan **`/api/data`** menggabungkan Spark + live; **Chart.js** dan **muat ulang ~30 dtk**; **fallback** bila file belum ada.

---

## Folder penting (tabel ringkas)

| Path | Fungsi awam |
| --- | --- |
| `README.md` | Panduan penuh |
| `CHECKLIST.md` | Progres tugas |
| `docker-compose-kafka.yml` | Kafka + Zookeeper |
| `docker-compose-hadoop.yml` | HDFS + YARN |
| `hadoop.env` | Setelan Hadoop termasuk replikasi |
| `kafka/` | Pengirim dan penerima |
| `spark/` | Notebook hitung |
| `dashboard/` | Web |
| `scripts/` | Menyalakan dan menjalankan |
| `.env` | Pengaturan runtime (dari `.env.example`) |

---

## Kesimpulan

**AirQuality Alert** adalah rantai: **ambil** → **antrikan (Kafka)** → **arsipkan (HDFS)** → **cerminkan ke file dashboard** → **hitung (Spark)** → **tampilkan (Flask + browser)**. Diagram di atas sengaja **bertingkat** supaya tidak ada langkah kecil yang hilang: dari container, init topik, perilaku tiap pengirim, buffer penerima, path simpan, hingga rute web.

Jika salah satu diagram tidak tampil di penampil Markdown Anda, kemungkinan versi Mermaid lama — buka di GitHub atau VS Code dengan ekstensi Mermaid, atau laporkan blok yang error agar disederhanakan.
