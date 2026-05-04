<!-- markdownlint-disable MD012 MD033 MD024 -->

# Persentasi Arsitektur - AirQuality Alert

Dokumen ini adalah naskah presentasi arsitektur untuk proyek **AirQuality Alert: Monitoring Kualitas Udara Jawa Timur**.

File ini menggabungkan informasi utama dari `README.md` dengan seluruh diagram Mermaid dari `ARCHITECTURE_A1.md`. Tujuannya adalah agar pembaca dapat memahami setiap kotak, setiap panah, setiap alur data, dan alasan desain tanpa harus membuka banyak file secara bersamaan.

> Catatan: ekstensi file mengikuti permintaan, yaitu `persentasi.ms`. Isi file tetap menggunakan format Markdown dengan blok Mermaid agar diagram dapat dirender oleh viewer yang mendukung Mermaid.

---

## Cara Membaca Dokumen Ini

Dokumen ini disusun seperti naskah presentasi. Setiap bagian berisi diagram, tujuan diagram, penjelasan semua kotak, penjelasan semua flow, lalu ringkasan pesan yang harus disampaikan saat presentasi.

| Bagian | Isi |
| --- | --- |
| Diagram | Blok Mermaid yang dapat dirender. |
| Tujuan diagram | Apa yang ingin dijelaskan oleh diagram tersebut. |
| Penjelasan kotak | Makna setiap node, service, file, atau layer. |
| Penjelasan flow | Makna setiap panah dan urutan kerja. |
| Narasi presentasi | Kalimat yang dapat dipakai saat menjelaskan ke dosen/audience. |


## Ringkasan Sistem Satu Menit

AirQuality Alert adalah pipeline Big Data yang mengalirkan data kualitas udara dan berita lingkungan dari sumber eksternal sampai dashboard web.

- `producer_api.py` mengambil AQI dari AQICN atau simulator.
- `producer_rss.py` mengambil berita dari RSS, membersihkan summary, dan mencegah duplikasi.
- Kafka memisahkan producer dari consumer melalui dua topic: `airquality-api` dan `airquality-rss`.
- `consumer_to_hdfs.py` membaca Kafka, melakukan buffer, menulis data ke HDFS, dan membuat mirror JSON untuk dashboard.
- HDFS menyimpan raw data dan hasil Spark di `/data/airquality`.
- `spark/analysis.ipynb` menghitung tiga analisis utama.
- `dashboard/app.py` menyajikan JSON ke frontend.
- `index.html` dan `style.css` menampilkan dashboard yang auto-refresh.


## Matriks Komponen Utama

| Lapisan | Komponen | Tanggung Jawab | Output |
| --- | --- | --- | --- |
| Sumber data | AQICN API | Memberi data kualitas udara nyata. | Payload AQI. |
| Sumber data | Simulator AQI | Memberi data cadangan saat API tidak tersedia. | Payload AQI simulator. |
| Sumber data | RSS Feeds | Memberi konteks berita lingkungan. | Entry RSS. |
| Ingestion | `producer_api.py` | Polling AQI dan kirim ke Kafka. | Message `airquality-api`. |
| Ingestion | `producer_rss.py` | Parse RSS, filter keyword, dedup. | Message `airquality-rss`. |
| Broker | Kafka | Menahan dan memisahkan aliran data. | Topic log. |
| Sink | `consumer_to_hdfs.py` | Baca Kafka, buffer, flush, mirror. | File HDFS dan JSON dashboard. |
| Storage | HDFS | Menyimpan data historis. | NDJSON raw dan Parquet hasil. |
| Analytics | Spark Notebook | Menghitung distribusi, jam puncak, ranking. | Parquet dan `spark_results.json`. |
| Presentation | Flask Dashboard | Menyajikan API dan halaman web. | Dashboard browser. |


## 1. Peta Besar Sistem

```mermaid
%%{init: {"theme":"base","themeVariables":{"fontFamily":"Inter, Arial","primaryColor":"#dbeafe","primaryTextColor":"#0f172a","primaryBorderColor":"#2563eb","lineColor":"#334155","secondaryColor":"#dcfce7","tertiaryColor":"#fef3c7"}}}%%
flowchart LR
    subgraph Sumber["Sumber Data Eksternal"]
        AQICN["AQICN API<br/>Data AQI real-time"]
        SIM["Simulator AQI<br/>Fallback offline"]
        RSS["RSS Feeds<br/>Kontan, Liputan6, Tempo, CNBC, CNN, Jawa Pos"]
    end

    subgraph Ingest["Lapisan Ingestion Python"]
        APIProducer["producer_api.py<br/>Polling AQI<br/>Key: city_slug"]
        RSSProducer["producer_rss.py<br/>Parse RSS<br/>Dedup MD5 URL"]
    end

    subgraph Kafka["Apache Kafka"]
        TopicAPI[("topic: airquality-api")]
        TopicRSS[("topic: airquality-rss")]
    end

    subgraph Sink["Consumer dan Sink"]
        Consumer["consumer_to_hdfs.py<br/>2 thread<br/>buffer<br/>manual commit"]
        Mirror["dashboard/data<br/>live_api.json<br/>live_rss.json"]
    end

    subgraph Lake["Hadoop HDFS"]
        HDFSAPI[("/data/airquality/api")]
        HDFSRSS[("/data/airquality/rss")]
        HDFSResult[("/data/airquality/hasil")]
    end

    subgraph Analytics["Apache Spark"]
        Notebook["spark/analysis.ipynb<br/>3 analisis utama"]
        SparkJSON["spark_results.json"]
    end

    subgraph Presentation["Presentation Layer"]
        Flask["dashboard/app.py<br/>/api/data<br/>/api/status"]
        UI["index.html + style.css<br/>Chart.js<br/>auto-refresh 30s"]
        Browser["Browser pengguna"]
    end

    AQICN --> APIProducer
    SIM --> APIProducer
    RSS --> RSSProducer
    APIProducer --> TopicAPI
    RSSProducer --> TopicRSS
    TopicAPI --> Consumer
    TopicRSS --> Consumer
    Consumer --> HDFSAPI
    Consumer --> HDFSRSS
    Consumer --> Mirror
    HDFSAPI --> Notebook
    Notebook --> HDFSResult
    Notebook --> SparkJSON
    Mirror --> Flask
    SparkJSON --> Flask
    Flask --> UI
    UI --> Browser

    classDef source fill:#e0f2fe,stroke:#0284c7,color:#0f172a,stroke-width:2px;
    classDef ingest fill:#dcfce7,stroke:#16a34a,color:#0f172a,stroke-width:2px;
    classDef kafka fill:#fef3c7,stroke:#d97706,color:#0f172a,stroke-width:2px;
    classDef sink fill:#fae8ff,stroke:#9333ea,color:#0f172a,stroke-width:2px;
    classDef hdfs fill:#fee2e2,stroke:#dc2626,color:#0f172a,stroke-width:2px;
    classDef spark fill:#ede9fe,stroke:#7c3aed,color:#0f172a,stroke-width:2px;
    classDef presentation fill:#f1f5f9,stroke:#475569,color:#0f172a,stroke-width:2px;

    class AQICN,SIM,RSS source;
    class APIProducer,RSSProducer ingest;
    class TopicAPI,TopicRSS kafka;
    class Consumer,Mirror sink;
    class HDFSAPI,HDFSRSS,HDFSResult hdfs;
    class Notebook,SparkJSON spark;
    class Flask,UI,Browser presentation;
```


