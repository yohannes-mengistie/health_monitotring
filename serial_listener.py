import serial
import requests
import time
import threading
from flask import Flask, request, jsonify

# --- Configuration ---
SERIAL_PORT = 'COM5'  
BAUD_RATE = 9600
LARAVEL_API_URL = "http://127.0.0.1:8000/api/sensor-data"

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
            # Only proceed if we have a token from the mobile app
            if current_token:
                if ser.in_waiting > 0:
                    line = ser.readline().decode('utf-8').strip()
                    
                    try:
                        # Parsing Heart Rate and Temperature (matching your ML model requirements)
                        hr, temp = line.split(',')
                        
                        payload = {
                            "heart_rate": float(hr),
                            "body_temperature": float(temp)
                        }

                        # Send to Laravel with the dynamic Bearer Token
                        headers = {
                            "Authorization": f"Bearer {current_token}",
                            "Accept": "application/json"
                        }
                        
                        response = requests.post(LARAVEL_API_URL, json=payload, headers=headers)
                        
                        if response.status_code == 200:
                            print(f"✅ Sent: HR {hr}, Temp {temp} | Risk: {response.json().get('data', {}).get('analysis', {}).get('predicted_risk')}")
                        elif response.status_code == 401:
                            print("❌ Token expired or invalid. Please re-login on mobile.")
                            current_token = None # Reset token to wait for a new one
                        else:
                            print(f"⚠️ Laravel Error: {response.status_code}")

                    except ValueError:
                        print(f"⚠️ Invalid data format from Proteus: {line}")
            
            time.sleep(0.1) 

    except serial.SerialException as e:
        print(f"Serial Error: {e}")
    except KeyboardInterrupt:
        print("Closing Listener...")
    finally:
        if 'ser' in locals(): ser.close()

if __name__ == "__main__":
    # Start the Flask server in a separate thread so it doesn't block the serial loop
    flask_thread = threading.Thread(target=start_flask)
    flask_thread.daemon = True
    flask_thread.start()

    # Start the sensor listener
    listen_to_sensors()