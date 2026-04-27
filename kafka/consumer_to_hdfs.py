# [Nama Anggota]: consumer_to_hdfs.py
from kafka import KafkaConsumer
from hdfs import InsecureClient
import json
from datetime import datetime

# Inisialisasi Consumer
consumer = KafkaConsumer(
    'airquality-api', 'airquality-rss',
    bootstrap_servers=['localhost:9092'],
    auto_offset_reset='earliest',
    value_deserializer=lambda x: json.loads(x.decode('utf-8'))
)

# Inisialisasi HDFS Client (Port 9870 sesuai docker-compose)
client = InsecureClient('http://localhost:9870', user='root')

print("Consumer HDFS berjalan... Menunggu pesan...")

try:
    for message in consumer:
        topic = message.topic
        data = message.value
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Buat path folder di HDFS
        hdfs_folder = f"/data/airquality/{topic.split('-')[1]}"
        hdfs_path = f"{hdfs_folder}/data_{timestamp}.json"
        
        # Simpan ke HDFS
        with client.write(hdfs_path, encoding='utf-8') as writer:
            json.dump(data, writer)
            
        print(f"Sukses simpan ke HDFS: {hdfs_path}")

except Exception as e:
    print(f"Terjadi error: {e}")