### Tujuan Diagram

Diagram ini adalah peta utama seluruh sistem. Diagram ini menjelaskan semua lapisan dari sumber data sampai dashboard yang dibuka pengguna.


### Penjelasan Semua Kotak

| Kotak / Node | Penjelasan |
| --- | --- |
| `Sumber Data Eksternal` | Berisi `AQICN API`, `Simulator AQI`, dan `RSS Feeds`. AQICN adalah sumber data kualitas udara nyata. Simulator adalah cadangan jika token kosong atau API gagal. RSS Feeds adalah sumber konteks berita dari Kontan, Liputan6, Tempo, CNBC Indonesia, CNN Indonesia, dan Jawa Pos. |
| `Lapisan Ingestion Python` | Berisi `producer_api.py` dan `producer_rss.py`. Dua file ini bertugas mengambil data dari luar, membentuk payload JSON, lalu mengirimkannya ke Kafka. |
| `Apache Kafka` | Berisi topic `airquality-api` dan `airquality-rss`. Kafka menjadi antrian data agar producer tidak langsung bergantung pada HDFS atau dashboard. |
| `Consumer dan Sink` | Berisi `consumer_to_hdfs.py` dan mirror `dashboard/data`. Consumer membaca Kafka, melakukan buffer, menulis ke HDFS, dan membuat file JSON lokal untuk dashboard. |
| `Hadoop HDFS` | Berisi path `/data/airquality/api`, `/data/airquality/rss`, dan `/data/airquality/hasil`. Ini adalah gudang data historis. |
| `Apache Spark` | Berisi `spark/analysis.ipynb` dan `spark_results.json`. Spark membaca data historis dari HDFS, menghitung analisis, lalu menulis hasil. |
| `Presentation Layer` | Berisi `dashboard/app.py`, `index.html + style.css`, dan browser pengguna. Layer ini mengubah data hasil pipeline menjadi halaman dashboard. |


### Penjelasan Semua Flow

- AQICN dan Simulator mengarah ke `producer_api.py` karena keduanya adalah sumber alternatif untuk data AQI.
- RSS Feeds mengarah ke `producer_rss.py` karena berita diproses oleh producer terpisah.
- Dua producer mengarah ke topic Kafka yang berbeda agar aliran angka AQI dan aliran berita tidak bercampur.
- Dua topic Kafka mengarah ke `consumer_to_hdfs.py` karena satu consumer membaca kedua topic dengan dua thread.
- Consumer mengarah ke HDFS dan mirror dashboard karena ia menulis data historis sekaligus snapshot cepat.
- Spark membaca HDFS API, lalu menulis hasil ke HDFS hasil dan `spark_results.json`.
- Flask membaca mirror live dan hasil Spark, lalu frontend mengambil data dari Flask.


### Narasi Presentasi

Inti diagram ini adalah pemisahan tanggung jawab. Producer mengambil data, Kafka menahan data, consumer menyimpan data, HDFS mengarsipkan data, Spark menganalisis data, dan dashboard menyajikan data.

Kalimat presentasi yang disarankan:

> Diagram ini menunjukkan bahwa sistem tidak dibuat sebagai satu program besar, tetapi sebagai rangkaian komponen dengan tanggung jawab yang jelas. Aliran data bergerak bertahap dari sumber, masuk ke Kafka, disimpan di HDFS, dianalisis Spark, lalu disajikan lewat dashboard Flask.

---

## 2. Topologi Deployment Lokal

