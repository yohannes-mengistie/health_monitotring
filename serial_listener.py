import serial
import time
import requests
import json
import threading
from flask import Flask, request, jsonify

# --- Configuration ---
SERIAL_PORT = 'COM3'  # Change this to your port (e.g., '/dev/ttyUSB0' on Linux/Mac)
BAUD_RATE = 115200
LARAVEL_API_URL = "http://127.0.0.1:8000/api/sensor-data"

app = Flask(__name__)
current_token = None

# --- Serial Reader Logic ---
def serial_to_laravel_bridge():
    global current_token
    
    print(f"📡 Connecting to Arduino on {SERIAL_PORT}...")
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
                # 1. Read line from USB
                line = ser.readline().decode('utf-8').strip()
                
                # Check if it looks like the ML data line we formatted earlier
                # Expected format: BPM:75.0,SPO2:98.0,TEMP:36.5
                if "BPM:" in line:
                    print(f"📥 USB Data Received: {line}")
                    
                    if not current_token:
                        print("⚠️ Waiting for Mobile App to set Token...")
                        continue

                    # 2. Parse the string into JSON
                    # Splitting "BPM:75.0,SPO2:98.0,TEMP:36.5"
                    parts = dict(item.split(":") for item in line.split(","))
                    
                    payload = {
                        "heart_rate": float(parts["BPM"]),
                        "oxygen_saturation": float(parts["SPO2"]),
                        "body_temperature": float(parts["TEMP"])
                    }

                    # 3. Forward to Laravel
                    headers = {
                        "Authorization": f"Bearer {current_token}",
                        "Accept": "application/json",
                        "Content-Type": "application/json"
                    }
                    
                    response = requests.post(LARAVEL_API_URL, json=payload, headers=headers)
                    
                    if response.status_code == 200:
                        risk = response.json().get('data', {}).get('analysis', {}).get('predicted_risk', 'Unknown')
                        print(f"🚀 Sent to Laravel! Risk: {risk}")
                    else:
                        print(f"⚠️ Laravel Error: {response.status_code}")

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