import serial
import time
import requests
import threading
import os
import re
import json
from urllib.parse import urlparse
from flask import Flask, request, jsonify

# --- Configuration ---
SERIAL_PORT = '/dev/ttyACM0'
BAUD_RATE = 115200
LARAVEL_API_URL = os.getenv("LARAVEL_API_URL", "http://127.0.0.1:8000/api/health-data")
TOKEN_CACHE_PATH = os.getenv("TOKEN_CACHE_PATH", "last_token.json")


def build_user_profile_url(health_data_url):
    """Convert .../api/health-data into .../api/user for token identity checks."""
    parsed = urlparse(health_data_url)
    path = parsed.path or ""
    if path.endswith("/health-data"):
        path = path[: -len("/health-data")] + "/user"
    elif path.endswith("health-data"):
        path = path[: -len("health-data")] + "user"
    else:
        path = "/api/user"

    return f"{parsed.scheme}://{parsed.netloc}{path}"


LARAVEL_USER_API_URL = os.getenv(
    "LARAVEL_USER_API_URL", build_user_profile_url(LARAVEL_API_URL)
)

app = Flask(__name__)
current_token = None


@app.after_request
def add_cors_headers(response):
    response.headers.setdefault("Access-Control-Allow-Origin", "*")
    response.headers.setdefault("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    response.headers.setdefault(
        "Access-Control-Allow-Headers",
        "Content-Type, Authorization",
    )
    return response


def fetch_authenticated_user(token):
    """Resolve token to backend user id/email for easier debugging."""
    try:
        response = requests.get(
            LARAVEL_USER_API_URL,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
            },
            timeout=5,
        )

        if response.status_code < 200 or response.status_code >= 300:
            return None

        body = response.json()
        if isinstance(body, dict) and isinstance(body.get("data"), dict):
            body = body["data"]

        if not isinstance(body, dict):
            return None

        return {
            "id": body.get("id"),
            "email": body.get("email"),
            "first_name": body.get("first_name"),
            "last_name": body.get("last_name"),
        }
    except Exception:
        return None