```mermaid
%%{init: {"theme":"base","themeVariables":{"fontFamily":"Inter, Arial","primaryColor":"#f8fafc","primaryBorderColor":"#0f172a","lineColor":"#334155"}}}%%
flowchart TB
    subgraph Host["Host Linux / WSL2"]
        Venv["Python .venv<br/>requirements.txt"]
        Producers["Python Producers<br/>producer_api.py<br/>producer_rss.py"]
        ConsumerPy["Python Consumer<br/>consumer_to_hdfs.py"]
        NotebookHost["Jupyter / Spark Notebook<br/>analysis.ipynb"]
        DashboardHost["Flask Dashboard<br/>dashboard/app.py<br/>port 5000"]
    end

    subgraph KafkaCompose["docker-compose-kafka.yml"]
        ZK["zookeeper<br/>2181"]
        Broker["kafka-broker<br/>9092 external<br/>29092 internal"]
    end

    subgraph HadoopCompose["docker-compose-hadoop.yml"]
        NN["namenode<br/>9870 Web UI<br/>9000 RPC"]
        DN1["datanode1<br/>9864"]
        DN2["datanode2<br/>9865 -> 9864"]
        DN3["datanode3<br/>9866 -> 9864"]
        RM["resourcemanager<br/>8088"]
        NM["nodemanager"]
    end

    Venv --> Producers
    Venv --> ConsumerPy
    Venv --> NotebookHost
    Venv --> DashboardHost
    Producers -->|"localhost:9092"| Broker
    ConsumerPy -->|"localhost:9092"| Broker
    ConsumerPy -->|"docker exec namenode"| NN
    NotebookHost -->|"hdfs://localhost:9000"| NN
    NotebookHost -->|"fallback docker exec"| NN
    DashboardHost -->|"reads JSON"| Venv

    ZK --> Broker
    NN --> DN1
    NN --> DN2
    NN --> DN3
    RM --> NM
    RM --> NN

    classDef host fill:#dbeafe,stroke:#2563eb,stroke-width:2px,color:#0f172a;
    classDef kafka fill:#fef3c7,stroke:#d97706,stroke-width:2px,color:#0f172a;
    classDef hadoop fill:#dcfce7,stroke:#16a34a,stroke-width:2px,color:#0f172a;

    class Venv,Producers,ConsumerPy,NotebookHost,DashboardHost host;
    class ZK,Broker kafka;
    class NN,DN1,DN2,DN3,RM,NM hadoop;
```


### Tujuan Diagram

Diagram ini menjelaskan bagaimana aplikasi berjalan di mesin lokal Linux atau WSL2.


### Penjelasan Semua Kotak

| Kotak / Node | Penjelasan |
| --- | --- |
| `Host Linux / WSL2` | Menjalankan virtual environment Python, producer, consumer, notebook Spark, dan dashboard Flask. |
| `Python .venv` | Tempat dependency dari `requirements.txt` diinstal. Semua program Python proyek idealnya berjalan dari environment ini. |
| `Python Producers` | Proses `producer_api.py` dan `producer_rss.py` berjalan di host, bukan di container. |
| `Python Consumer` | Proses `consumer_to_hdfs.py` juga berjalan di host dan mengakses Kafka serta HDFS. |
| `Jupyter / Spark Notebook` | Notebook dijalankan dari host dan membaca HDFS melalui `hdfs://localhost:9000` atau fallback docker exec. |
| `Flask Dashboard` | Dashboard Flask berjalan pada host dan membuka port 5000. |
| `docker-compose-kafka.yml` | Menjalankan Zookeeper dan Kafka broker. |
| `docker-compose-hadoop.yml` | Menjalankan NameNode, tiga DataNode, ResourceManager, dan NodeManager. |


### Penjelasan Semua Flow

- Producer dan consumer mengakses Kafka melalui `localhost:9092` karena Kafka mengiklankan listener eksternal untuk host.
- Consumer menulis HDFS menggunakan `docker exec namenode` sebagai strategi default yang stabil di WSL2.
- Notebook mencoba membaca HDFS melalui `hdfs://localhost:9000`, lalu memakai fallback jika hostname DataNode bermasalah.
- Dashboard membaca file JSON lokal di folder `dashboard/data`, bukan langsung membaca Kafka atau HDFS.


### Narasi Presentasi

Diagram ini penting untuk menjelaskan batas antara proses host dan container. Infrastruktur berat berjalan di Docker, sedangkan logika proyek berjalan sebagai Python lokal.

Kalimat presentasi yang disarankan:

> Diagram ini menunjukkan bahwa sistem tidak dibuat sebagai satu program besar, tetapi sebagai rangkaian komponen dengan tanggung jawab yang jelas. Aliran data bergerak bertahap dari sumber, masuk ke Kafka, disimpan di HDFS, dianalisis Spark, lalu disajikan lewat dashboard Flask.

---

## 3. Sequence Diagram Ingestion AQI

```mermaid
%%{init: {"theme":"base","themeVariables":{"fontFamily":"Inter, Arial","actorBkg":"#dbeafe","actorBorder":"#2563eb","activationBkgColor":"#fef3c7","activationBorderColor":"#d97706","sequenceNumberColor":"#0f172a"}}}%%
sequenceDiagram
    autonumber
    participant Timer as Polling Timer
    participant Producer as producer_api.py
    participant AQICN as AQICN API
    participant Sim as Simulator
    participant Kafka as Kafka topic airquality-api

    Timer->>Producer: trigger setiap POLL_INTERVAL_SEC
    loop Untuk setiap kota
        Producer->>AQICN: GET /feed/{city_slug}?token=...
        alt AQICN sukses dan valid
            AQICN-->>Producer: payload AQI
            Producer->>Producer: normalisasi field
        else AQICN gagal / token kosong / FORCE_SIMULATOR
            Producer->>Sim: simulate_event(city)
            Sim-->>Producer: payload simulator
        end
        Producer->>Producer: tambah city, city_slug, timestamp_ingest
        Producer->>Kafka: send(key=city_slug, value=json)
    end
    Producer->>Kafka: flush(timeout=15)
```


### Tujuan Diagram

Diagram ini menjelaskan urutan kejadian saat data AQI dikirim ke Kafka.


### Penjelasan Semua Kotak

| Kotak / Node | Penjelasan |
| --- | --- |
| `Polling Timer` | Pemicu periodik berdasarkan `POLL_INTERVAL_SEC`, default 900 detik. |
| `producer_api.py` | Program utama yang mengatur pengambilan data AQI, fallback simulator, normalisasi field, dan pengiriman Kafka. |
| `AQICN API` | Sumber data kualitas udara nyata jika token tersedia dan response valid. |
| `Simulator` | Sumber cadangan jika token kosong, request gagal, atau `FORCE_SIMULATOR=1`. |
| `Kafka topic airquality-api` | Topic tujuan untuk seluruh event AQI. |


### Penjelasan Semua Flow

