import serial
import time
import requests
import threading
import os
from flask import Flask, request, jsonify

# --- Configuration ---
SERIAL_PORT = 'COM9'  
BAUD_RATE = 115200
LARAVEL_API_URL = os.getenv("LARAVEL_API_URL", "http://127.0.0.1:8000/api/health-data")

app = Flask(__name__)
current_token = None


def parse_vitals_line(line):
    """Parse one serial line like BPM:75.0,SPO2:98.0,TEMP:36.5 into payload."""
    parts = {}
    for item in line.split(","):
        if ":" not in item:
            continue
        key, value = item.split(":", 1)
        parts[key.strip().upper()] = value.strip()

    required = ["BPM", "SPO2", "TEMP"]
    if not all(key in parts for key in required):
        raise ValueError(f"Missing keys in serial data. Got: {list(parts.keys())}")

    heart_rate = float(parts["BPM"])
    spo2 = float(parts["SPO2"])
    temperature = float(parts["TEMP"])

    return {
        "heart_rate": heart_rate,
        "oxygen_saturation": spo2,
        "body_temperature": temperature,
    }


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
                
                # Check if it looks like the ML data line we formatted earlier
                # Expected format: BPM:75.0,SPO2:98.0,TEMP:36.5
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
@app.route('/set-token', methods=['POST'])
def set_token():
    global current_token
    data = request.get_json()
    if data and 'token' in data:
        current_token = data['token']
        print(f"\n[AUTH] Token Updated. System Active.")
        return jsonify({"message": "Token updated"}), 200
    return jsonify({"error": "Invalid payload"}), 400

if __name__ == "__main__":
    # Start the Serial Monitor in a separate thread
    serial_thread = threading.Thread(target=serial_to_laravel_bridge, daemon=True)
    serial_thread.start()

    print("🚀 USB Bridge Server starting on port 5001...")
    app.run(host='0.0.0.0', port=5001, debug=False)