def load_token_cache():
    if not os.path.exists(TOKEN_CACHE_PATH):
        return {"tokens": {}, "last_user_id": None}
    try:
        with open(TOKEN_CACHE_PATH, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        if not isinstance(data, dict):
            return {"tokens": {}, "last_user_id": None}
        tokens = data.get("tokens")
        last_user_id = data.get("last_user_id")
        if not isinstance(tokens, dict):
            tokens = {}
        return {"tokens": tokens, "last_user_id": last_user_id}
    except Exception:
        return {"tokens": {}, "last_user_id": None}


def persist_token_for_user(user_id, token):
    try:
        cache = load_token_cache()
        cache["tokens"][str(user_id)] = token
        cache["last_user_id"] = str(user_id)
        with open(TOKEN_CACHE_PATH, "w", encoding="utf-8") as handle:
            json.dump(cache, handle)
    except Exception:
        pass


def parse_vitals_line(line):
    """Parse serial vitals into API payload.

    Supports both:
    - BPM:75.0,SPO2:98.0,TEMP:36.5
    - BPM: 72.8 | SpO2: 96% | Temp: 28.5C | BP: 122/84 mmHg
    """
    pretty_match = re.search(
        r"BPM:\s*([0-9]+(?:\.[0-9]+)?)\s*\|\s*"
        r"SpO2:\s*([0-9]+(?:\.[0-9]+)?)%\s*\|\s*"
        r"Temp:\s*([0-9]+(?:\.[0-9]+)?)\s*C\s*\|\s*"
        r"BP:\s*(\d+)\s*/\s*(\d+)",
        line,
        flags=re.IGNORECASE,
    )

    if pretty_match:
        return {
            "heart_rate": float(pretty_match.group(1)),
            "oxygen_saturation": float(pretty_match.group(2)),
            "body_temperature": float(pretty_match.group(3)),
            "systolic_bp": float(pretty_match.group(4)),
            "diastolic_bp": float(pretty_match.group(5)),
        }

    parts = {}
    for item in re.split(r"[,|]", line):
        if ":" not in item:
            continue
        key, value = item.split(":", 1)
        parts[key.strip().upper()] = value.strip()

    required = ["BPM", "SPO2", "TEMP"]
    if not all(key in parts for key in required):
        raise ValueError(f"Missing keys in serial data. Got: {list(parts.keys())}")

    heart_rate = float(parts["BPM"])
    spo2 = float(parts["SPO2"].replace("%", "").strip())
    temp_value = parts["TEMP"].strip()
    if temp_value.upper().endswith("C"):
        temp_value = temp_value[:-1].strip()
    temperature = float(temp_value)

    payload = {
        "heart_rate": heart_rate,
        "oxygen_saturation": spo2,
        "body_temperature": temperature,
    }

    bp_raw = parts.get("BP")
    if bp_raw:
        bp_match = re.search(r"(\d+)\s*/\s*(\d+)", bp_raw)
        if bp_match:
            payload["systolic_bp"] = float(bp_match.group(1))
            payload["diastolic_bp"] = float(bp_match.group(2))

    return payload


# --- Serial Reader Logic ---
def serial_to_laravel_bridge():
    global current_token
    
    print(f"📡 Connecting to Arduino on {SERIAL_PORT}...")
    print(f"🌐 Forwarding health payloads to: {LARAVEL_API_URL}")
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=1)
        time.sleep(2) # Wait for Arduino reset
        print("✅ Serial Connection Established.")
    except Exception as e:
        print(f"❌ Could not open serial port: {e}")
        return

    while True:
        if ser.in_waiting > 0:
            try:
                line = ser.readline().decode('utf-8', errors='ignore').strip()
                print(f"RAW DATA: {line}")
                
                # Accept both legacy comma format and new human-readable format.
                if "BPM:" in line:
                    print(f"📥 USB Data Received: {line}")
                    
                    if not current_token:
                        print("⚠️ Waiting for Mobile App to set Token...")
                        continue

                    payload = parse_vitals_line(line)

                    # 3. Forward to Laravel
                    headers = {
                        "Authorization": f"Bearer {current_token}",
                        "Accept": "application/json",
                        "Content-Type": "application/json"
                    }
                    
                    response = requests.post(
                        LARAVEL_API_URL,
                        json=payload,
                        headers=headers,
                        timeout=5,
                    )
                    
                    if response.status_code == 200:
                        resp_json = response.json()
                        status = resp_json.get('status')
                        if status == 'buffering':
                            samples = resp_json.get('data', {}).get('samples_collected')
                            remaining = resp_json.get('data', {}).get('remaining_seconds')
                            print(f"⏳ Buffering samples: {samples}, remaining ~{remaining}s")
                        else:
                            risk = resp_json.get('data', {}).get('analysis', {}).get('predicted_risk', 'Unknown')
                            print(f"🚀 8s average sent! Risk: {risk}")
                    else:
                        print(f"⚠️ Laravel Error: {response.status_code} | {response.text[:300]}")

            except Exception as e:
                print(f"❌ Error processing line: {e}")
        
        time.sleep(0.1)

# --- Flask Routes (For Mobile App) ---
@app.route('/set-token', methods=['POST', 'OPTIONS'])
def set_token():
    global current_token
    if request.method == 'OPTIONS':
        return jsonify({"message": "OK"}), 200
    data = request.get_json()
    if data and 'token' in data:
        current_token = data['token']
        profile = fetch_authenticated_user(current_token)
        if profile:
            if profile.get("id") is not None:
                persist_token_for_user(profile.get("id"), current_token)
            print(
                "\n[AUTH] Token Updated. System Active. "
                f"Receiving sensor data for user_id={profile.get('id')} email={profile.get('email')}"
            )
        else:
            print(
                "\n[AUTH] Token Updated. System Active. "
                "Could not resolve token to user profile."
            )

        return jsonify({"message": "Token updated", "user": profile}), 200
    return jsonify({"error": "Invalid payload"}), 400

if __name__ == "__main__":
    cache = load_token_cache()
    last_user_id = cache.get("last_user_id")
    cached_token = None
    if last_user_id is not None:
        cached_token = cache.get("tokens", {}).get(str(last_user_id))

    if cached_token:
        current_token = cached_token
        profile = fetch_authenticated_user(current_token)
        if profile:
            print(
                "\n[AUTH] Cached token loaded. System Active. "
                f"Receiving sensor data for user_id={profile.get('id')} email={profile.get('email')}"
            )
        else:
            print(
                "\n[AUTH] Cached token loaded. System Active. "
                "Could not resolve token to user profile."
            )

    # Start the Serial Monitor in a separate thread
    serial_thread = threading.Thread(target=serial_to_laravel_bridge, daemon=True)
    serial_thread.start()

    print("🚀 USB Bridge Server starting on port 5001...")
    app.run(host='0.0.0.0', port=5001, debug=False)