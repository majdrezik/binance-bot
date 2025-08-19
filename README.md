# TradingView → Binance Webhook Bot

This is a Python Flask app that receives TradingView alerts via webhook and executes spot trades on Binance (live or testnet). It can also send email notifications when orders are executed or fail.  

The app is deployed under `/opt/tv-trader` on the server.  

---

## Features

- Supports **Binance spot trading** (live & testnet).  
- Receives TradingView alerts in JSON format.  
- Executes **market buy/sell orders**.  
- Sends **simplified email notifications** for executed or failed trades.  
- Supports a **shared token** for basic security.  
- Configurable via `.env`.  
- Deployed under `/opt/tv-trader` for system-wide management.  

---

## Requirements

- Python 3.10+  
- Virtualenv (recommended)  
- Binance account (live & testnet API keys)  
- Gmail account for sending emails (app password recommended)  

---

## Installation

1. Clone or copy the app into `/opt/tv-trader`:

```bash
sudo mkdir -p /opt/tv-trader
sudo chown $USER:$USER /opt/tv-trader
cd /opt/tv-trader
```
2. Place `app.py` and `requirements.txt` in `/opt/tv-trader`.

3. Create a virtual environment:
```
python3 -m venv .venv
source .venv/bin/activate
```
4. Install dependencies:
```
pip install -r requirements.txt
```
5. Create a `.env` file in `/opt/tv-trader`:
```
# Binance settings
BINANCE_MODE=testnet       # choose 'live' or 'testnet'
SHARED_TOKEN=your_secret_token
DEFAULT_SYMBOL=BTCUSDT
DEFAULT_QUOTE_QTY=50
TRADING_ENABLED=true

# API keys
TESTNET_API_KEY=your_testnet_api_key
TESTNET_API_SECRET=your_testnet_secret
BINANCE_API_KEY=your_live_api_key
BINANCE_API_SECRET=your_live_api_secret

# Email settings
EMAIL_USER=youremail@gmail.com
EMAIL_PASS=your_app_password
EMAIL_TO=youremail@gmail.com
```

6. Start the Flask app (for testing):
```
source .venv/bin/activate
python app.py
```

# Usage

### 1. Health Check

`curl http://127.0.0.1:8000/health`

Response example:

```
{
  "ok": true,
  "mode": "testnet",
  "trading_enabled": true
}
```

---

### 2. TradingView Webhook

Send a POST request with JSON:
```
curl -X POST "https://yourdomain.com/webhook?token=YOUR_SHARED_TOKEN" \
-H "Content-Type: application/json" \
-d '{
  "action": "BUY",
  "symbol": "BTCUSDT",
  "quoteQty": 50
}'
```
 - action: BUY or SELL
 - symbol: Trading pair (e.g., BTCUSDT)
 - quoteQty: Amount in quote currency (e.g., USDT)

### 3. Email Notifications

- Successful orders:
```
Action: BUY
Symbol: BTCUSDT
Quantity: 0.00044
Price: 112979.25
Status: FILLED
Commission: 0 USDT
Type: MARKET
TransactTime: 1755634309026
```

- Failed orders:
```
Action: BUY
Error: <error message from Binance>
```

# Deployment (Systemd Example)

1. Create /etc/systemd/system/tv-trader.service:
```
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
```

2. Enable and start the service:
```
sudo systemctl daemon-reload
sudo systemctl enable tv-trader
sudo systemctl start tv-trader
sudo systemctl status tv-trader
```

# Notes

1. Testnet first: Always test your bot on Testnet before using live funds.
1. Security: Only expose the webhook via HTTPS, and keep your SHARED_TOKEN secret.
1. Quantity: You can set DEFAULT_QUOTE_QTY or send quoteQty in TradingView alerts.
1. App is installed under /opt/tv-trader for easier server management.