from flask import Flask, render_template, jsonify
import json
import os

app = Flask(__name__)

DATA_DIR = os.path.join(os.path.dirname(__file__), 'data')

def load_json_data(filename):
    """Fungsi pembantu untuk membaca file JSON dari folder data"""
    file_path = os.path.join(DATA_DIR, filename)
    if os.path.exists(file_path):
        with open(file_path, 'r') as f:
            return json.load(f)
    return {}

@app.route('/')
def index():
    """Menampilkan halaman utama dashboard"""
    return render_template('index.html')

@app.route('/api/status')
def get_status():
    """
    Endpoint untuk mengambil data terbaru yang akan ditampilkan di 3 panel:
    1. Hasil analisis Spark (Historis)
    2. Data API terbaru (Real-time)
    3. Berita RSS terbaru (Feed)
    """
    spark_results = load_json_data('spark_results.json')
    live_api = load_json_data('live_api.json')
    live_rss = load_json_data('live_rss.json')
    
    return jsonify({
        "spark": spark_results,
        "api": live_api,
        "rss": live_rss
    })

if __name__ == '__main__':
    app.run(debug=True, port=5000)