- Timer memicu producer sesuai interval.
- Producer melakukan loop untuk setiap kota: Surabaya, Malang, Sidoarjo, Gresik, dan Mojokerto.
- Producer mencoba request ke AQICN dengan slug kota.
- Jika AQICN sukses, payload dinormalisasi.
- Jika AQICN gagal, simulator membuat payload realistis.
- Producer menambahkan `city`, `city_slug`, dan `timestamp_ingest`.
- Producer mengirim message ke Kafka memakai key `city_slug`.
- Setelah satu siklus, producer melakukan flush agar message benar-benar dikirim.


### Narasi Presentasi

Ingestion AQI dirancang tahan gangguan. Demo tidak berhenti hanya karena API eksternal tidak tersedia.

Kalimat presentasi yang disarankan:

> Diagram ini menunjukkan bahwa sistem tidak dibuat sebagai satu program besar, tetapi sebagai rangkaian komponen dengan tanggung jawab yang jelas. Aliran data bergerak bertahap dari sumber, masuk ke Kafka, disimpan di HDFS, dianalisis Spark, lalu disajikan lewat dashboard Flask.

---

## 4. Sequence Diagram Ingestion RSS

```mermaid
%%{init: {"theme":"base","themeVariables":{"fontFamily":"Inter, Arial","actorBkg":"#dcfce7","actorBorder":"#16a34a","activationBkgColor":"#fae8ff","activationBorderColor":"#9333ea"}}}%%
sequenceDiagram
    autonumber
    participant Timer as Polling Timer
    participant Producer as producer_rss.py
    participant Feed as RSS Feed
    participant Seen as seen_ids.json
    participant Kafka as Kafka topic airquality-rss

    Timer->>Producer: trigger setiap POLL_INTERVAL_SEC_RSS
    Producer->>Seen: load_seen_ids()
    loop Untuk setiap RSS_FEEDS
        Producer->>Feed: feedparser.parse(url)
        Feed-->>Producer: entries
        Producer->>Producer: strip_html(summary)
        Producer->>Producer: hash_url(link)
        Producer->>Seen: cek id sudah pernah dikirim
        alt berita relevan keyword
            Producer->>Kafka: send(key=id, value=json)
            Producer->>Seen: add id
        else tidak ada relevan tetapi fallback aktif
            Producer->>Kafka: send top-N fallback
            Producer->>Seen: add id
        end
    end
    Producer->>Kafka: flush(timeout=15)
    Producer->>Seen: save_seen_ids() atomic
```


### Tujuan Diagram

Diagram ini menjelaskan bagaimana berita RSS dibaca, difilter, didedup, lalu dikirim ke Kafka.


### Penjelasan Semua Kotak

| Kotak / Node | Penjelasan |
| --- | --- |
| `Polling Timer` | Pemicu periodik berdasarkan `POLL_INTERVAL_SEC_RSS`, default 300 detik. |
| `producer_rss.py` | Program yang membaca feed, membersihkan summary, menghitung hash link, dan mengirim message. |
| `RSS Feed` | Sumber berita dari URL feed yang didefinisikan di default kode atau `RSS_FEEDS`. |
| `seen_ids.json` | File runtime yang menyimpan ID berita yang sudah pernah dikirim. |
| `Kafka topic airquality-rss` | Topic tujuan event RSS. |


### Penjelasan Semua Flow

- Producer memuat `seen_ids.json` saat siklus dimulai.
- Producer membaca setiap feed dengan `feedparser`.
- Setiap entry dibersihkan dari HTML dan dibuat ID berdasarkan MD5 link.
- Jika ID sudah ada, berita dilewati agar tidak duplikat.
- Jika berita relevan dengan keyword, berita dikirim ke Kafka.
- Jika tidak ada yang relevan, fallback Top-N dapat dikirim untuk menjaga dashboard tetap terisi.
- Setelah kirim, ID berita disimpan kembali secara atomic.


### Narasi Presentasi

RSS ingestion menyeimbangkan relevansi dan kebutuhan demo. Sistem mencoba memilih berita lingkungan, tetapi tetap punya fallback agar panel berita tidak kosong.

Kalimat presentasi yang disarankan:

> Diagram ini menunjukkan bahwa sistem tidak dibuat sebagai satu program besar, tetapi sebagai rangkaian komponen dengan tanggung jawab yang jelas. Aliran data bergerak bertahap dari sumber, masuk ke Kafka, disimpan di HDFS, dianalisis Spark, lalu disajikan lewat dashboard Flask.

---

## 5. Sequence Diagram Consumer ke HDFS

```mermaid
%%{init: {"theme":"base","themeVariables":{"fontFamily":"Inter, Arial","actorBkg":"#fef3c7","actorBorder":"#d97706","activationBkgColor":"#fee2e2","activationBorderColor":"#dc2626"}}}%%
sequenceDiagram
    autonumber
    participant KafkaAPI as topic airquality-api
    participant KafkaRSS as topic airquality-rss
    participant Consumer as consumer_to_hdfs.py
    participant Buffer as In-memory Buffer
    participant HDFS as Hadoop HDFS
    participant Mirror as dashboard/data

    par Thread API
        KafkaAPI->>Consumer: poll messages
        Consumer->>Buffer: append API records
    and Thread RSS
        KafkaRSS->>Consumer: poll messages
        Consumer->>Buffer: append RSS records
    end

    alt BUFFER_MAX_RECORDS tercapai
        Consumer->>HDFS: write NDJSON batch
        Consumer->>Mirror: update live_api/live_rss
        Consumer->>KafkaAPI: commit offset
        Consumer->>KafkaRSS: commit offset
    else BUFFER_FLUSH_SEC tercapai
        Consumer->>HDFS: write NDJSON batch
        Consumer->>Mirror: update live_api/live_rss
        Consumer->>KafkaAPI: commit offset
        Consumer->>KafkaRSS: commit offset
    else HDFS write gagal
        Consumer->>Buffer: pertahankan buffer
        Consumer-->>KafkaAPI: offset belum commit
        Consumer-->>KafkaRSS: offset belum commit
    end
```


### Tujuan Diagram

Diagram ini menjelaskan bagaimana consumer membaca dua topic Kafka dan menyimpan data dengan aman.


### Penjelasan Semua Kotak

