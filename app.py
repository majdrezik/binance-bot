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

EMAIL_USER = os.getenv("EMAIL_USER")  # Gmail address
EMAIL_PASS = os.getenv("EMAIL_PASS")  # Gmail app password
EMAIL_TO = os.getenv("EMAIL_TO")      # where to send notifications

# Choose endpoint
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
# Authentication check
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
    order_type = (data.get("order_type") or "MARKET").upper()
    max_pct = float(data.get("max_pct", 100))  # default 100%

    if action not in ("BUY", "SELL"):
        return jsonify({"error": "action must be BUY or SELL"}), 400
    if order_type != "MARKET":
        return jsonify({"error": "only MARKET supported"}), 400

    if not TRADING_ENABLED:
        return jsonify({"status": "dry-run", "symbol": symbol, "action": action}), 200

    try:
        # Fetch current balances
        balances = {b['asset']: float(b['free']) for b in client.account()['balances']}

        if action == "BUY":
            usdt_balance = balances.get("USDT", 0)
            spend = usdt_balance * max_pct / 100
            order = client.new_order(
                symbol=symbol, side=action, type="MARKET", quoteOrderQty=str(spend)
            )
        else:  # SELL
            base_asset = symbol.replace("USDT", "")
            asset_balance = balances.get(base_asset, 0)
            qty_to_sell = asset_balance * max_pct / 100
            order = client.new_order(
                symbol=symbol, side=action, type="MARKET", quantity=str(qty_to_sell)
            )

        # Email simplified info
        fills = order.get("fills", [{}])
        fill = fills[0] if fills else {}
        body = f"""
Action: {order.get('side')}
Symbol: {order.get('symbol')}
Quantity: {order.get('executedQty')}
Price: {fill.get('price', 'N/A')}
Mode: {MODE}
Status: {order.get('status')}
Commission: {fill.get('commission', '0')} {fill.get('commissionAsset', '')}
Type: {order.get('type')}
TransactTime: {order.get('transactTime')}
"""
        send_email(subject=f"{order.get('side')} executed {order.get('symbol')}", body=body)

        return jsonify({"status": "filled", "order": order}), 200

    except Exception as e:
        send_email(subject=f"{action} FAILED", body=str(e))
        return jsonify({"error": str(e)}), 500

# ---------------------------
if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8000)