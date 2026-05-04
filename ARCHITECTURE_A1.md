<!-- markdownlint-disable MD012 MD033 -->

# AirQuality Alert - Dokumen Arsitektur A1

Dokumen ini adalah file khusus untuk menjelaskan arsitektur proyek dalam bentuk poster teknis berukuran **A1 landscape**. Fokus dokumen ini adalah diagram besar, berwarna, dan mudah dipakai untuk presentasi atau export ke PDF.

> **Target format**
> Ukuran kertas: A1 landscape.
> Rasio visual: lebar, multi-kolom, cocok untuk poster arsitektur.
> Diagram: Mermaid berwarna, dengan teks penjelas singkat di bawah setiap diagram.
> Catatan: Mermaid dirender otomatis di GitHub dan banyak Markdown preview modern. Untuk hasil poster terbaik, buka di Markdown preview yang mendukung Mermaid lalu export/print ke PDF ukuran A1 landscape.

<style>
@page {
  size: A1 landscape;
  margin: 18mm;
}

body {
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
  color: #0f172a;
  background: #ffffff;
  line-height: 1.45;
}

h1 {
  font-size: 42px;
  letter-spacing: -0.04em;
  margin-bottom: 8px;
}

h2 {
  font-size: 28px;
  margin-top: 34px;
  padding-bottom: 8px;
  border-bottom: 3px solid #1e3a8a;
}

h3 {
  font-size: 20px;
  margin-top: 24px;
}

p,
li,
td,
th {
  font-size: 15px;
}

blockquote {
  border-left: 6px solid #2563eb;
  background: #eff6ff;
  padding: 12px 16px;
  margin: 18px 0;
}

table {
  width: 100%;
  border-collapse: collapse;
  margin: 12px 0 24px;
}

th {
  background: #1e3a8a;
  color: #ffffff;
}

th,
td {
  border: 1px solid #cbd5e1;
  padding: 8px 10px;
  vertical-align: top;
}

.a1-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 18px;
}

.caption {
  font-size: 14px;
  color: #334155;
  background: #f8fafc;
  border: 1px solid #cbd5e1;
  padding: 10px 12px;
  margin-top: 8px;
}

.page-break {
  page-break-before: always;
}
</style>

---

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

<div class="caption">
Diagram ini menunjukkan arsitektur end-to-end. Data masuk dari AQICN/simulator dan RSS, melewati Kafka, ditulis ke HDFS, dianalisis Spark, lalu ditampilkan lewat dashboard Flask. Warna menunjukkan batas tanggung jawab tiap lapisan.
</div>

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

<div class="caption">
Deployment lokal memisahkan proses Python di host dan service besar di Docker. Producer dan consumer mengakses Kafka melalui `localhost:9092`; consumer dan notebook memakai strategi `docker exec` bila akses HDFS langsung dari WSL2 bermasalah.
</div>

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

<div class="caption">
Producer API selalu berusaha memakai data asli AQICN. Jika token kosong atau request gagal, simulator mengisi data agar pipeline tetap bisa diuji dan dashboard tetap bisa berjalan saat demo.
</div>

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

<div class="caption">
Producer RSS menjaga agar berita yang sama tidak dikirim berulang. Filter keyword membuat berita yang tampil lebih dekat ke tema lingkungan, sementara fallback Top-N menjaga dashboard tidak kosong saat feed sedang tidak memuat kata kunci.
</div>

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

<div class="caption">
Offset Kafka baru di-commit setelah data berhasil ditulis ke HDFS dan mirror dashboard diperbarui. Ini menjaga agar data tidak dianggap selesai sebelum benar-benar tersimpan.
</div>

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

<div class="caption">
Folder `api` dan `rss` menyimpan data mentah hasil consumer. Folder `hasil` menyimpan output Spark dalam format Parquet. Pemisahan ini menjaga batas antara raw data dan processed data.
</div>

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

<div class="caption">
Spark membaca data historis dari HDFS. Jika akses native HDFS bermasalah di WSL2, notebook memakai fallback yang tetap mengambil data dari HDFS, hanya jalur pembacaannya yang berbeda.
</div>

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

<div class="caption">
Kontrak data menjaga agar producer, consumer, Spark, dan dashboard punya ekspektasi field yang sama. Field utama untuk analisis adalah kota, AQI, waktu, kategori, dan hasil agregasi.
</div>

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

<div class="caption">
State machine ini berguna untuk menjelaskan urutan demo. Infrastruktur harus siap lebih dulu, kemudian topic dan folder dibuat, producer-consumer berjalan, Spark membuat hasil, lalu dashboard menampilkan data.
</div>

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

<div class="caption">
Dashboard tidak membaca HDFS langsung. Flask membaca JSON lokal yang sudah diringkas oleh consumer dan Spark. Jika file belum ada, data demo dipakai agar dashboard tetap bisa dibuka.
</div>

---

## 11. Matriks Komponen

| Lapisan | File / Service | Input | Output | Alasan Desain |
| --- | --- | --- | --- | --- |
| AQI Producer | `kafka/producer_api.py` | AQICN / simulator | Kafka `airquality-api` | Memisahkan pengambilan AQI dari penyimpanan. |
| RSS Producer | `kafka/producer_rss.py` | RSS feeds | Kafka `airquality-rss` | Menambahkan konteks berita. |
| Broker | `kafka-broker` | Event JSON | Topic log | Menstabilkan laju data. |
| Consumer | `kafka/consumer_to_hdfs.py` | Kafka topics | HDFS + mirror JSON | Menulis batch dan menjaga offset. |
| Storage | HDFS | NDJSON | Data historis | Menyimpan arsip untuk Spark. |
| Analytics | `spark/analysis.ipynb` | HDFS API data | Parquet + JSON summary | Menghasilkan insight. |
| Backend | `dashboard/app.py` | JSON lokal | `/api/data` | Menyajikan data untuk frontend. |
| Frontend | `index.html`, `style.css` | `/api/data` | Dashboard visual | Memudahkan pembacaan hasil. |

---

## 12. Catatan Export A1

Untuk menjadikan dokumen ini poster A1:

1. Buka file `ARCHITECTURE_A1.md` pada Markdown preview yang mendukung Mermaid.
2. Pastikan diagram Mermaid berhasil dirender.
3. Gunakan print/export PDF.
4. Pilih ukuran kertas **A1**.
5. Pilih orientasi **Landscape**.
6. Jika preview mengabaikan CSS `@page`, atur ukuran A1 secara manual pada dialog print.

Alternatif CLI:

```bash
# Jika memakai mermaid-cli untuk render diagram satu per satu:
npx @mermaid-js/mermaid-cli -i ARCHITECTURE_A1.md -o architecture-output.svg
```

Catatan: rendering Markdown penuh dengan banyak diagram lebih stabil dilakukan dari preview editor yang mendukung Mermaid, lalu export ke PDF.
