import feedparser
import time
import json
from kafka import KafkaProducer

producer = KafkaProducer(
    bootstrap_servers=['localhost:9092'],
    value_serializer=lambda x: json.dumps(x).encode('utf-8')
)

RSS_FEEDS = [
    "https://rss.tempo.co/tag/polusi",
    "https://rss.kompas.com/feed/kompas.com/sains/environment"
]

print("Producer RSS dimulai...")
while True:
    for url in RSS_FEEDS:
        feed = feedparser.parse(url)
        for entry in feed.entries[:3]: 
            payload = {
                "title": entry.title,
                "link": entry.link,
                "published": entry.published,
                "summary": entry.get('summary', '')[:200] 
            }
            producer.send('airquality-rss', value=payload)
            print(f"Berita Terkirim: {entry.title[:50]}...")
            
    time.sleep(600)
