
#!/bin/bash
# -------------------------------
# EC2 User Data - Full TradingView → Binance Setup
# -------------------------------

set -e

# Update system and install dependencies
apt-get update -y
apt-get upgrade -y
apt-get install -y python3 python3-venv python3-pip nginx git curl certbot python3-certbot-nginx unzip

# Create project directory
mkdir -p /opt/tv-trader
cd /opt/tv-trader

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install Python dependencies
pip install --upgrade pip
cat > requirements.txt << 'EOF'
flask
gunicorn
python-dotenv
binance-connector
EOF
pip install -r requirements.txt


# -------------------------------
# Environment Variables
# -------------------------------
cat > /opt/tv-trader/.env <<EOL
# BINANCE API KEYS
BINANCE_API_KEY=
BINANCE_API_SECRET=
TESTNET_API_KEY=
TESTNET_API_SECRET=

# Choose 'live' or 'testnet'
BINANCE_MODE=live
SHARED_TOKEN=
DEFAULT_SYMBOL=BTCUSDT
DEFAULT_QUOTE_QTY=50
TRADING_ENABLED=true

# EMAIL
EMAIL_USER=majdrezik@gmail.com
EMAIL_PASS=
EMAIL_TO=majdrezik@gmail.com
EOL

# -------------------------------
# Python app.py
# -------------------------------
cat > /opt/tv-trader/app.py <<'EOL'
import os
import smtplib
from email.mime.text import MIMEText
from flask import Flask, request, jsonify
from dotenv import load_dotenv
from binance.spot import Spot as SpotClient

load_dotenv()

MODE = os.getenv("BINANCE_MODE", "testnet").lower()
SHARED_TOKEN = os.getenv("SHARED_TOKEN")
DEFAULT_SYMBOL = os.getenv("DEFAULT_SYMBOL", "BTCUSDT")
DEFAULT_QUOTE_QTY = float(os.getenv("DEFAULT_QUOTE_QTY", "50"))
TRADING_ENABLED = os.getenv("TRADING_ENABLED", "true").lower() == "true"

EMAIL_USER = os.getenv("EMAIL_USER")
EMAIL_PASS = os.getenv("EMAIL_PASS")
EMAIL_TO = os.getenv("EMAIL_TO")

if MODE == "testnet":
    BASE_URL = "https://testnet.binance.vision"
    API_KEY = os.getenv("TESTNET_API_KEY")
    API_SECRET = os.getenv("TESTNET_API_SECRET")
else:
    BASE_URL = "https://api.binance.com"
    API_KEY = os.getenv("BINANCE_API_KEY")
    API_SECRET = os.getenv("BINANCE_API_SECRET")

client = SpotClient(api_key=API_KEY, api_secret=API_SECRET, base_url=BASE_URL)
app = Flask(__name__)

# ---------------------------
# Email utility
# ---------------------------
def send_email(subject: str, body: str):
    if not EMAIL_USER or not EMAIL_PASS or not EMAIL_TO:
        print("⚠️ Email not configured, skipping notification.")
        return
    try:
        msg = MIMEText(body)
        msg["Subject"] = subject
        msg["From"] = EMAIL_USER
        msg["To"] = EMAIL_TO
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
            server.login(EMAIL_USER, EMAIL_PASS)
            server.send_message(msg)
        print(f"✅ Email sent: {subject}")
    except Exception as e:
        print(f"❌ Failed to send email: {e}")

# ---------------------------
# Auth
# ---------------------------
def auth_ok(req):
    token = None
    if req.is_json:
        token = req.json.get("token")
    if not token:
        token = req.args.get("token")
    return SHARED_TOKEN and token == SHARED_TOKEN

# ---------------------------
# Routes
# ---------------------------
@app.route("/health", methods=["GET"])
def health():
    return {"ok": True, "mode": MODE, "trading_enabled": TRADING_ENABLED}

@app.route("/webhook", methods=["POST"])
def webhook():
    if not auth_ok(request):
        return jsonify({"error": "unauthorized"}), 401
    if not request.is_json:
        return jsonify({"error": "expected JSON"}), 400

    data = request.get_json()
    action = (data.get("action") or data.get("side") or "").upper()
    symbol = (data.get("symbol") or DEFAULT_SYMBOL).upper()
    quantity = data.get("quantity") or data.get("qty")
    quote_qty = data.get("quoteQty") or data.get("amount")
    order_type = (data.get("order_type") or "MARKET").upper()

    if action not in ("BUY", "SELL"):
        return jsonify({"error": "action must be BUY or SELL"}), 400
    if order_type != "MARKET":
        return jsonify({"error": "only MARKET supported"}), 400
    if not TRADING_ENABLED:
        return jsonify({"status": "dry-run", "symbol": symbol, "action": action}), 200

    try:
        if quantity:
            order = client.new_order(symbol=symbol, side=action, type="MARKET", quantity=str(quantity))
        else:
            spend = float(quote_qty) if quote_qty else DEFAULT_QUOTE_QTY
            order = client.new_order(symbol=symbol, side=action, type="MARKET", quoteOrderQty=str(spend))

        # Simplified email
        if order:
            fill = order.get("fills", [{}])[0]
            body = f"""
Action: {order.get('side')}
Symbol: {order.get('symbol')}
Quantity: {order.get('executedQty')}
Price: {fill.get('price', 'N/A')}
MODE: {MODE}
Status: {order.get('status')}
Commission: {fill.get('commission', '0')} {fill.get('commissionAsset', '')}
Type: {order.get('type')}
TransactTime: {order.get('transactTime')}
"""
            send_email(subject=f"{order.get('side')} order executed on {order.get('symbol')}", body=body)

        return jsonify({"status": "filled", "order": order}), 200
    except Exception as e:
        send_email(subject=f"{action} order FAILED", body=str(e))
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8000)
EOL

# -------------------------------
# Nginx configuration
# -------------------------------
cat > /etc/nginx/sites-available/tv-trader <<EOL
server {
    listen 80;
    server_name binance.majdrezik.com;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOL

ln -s /etc/nginx/sites-available/tv-trader /etc/nginx/sites-enabled/
nginx -t
systemctl restart nginx

# -------------------------------
# SSL via Certbot
# -------------------------------
certbot --nginx --non-interactive --agree-tos -m majdrezik@gmail.com -d binance.majdrezik.com

# -------------------------------
# Systemd Service
# -------------------------------
cat > /etc/systemd/system/tv-trader.service <<EOL
[Unit]
Description=TradingView → Binance webhook (gunicorn)
After=network.target

[Service]
User=root
WorkingDirectory=/opt/tv-trader
Environment="PATH=/opt/tv-trader/.venv/bin"
EnvironmentFile=/opt/tv-trader/.env
ExecStart=/opt/tv-trader/.venv/bin/gunicorn -w 2 -b 127.0.0.1:8000 app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable tv-trader
systemctl start tv-trader
systemctl status tv-trader
