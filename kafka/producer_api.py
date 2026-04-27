# [Nama Anggota]: producer_api.py
import time
import json
import requests
from kafka import KafkaProducer

# Inisialisasi Producer
producer = KafkaProducer(
    bootstrap_servers=['localhost:9092'],
    value_serializer=lambda x: json.dumps(x).encode('utf-8')
)

# Daftar kota sesuai topik (AirQuality Jawa Timur)
CITIES = ["Surabaya", "Malang", "Sidoarjo", "Gresik"]

def fetch_air_quality(city):
    url = f"https://api.openaq.org/v2/latest?city={city}&limit=1"
    try:
        response = requests.get(url, timeout=10)
        data = response.json()
        if data['results']:
            res = data['results'][0]
            # Ambil parameter pertama (misal PM2.5)
            payload = {
                "city": city,
                "parameter": res['measurements'][0]['parameter'],
                "value": res['measurements'][0]['value'],
                "unit": res['measurements'][0]['unit'],
                "timestamp": res['measurements'][0]['lastUpdated']
            }
            return payload
    except Exception as e:
        print(f"Error pada kota {city}: {e}")
    return None

print("Producer API dimulai...")
while True:
    for city in CITIES:
        data = fetch_air_quality(city)
        if data:
            producer.send('airquality-api', value=data)
            print(f"Mengirim data {city}: {data['value']} {data['unit']}")
    
    # Tunggu 15 menit sebelum ambil data lagi (sesuai instruksi polling)
    time.sleep(900)