| Kotak / Node | Penjelasan |
| --- | --- |
| `topic airquality-api` | Topic berisi event AQI. |
| `topic airquality-rss` | Topic berisi event RSS. |
| `consumer_to_hdfs.py` | Consumer yang menjalankan dua thread, satu untuk API dan satu untuk RSS. |
| `In-memory Buffer` | Tempat menampung record sementara sebelum ditulis sebagai batch. |
| `Hadoop HDFS` | Tujuan penyimpanan historis. |
| `dashboard/data` | Tujuan mirror JSON untuk dashboard. |


### Penjelasan Semua Flow

- Thread API membaca topic `airquality-api`.
- Thread RSS membaca topic `airquality-rss`.
- Record dari dua aliran masuk ke buffer masing-masing.
- Flush terjadi jika `BUFFER_MAX_RECORDS` tercapai atau `BUFFER_FLUSH_SEC` tercapai.
- Pada flush sukses, data ditulis ke HDFS sebagai NDJSON.
- Mirror dashboard diperbarui agar dashboard punya snapshot terbaru.
- Offset Kafka baru di-commit setelah write sukses.
- Jika write gagal, buffer dipertahankan dan offset tidak di-commit.


### Narasi Presentasi

Desain commit setelah flush mencegah data dianggap selesai sebelum benar-benar tersimpan.

Kalimat presentasi yang disarankan:

> Diagram ini menunjukkan bahwa sistem tidak dibuat sebagai satu program besar, tetapi sebagai rangkaian komponen dengan tanggung jawab yang jelas. Aliran data bergerak bertahap dari sumber, masuk ke Kafka, disimpan di HDFS, dianalisis Spark, lalu disajikan lewat dashboard Flask.

---

## 6. Struktur Penyimpanan HDFS

```mermaid
%%{init: {"theme":"base","themeVariables":{"fontFamily":"Inter, Arial","primaryColor":"#fee2e2","primaryBorderColor":"#dc2626","lineColor":"#334155"}}}%%
flowchart TB
    Root["/data/airquality"]
    API["api/<br/>YYYY-MM-DD_HH-MM-SS.json<br/>NDJSON AQI"]
    RSS["rss/<br/>YYYY-MM-DD_HH-MM-SS.json<br/>NDJSON berita"]
    Hasil["hasil/"]
    Dist["distribusi_kategori/<br/>Parquet"]
    Avg["avg_aqi_per_jam/<br/>Parquet"]
    Rank["ranking_kota/<br/>Parquet"]

    Root --> API
    Root --> RSS
    Root --> Hasil
    Hasil --> Dist
    Hasil --> Avg
    Hasil --> Rank

    classDef root fill:#fee2e2,stroke:#dc2626,stroke-width:3px,color:#0f172a;
    classDef raw fill:#ffedd5,stroke:#ea580c,stroke-width:2px,color:#0f172a;
    classDef result fill:#dcfce7,stroke:#16a34a,stroke-width:2px,color:#0f172a;

    class Root root;
    class API,RSS raw;
    class Hasil,Dist,Avg,Rank result;
```


### Tujuan Diagram

Diagram ini menjelaskan struktur folder HDFS yang digunakan proyek.


### Penjelasan Semua Kotak

| Kotak / Node | Penjelasan |
| --- | --- |
| `/data/airquality` | Root folder data lake proyek. |
| `api` | Folder raw data AQI dalam file NDJSON per batch. |
| `rss` | Folder raw data RSS dalam file NDJSON per batch. |
| `hasil` | Folder untuk output Spark. |
| `distribusi_kategori` | Output Parquet analisis distribusi kategori AQI per kota. |
| `avg_aqi_per_jam` | Output Parquet analisis rata-rata AQI per kota per jam. |
| `ranking_kota` | Output Parquet analisis ranking kota berdasarkan AQI. |


### Penjelasan Semua Flow

- `/data/airquality` menjadi akar semua data proyek.
- Consumer menulis data mentah ke `api` dan `rss`.
- Spark menulis data hasil olahan ke `hasil`.
- Tiga subfolder hasil memisahkan output analisis agar mudah diverifikasi.


### Narasi Presentasi

Struktur ini memisahkan raw data dan processed data. Pemisahan ini membuat data lake lebih mudah dipahami.

Kalimat presentasi yang disarankan:

> Diagram ini menunjukkan bahwa sistem tidak dibuat sebagai satu program besar, tetapi sebagai rangkaian komponen dengan tanggung jawab yang jelas. Aliran data bergerak bertahap dari sumber, masuk ke Kafka, disimpan di HDFS, dianalisis Spark, lalu disajikan lewat dashboard Flask.

---

## 7. Arsitektur Spark Analysis

```mermaid
%%{init: {"theme":"base","themeVariables":{"fontFamily":"Inter, Arial","primaryColor":"#ede9fe","primaryBorderColor":"#7c3aed","secondaryColor":"#dbeafe","lineColor":"#334155"}}}%%
flowchart LR
    HDFSAPI[("HDFS<br/>/data/airquality/api/*.json")]
    ReadNative["Native read<br/>spark.read.json(hdfs://...)"]
    Fallback["Fallback read<br/>WebHDFS list<br/>docker exec hdfs dfs -cat"]
    Normalize["Normalize DataFrame<br/>city, aqi, event_ts, hour, category"]
    View["Temp View<br/>airquality"]

    A1["Analisis 1<br/>Distribusi kategori AQI"]
    A2["Analisis 2<br/>Rata-rata AQI per jam<br/>Spark SQL"]
    A3["Analisis 3<br/>Ranking kota terburuk"]

    Parquet["HDFS hasil/<br/>3 folder Parquet"]
    JSON["dashboard/data/spark_results.json"]

    HDFSAPI --> ReadNative
    ReadNative --> Normalize
    HDFSAPI -. jika native gagal .-> Fallback
    Fallback --> Normalize
    Normalize --> View
    View --> A1
    View --> A2
    View --> A3
    A1 --> Parquet
    A2 --> Parquet
    A3 --> Parquet
    A1 --> JSON
    A2 --> JSON
    A3 --> JSON

    classDef input fill:#dbeafe,stroke:#2563eb,stroke-width:2px,color:#0f172a;
    classDef process fill:#ede9fe,stroke:#7c3aed,stroke-width:2px,color:#0f172a;
    classDef output fill:#dcfce7,stroke:#16a34a,stroke-width:2px,color:#0f172a;

    class HDFSAPI input;
    class ReadNative,Fallback,Normalize,View,A1,A2,A3 process;
    class Parquet,JSON output;
```


