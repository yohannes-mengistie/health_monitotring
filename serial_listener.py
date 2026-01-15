import serial
import requests
import time
import threading
from flask import Flask, request, jsonify

# --- Configuration ---
SERIAL_PORT = 'COM5'  
BAUD_RATE = 9600
LARAVEL_API_URL = "http://127.0.0.1:8000/api/health-data"

# Global variable to hold the token received from the mobile phone
current_token = None

# --- Flask App to receive Token from Mobile ---
app = Flask(__name__)

@app.route('/set-token', methods=['POST'])
def set_token():
    global current_token
    data = request.get_json()
    
    if 'token' in data:
        current_token = data['token']
        print(f"\n[AUTH] New token received! System activated.")
        return jsonify({"message": "Token updated successfully"}), 200
    return jsonify({"error": "Invalid payload"}), 400

def start_flask():
    # Run Flask on port 5001 - Mobile app will POST to http://<PC_IP>:5001/set-token
    app.run(host='0.0.0.0', port=5001, debug=False, use_reloader=False)

# --- Main Logic for Serial Data ---
def listen_to_sensors():
    global current_token
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=1)
        print(f"--- Listening on {SERIAL_PORT} ---")
        print("--- Waiting for Mobile App to send token to port 5001... ---")

        while True:
            if current_token:
                if ser.in_waiting > 0:
                    line = ser.readline().decode('utf-8').strip()
                    
                    if not line:
                        continue

                    try:
                        parts = line.split(',')
                        if len(parts) < 2:
                            print(f"⚠️ Too few values: {line}")
                            continue

                        hr = float(parts[0].strip())
                        temp = float(parts[1].strip())

                        # Default: treat as live unless explicitly final
                        is_final = False
                        if len(parts) >= 3:
                            final_str = parts[2].strip().lower()
                            is_final = final_str in ['true', '1', 'yes', 'final']

                        payload = {
                            "heart_rate": hr,
                            "body_temperature": temp,
                            "device_id": "Proteus_Sensor_001",
                            "final": is_final
                        }

                        headers = {
                            "Authorization": f"Bearer {current_token}",
                            "Accept": "application/json"
                        }
                        
                        print(f"→ Sending {'FINAL' if is_final else 'LIVE'} → HR: {hr}, Temp: {temp}")

                        response = requests.post(LARAVEL_API_URL, json=payload, headers=headers, timeout=5)
                        
                        if response.status_code == 200:
                            data = response.json()
                            risk = data.get('data', {}).get('analysis', {}).get('predicted_risk', '—')
                            print(f"  ✓ Success | Risk: {risk}")
                        elif response.status_code == 401:
                            print("❌ Token expired/invalid → waiting for new token")
                            current_token = None
                        elif response.status_code == 422:
                            print(f"⚠️ Validation failed (422): {response.text}")
                        else:
                            print(f"⚠️ Laravel responded with {response.status_code}: {response.text}")

                    except ValueError as ve:
                        print(f"⚠️ Parse error: {ve} → line was: '{line}'")
                    except requests.RequestException as re:
                        print(f"⚠️ Network error to Laravel: {re}")

            time.sleep(0.1)

    except serial.SerialException as e:
        print(f"Serial Error: {e}")
    except KeyboardInterrupt:
        print("Closing Listener...")
    finally:
        if 'ser' in locals():
            ser.close()

if __name__ == "__main__":
    # Start the Flask server in a separate thread so it doesn't block the serial loop
    flask_thread = threading.Thread(target=start_flask)
    flask_thread.daemon = True
    flask_thread.start()

    # Start the sensor listener
    listen_to_sensors()