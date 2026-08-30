cat > app.py << 'EOF'
from flask import Flask, jsonify
from prometheus_flask_exporter import PrometheusMetrics
import os
import psycopg2

app = Flask(__name__)
metrics = PrometheusMetrics(app)

def get_connection():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST"),
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ.get("DB_NAME"),
        user=os.environ.get("DB_USER"),
        password=os.environ.get("DB_PASSWORD"),
        connect_timeout=5
    )

def init_db():
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS visits (
            id SERIAL PRIMARY KEY,
            visited_at TIMESTAMP DEFAULT NOW()
        )
    """)
    conn.commit()
    cur.close()
    conn.close()

@app.route("/health")
def health():
    return jsonify({"status": "ok"})

@app.route("/api/visits", methods=["POST"])
def record_visit():
    try:
        init_db()
        conn = get_connection()
        cur = conn.cursor()
        cur.execute("INSERT INTO visits DEFAULT VALUES")
        conn.commit()
        cur.execute("SELECT COUNT(*) FROM visits")
        count = cur.fetchone()[0]
        cur.close()
        conn.close()
        return jsonify({"status": "ok", "count": count})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