### Tujuan Diagram

Diagram ini menjelaskan jalur data di notebook Spark.


### Penjelasan Semua Kotak

| Kotak / Node | Penjelasan |
| --- | --- |
| `HDFS /data/airquality/api/*.json` | Input historis AQI yang sudah ditulis consumer. |
| `Native read` | Percobaan baca langsung dengan `spark.read.json(hdfs://...)`. |
| `Fallback read` | Jalur cadangan menggunakan WebHDFS list dan `docker exec hdfs dfs -cat`. |
| `Normalize DataFrame` | Tahap pembentukan kolom `city`, `aqi`, `event_ts`, `hour`, dan `category`. |
| `Temp View airquality` | View SQL agar analisis Spark SQL dapat dijalankan. |
| `Analisis 1` | Distribusi kategori AQI per kota. |
| `Analisis 2` | Rata-rata AQI per jam dengan Spark SQL. |
| `Analisis 3` | Ranking kota terburuk. |
| `HDFS hasil` | Output Parquet untuk verifikasi dan penyimpanan hasil. |
| `spark_results.json` | Output JSON ringkas untuk dashboard. |


### Penjelasan Semua Flow

- Notebook mencoba native read lebih dulu.
- Jika native read gagal, notebook memakai fallback tetapi sumber data tetap HDFS.
- Data dinormalisasi agar semua analisis memakai schema konsisten.
- Temp view `airquality` dibuat untuk query SQL.
- Tiga analisis berjalan dari view yang sama.
- Hasil ditulis ke HDFS dan JSON dashboard.


### Narasi Presentasi

Spark menjadi jembatan antara raw data historis dan insight yang siap ditampilkan.

Kalimat presentasi yang disarankan:

> Diagram ini menunjukkan bahwa sistem tidak dibuat sebagai satu program besar, tetapi sebagai rangkaian komponen dengan tanggung jawab yang jelas. Aliran data bergerak bertahap dari sumber, masuk ke Kafka, disimpan di HDFS, dianalisis Spark, lalu disajikan lewat dashboard Flask.

---

## 8. Data Contract API dan RSS

```mermaid
%%{init: {"theme":"base","themeVariables":{"fontFamily":"Inter, Arial","primaryColor":"#f8fafc","primaryBorderColor":"#334155","lineColor":"#334155"}}}%%
erDiagram
    AIRQUALITY_API_EVENT {
        string city
        string city_slug
        float aqi
        float pm25
        float pm10
        float o3
        float no2
        float so2
        float co
        string dominent_pollutant
        string station_name
        string observed_at
        string timestamp_ingest
        string source
    }

    RSS_EVENT {
        string id
        string title
        string link
        string summary
        string published
        string source_feed
        boolean relevant
        string timestamp_ingest
    }

    SPARK_RESULT {
        string generated_at
        object analysis1
        object analysis2
        object analysis3
        boolean _demo
    }

    DASHBOARD_PAYLOAD {
        object spark
        object api
        object rss
        object meta
        string refreshed_at
    }

    AIRQUALITY_API_EVENT ||--o{ SPARK_RESULT : "diolah menjadi"
    RSS_EVENT ||--o{ DASHBOARD_PAYLOAD : "ditampilkan sebagai konteks"
    SPARK_RESULT ||--|| DASHBOARD_PAYLOAD : "dibaca oleh"
```


### Tujuan Diagram

Diagram ini menjelaskan struktur data utama yang bergerak antar komponen.


### Penjelasan Semua Kotak

| Kotak / Node | Penjelasan |
| --- | --- |
| `AIRQUALITY_API_EVENT` | Kontrak event AQI yang dikirim producer API dan dibaca Spark. |
| `RSS_EVENT` | Kontrak event berita yang dikirim producer RSS dan ditampilkan dashboard. |
| `SPARK_RESULT` | Kontrak hasil analisis Spark untuk dashboard. |
| `DASHBOARD_PAYLOAD` | Kontrak response `/api/data` yang dibaca frontend. |


### Penjelasan Semua Flow

- AIRQUALITY_API_EVENT diolah menjadi SPARK_RESULT.
- RSS_EVENT masuk ke DASHBOARD_PAYLOAD sebagai konteks berita.
- SPARK_RESULT dibaca oleh DASHBOARD_PAYLOAD untuk panel analisis.


### Narasi Presentasi

Data contract memastikan semua komponen punya ekspektasi field yang sama.

Kalimat presentasi yang disarankan:

> Diagram ini menunjukkan bahwa sistem tidak dibuat sebagai satu program besar, tetapi sebagai rangkaian komponen dengan tanggung jawab yang jelas. Aliran data bergerak bertahap dari sumber, masuk ke Kafka, disimpan di HDFS, dianalisis Spark, lalu disajikan lewat dashboard Flask.

---

## 9. State Machine Pipeline Runtime

```mermaid
%%{init: {"theme":"base","themeVariables":{"fontFamily":"Inter, Arial","primaryColor":"#e0f2fe","primaryBorderColor":"#0284c7","lineColor":"#334155"}}}%%
stateDiagram-v2
    [*] --> StackStopped
    StackStopped --> StackStarting: scripts/start-stack.sh
    StackStarting --> InfraReady: Kafka + Hadoop running
    InfraReady --> TopicsAndDirsReady: scripts/init-infra.sh
    TopicsAndDirsReady --> ProducersRunning: scripts/run-producers.sh
    ProducersRunning --> ConsumerRunning: scripts/run-consumer.sh
    ConsumerRunning --> HDFSReceiving: buffer flush sukses
    HDFSReceiving --> SparkReady: data cukup
    SparkReady --> SparkResultWritten: run analysis.ipynb
    SparkResultWritten --> DashboardReady: scripts/run-dashboard.sh
    DashboardReady --> Monitoring: browser fetch /api/data
    Monitoring --> Monitoring: auto-refresh 30s
    Monitoring --> PipelineStopped: scripts/stop-pipeline.sh
    PipelineStopped --> StackStopped: scripts/stop-stack.sh
```


