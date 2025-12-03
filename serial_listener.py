import serial
import requests
import time

# -------------------------------
# CONFIGURATION
# -------------------------------
SERIAL_PORT = "COM5"      # Change this to your Proteus virtual COM port
BAUD_RATE = 9600
LARAVEL_API_URL = "http://127.0.0.1:8000/api/health-data"

# -------------------------------
# SERIAL CONNECTION
# -------------------------------
print("Connecting to serial port...")
ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=1)
time.sleep(2)
print("Connected!\nListening for data...\n")

# -------------------------------
# MAIN LOOP
# -------------------------------
while True:
    try:
        raw = ser.readline().decode().strip()

        if not raw:
            continue

        print("RAW:", raw)

        # ----------------------------------------------------
        # 1. LIVE TEMPERATURE STREAM
        # Format: LIVE_TEMP_C:36.5
        # ----------------------------------------------------
        if raw.startswith("LIVE_TEMP_C:"):
            temp_str = raw.split(":")[1]
            temp_value = float(temp_str)

            payload = {
                "device_id": "simulator_01",
                "temperature": temp_value,
                "heart_rate": None
            }

            print("Sending LIVE temperature →", payload)
            send_to_backend(payload)
            
            continue

        # ----------------------------------------------------
        # 2. FINAL COMPLETE DATA SET
        # Format: FINAL_DATA_SET,<bpm>,<temp>
        # Example: FINAL_DATA_SET,75,36.5
        # ----------------------------------------------------
        if raw.startswith("FINAL_DATA_SET"):
            _, bpm_str, temp_str = raw.split(",")

            bpm_value = int(bpm_str)
            temp_value = float(temp_str)

            payload = {
                "device_id": "simulator_01",
                "temperature": temp_value,
                "heart_rate": bpm_value
            }

            print("Sending FINAL measurement →", payload)
            requests.post(LARAVEL_API_URL, json=payload)
            continue

        # ----------------------------------------------------
        # IGNORE OTHER LINES (debug messages)
        # ----------------------------------------------------
        # Example: PULSE_DETECTED, TIME_UPDATE, etc.

    except Exception as e:
        print("Error:", e)
        time.sleep(1)

    def send_to_backend(data):
        try:
            response = requests.post(LARAVEL_API_URL, json=data)
            if response.status_code == 200:
                print("Data sent successfully!")
            else:
                print("Failed to send data. Status code:", response.status_code)
        except Exception as e:
            print("Error sending data:", e) 