### Tujuan Diagram

Diagram ini menjelaskan urutan status runtime dari stack mati sampai dashboard monitoring.


### Penjelasan Semua Kotak

| Kotak / Node | Penjelasan |
| --- | --- |
| `StackStopped` | Kondisi awal saat container belum berjalan. |
| `StackStarting` | Kondisi saat script start stack menjalankan Docker Compose. |
| `InfraReady` | Kafka dan Hadoop sudah running. |
| `TopicsAndDirsReady` | Topic Kafka dan folder HDFS sudah dibuat. |
| `ProducersRunning` | Producer API dan RSS sudah berjalan. |
| `ConsumerRunning` | Consumer Kafka-HDFS sudah berjalan. |
| `HDFSReceiving` | HDFS mulai menerima file batch. |
| `SparkReady` | Data cukup untuk dianalisis. |
| `SparkResultWritten` | Notebook selesai menulis hasil. |
| `DashboardReady` | Dashboard Flask berjalan. |
| `Monitoring` | Browser melakukan fetch dan auto-refresh. |
| `PipelineStopped` | Pipeline Python dihentikan. |


### Penjelasan Semua Flow

- `scripts/start-stack.sh` mengubah StackStopped menjadi StackStarting.
- `scripts/init-infra.sh` membuat topic dan folder.
- `scripts/run-producers.sh` menyalakan producer.
- `scripts/run-consumer.sh` menyalakan consumer.
- Flush sukses membuat HDFS menerima data.
- Notebook Spark membuat hasil analisis.
- Dashboard berjalan dan browser melakukan auto-refresh.
- `scripts/stop-pipeline.sh` menghentikan producer/consumer.
- `scripts/stop-stack.sh` menghentikan container.


### Narasi Presentasi

State machine ini cocok dipakai sebagai urutan demo di depan kelas.

Kalimat presentasi yang disarankan:

> Diagram ini menunjukkan bahwa sistem tidak dibuat sebagai satu program besar, tetapi sebagai rangkaian komponen dengan tanggung jawab yang jelas. Aliran data bergerak bertahap dari sumber, masuk ke Kafka, disimpan di HDFS, dianalisis Spark, lalu disajikan lewat dashboard Flask.

---

## 10. Arsitektur Dashboard

```mermaid
%%{init: {"theme":"base","themeVariables":{"fontFamily":"Inter, Arial","primaryColor":"#f1f5f9","primaryBorderColor":"#475569","secondaryColor":"#dbeafe","tertiaryColor":"#dcfce7","lineColor":"#334155"}}}%%
flowchart TB
    Browser["Browser"]
    HTML["index.html<br/>render panel<br/>theme toggle"]
    JS["JavaScript<br/>fetch /api/data<br/>setInterval 30s"]
    CSS["style.css<br/>light/dark theme<br/>AQI colors"]
    Flask["Flask app.py"]
    API["GET /api/data<br/>GET /api/status"]
    SparkJSON["spark_results.json"]
    LiveAPI["live_api.json"]
    LiveRSS["live_rss.json"]
    Demo["Fallback demo data"]

    Browser --> HTML
    HTML --> JS
    HTML --> CSS
    JS --> API
    API --> Flask
    Flask --> SparkJSON
    Flask --> LiveAPI
    Flask --> LiveRSS
    Flask --> Demo
    Flask --> API
    API --> JS
    JS --> HTML

    classDef client fill:#dbeafe,stroke:#2563eb,stroke-width:2px,color:#0f172a;
    classDef server fill:#f1f5f9,stroke:#475569,stroke-width:2px,color:#0f172a;
    classDef data fill:#dcfce7,stroke:#16a34a,stroke-width:2px,color:#0f172a;
    classDef fallback fill:#fef3c7,stroke:#d97706,stroke-width:2px,color:#0f172a;

    class Browser,HTML,JS,CSS client;
    class Flask,API server;
    class SparkJSON,LiveAPI,LiveRSS data;
    class Demo fallback;
```


### Tujuan Diagram

Diagram ini menjelaskan cara kerja dashboard dari backend sampai browser.


### Penjelasan Semua Kotak

| Kotak / Node | Penjelasan |
| --- | --- |
| `Browser` | Tempat pengguna membuka dashboard. |
| `index.html` | Template HTML yang merender panel dashboard. |
| `JavaScript` | Kode frontend yang fetch `/api/data` dan auto-refresh 30 detik. |
| `style.css` | File styling untuk tema, layout, dan warna AQI. |
| `Flask app.py` | Backend dashboard. |
| `GET /api/data dan /api/status` | Endpoint JSON untuk frontend. |
| `spark_results.json` | Hasil Spark untuk panel analisis. |
| `live_api.json` | Snapshot AQI terbaru. |
| `live_rss.json` | Snapshot berita terbaru. |
| `Fallback demo data` | Data contoh jika file runtime belum tersedia. |


### Penjelasan Semua Flow

- Browser memuat HTML.
- HTML memuat JavaScript dan CSS.
- JavaScript fetch `/api/data`.
- Endpoint Flask membaca JSON lokal dan fallback demo jika perlu.
- Response kembali ke JavaScript.
- JavaScript merender panel Spark, API, RSS, dan chart.


### Narasi Presentasi

Dashboard sengaja membaca JSON ringkas agar cepat dan tidak perlu langsung membaca HDFS.

Kalimat presentasi yang disarankan:

> Diagram ini menunjukkan bahwa sistem tidak dibuat sebagai satu program besar, tetapi sebagai rangkaian komponen dengan tanggung jawab yang jelas. Aliran data bergerak bertahap dari sumber, masuk ke Kafka, disimpan di HDFS, dianalisis Spark, lalu disajikan lewat dashboard Flask.

---

## Penjelasan Semua File yang Disebut dalam Diagram

| File | Peran dalam Arsitektur |
| --- | --- |
| `README.md` | Dokumentasi utama sistem. Informasi konsep, arsitektur, cara jalan, verifikasi, dan troubleshooting berasal dari file ini. |
| `ARCHITECTURE_A1.md` | Poster arsitektur A1 yang menjadi sumber diagram Mermaid dalam dokumen presentasi ini. |
| `docker-compose-kafka.yml` | Menjalankan Zookeeper dan Kafka broker. Kafka membuka listener host di `localhost:9092`. |
| `docker-compose-hadoop.yml` | Menjalankan NameNode, tiga DataNode, ResourceManager, dan NodeManager. |
| `hadoop.env` | Mengatur `fs.defaultFS`, WebHDFS, permission HDFS, dan `dfs.replication=2`. |
| `.env.example` | Template environment variable untuk token, Kafka topic, interval polling, HDFS, buffering, RSS, dan dashboard. |
| `requirements.txt` | Daftar dependency Python seperti `kafka-python-ng`, `feedparser`, `requests`, `hdfs`, `pyspark`, dan `flask`. |
| `scripts/start-stack.sh` | Menyalakan stack Hadoop dan Kafka. |
| `scripts/init-infra.sh` | Membuat topic Kafka dan folder HDFS awal. |
| `scripts/sanity-check.sh` | Memeriksa container, Kafka, HDFS, WebHDFS, dan port Kafka. |
| `scripts/run-producers.sh` | Menjalankan producer API dan RSS di background. |
| `scripts/run-consumer.sh` | Menjalankan consumer Kafka ke HDFS di background. |
| `scripts/run-dashboard.sh` | Menjalankan Flask dashboard di port 5000. |
| `scripts/run-all.sh` | Menjalankan stack, init, producer, consumer, dan dashboard dalam satu alur. |
| `scripts/stop-pipeline.sh` | Menghentikan producer dan consumer Python. |
| `scripts/stop-stack.sh` | Mematikan container Kafka dan Hadoop. Opsi `--volumes` menghapus volume data. |
| `kafka/producer_api.py` | Producer AQI. Mengambil data AQICN atau simulator dan mengirim ke topic `airquality-api`. |
| `kafka/producer_rss.py` | Producer RSS. Membaca feed, membersihkan summary, filter keyword, dedup, dan mengirim ke topic `airquality-rss`. |
| `kafka/consumer_to_hdfs.py` | Consumer dua topic. Melakukan buffering, flush ke HDFS, mirror JSON, dan commit offset setelah sukses. |
| `spark/analysis.ipynb` | Notebook Spark yang membaca data HDFS, melakukan tiga analisis, dan menulis hasil. |
| `dashboard/app.py` | Backend Flask untuk route `/`, `/api/data`, dan `/api/status`. |
| `dashboard/templates/index.html` | Frontend dashboard dengan JavaScript fetch `/api/data`, Chart.js, dan auto-refresh. |
| `dashboard/static/style.css` | CSS dashboard untuk layout, warna AQI, light theme, dark theme, dan tampilan tegas. |
| `dashboard/data/live_api.json` | Mirror runtime dari consumer untuk data AQI terbaru. |
| `dashboard/data/live_rss.json` | Mirror runtime dari consumer untuk berita terbaru. |
| `dashboard/data/spark_results.json` | Output runtime notebook Spark untuk panel analisis dashboard. |


## Script Presentasi 7 Menit

| Waktu | Narasi |
| --- | --- |
| Menit 0-1 | Perkenalkan tujuan proyek: monitoring kualitas udara Jawa Timur dengan pipeline Big Data. |
| Menit 1-2 | Tampilkan Peta Besar Sistem. Jelaskan layer sumber data, ingestion, Kafka, HDFS, Spark, dan dashboard. |
| Menit 2-3 | Tampilkan Topologi Deployment Lokal. Jelaskan proses Python berjalan di host dan infrastruktur berjalan di Docker. |
| Menit 3-4 | Tampilkan sequence AQI dan RSS. Jelaskan fallback simulator dan dedup RSS. |
| Menit 4-5 | Tampilkan consumer ke HDFS dan struktur HDFS. Tekankan buffering, manual commit, dan NDJSON. |
| Menit 5-6 | Tampilkan arsitektur Spark dan data contract. Jelaskan tiga analisis utama dan output dashboard. |
| Menit 6-7 | Tampilkan arsitektur dashboard dan state machine. Tutup dengan alur demo dari start stack sampai monitoring. |


## Hal yang Tidak Boleh Terlewat Saat Menjelaskan

- Producer API dan RSS terpisah karena format data dan logika ingest berbeda.
- Kafka punya dua topic agar data AQI dan berita tidak tercampur.
- Consumer memakai dua thread agar dua topic dapat diproses paralel.
- Offset Kafka baru di-commit setelah flush berhasil.
- HDFS menyimpan data historis; dashboard tidak membaca HDFS langsung.
- Mirror JSON dibuat untuk kebutuhan dashboard yang cepat.
- Spark membaca data historis, bukan data live langsung dari Kafka.
- Notebook punya fallback untuk masalah akses HDFS di WSL2.
- Dashboard punya fallback demo agar halaman tidak kosong.
- State machine menunjukkan urutan operasional demo yang benar.


## Penutup

Arsitektur AirQuality Alert menunjukkan alur Big Data yang lengkap: ingestion, message broker, distributed storage, analytics, dan presentation. Setiap diagram dalam dokumen ini menjelaskan satu sudut pandang yang berbeda: peta besar, deployment, sequence runtime, struktur HDFS, analisis Spark, data contract, state machine, dan dashboard.

Dokumen ini dapat dipakai sebagai naskah presentasi, bahan penjelasan diagram, atau pendamping poster `ARCHITECTURE_A1.md`.
