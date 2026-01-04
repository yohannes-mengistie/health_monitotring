from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import joblib
import pandas as pd
from datetime import datetime
import uvicorn

app = FastAPI()

# --- LOAD MODELS ONCE ---
try:
    model = joblib.load('final_health_risk_model.pkl')
    required_features = joblib.load('model_features.pkl')
    print("✅ Models loaded successfully")
except Exception as e:
    print(f"❌ Error loading models: {e}")

# --- DATA SCHEMA ---
class SensorData(BaseModel):
    heart_rate: float
    body_temperature: float
    age: int
    weight_kg: float
    height_m: float
    gender: str
    patient_id: int

# --- LOGIC FUNCTIONS ---
def calculate_bmi(weight_kg, height_m):
    return round(weight_kg / (height_m ** 2), 2) if height_m > 0 else 0

@app.post("/predict")
async def predict(data: SensorData):
    try:
        timestamp = datetime.now()
        bmi = calculate_bmi(data.weight_kg, data.height_m)
        is_male = 1 if data.gender.lower() == 'male' else 0
        
        hour = timestamp.hour
        day_of_week = timestamp.weekday()
        is_night = 1 if 20 <= hour or hour < 6 else 0

        # Create DataFrame matching EXACT training feature names
        input_data = pd.DataFrame([{
            'Heart Rate': data.heart_rate,
            'Body Temperature': data.body_temperature,
            'Age': data.age,
            'Weight (kg)': data.weight_kg,
            'Height (m)': data.height_m,
            'Derived_BMI': bmi,
            'Hour': hour,
            'Day_of_Week': day_of_week,
            'Is_Night': is_night,
            'Gender_Male': is_male
        }])

        # Ensure feature order matches 'model_features.pkl'
        input_data = input_data[required_features]

        # Model Prediction
        prediction = model.predict(input_data)[0]
        probabilities = model.predict_proba(input_data)[0]
        prob_dict = dict(zip(model.classes_, probabilities))
        
        high_risk_prob = prob_dict.get('High Risk', 0)
        
        # Apply your Custom Logic for Medium Risk
        is_medium_risk = (90 <= data.heart_rate <= 100) or \
                         (37.6 <= data.body_temperature <= 38.2) or \
                         (25 <= bmi < 30)

        if is_medium_risk:
            final_risk = 'Medium Risk'
            alert_needed = high_risk_prob > 0.7
        else:
            final_risk = prediction
            alert_needed = (final_risk == 'High Risk') or (high_risk_prob > 0.7)

        return {
            'patient_id': data.patient_id,
            'predicted_risk': final_risk,
            'bmi': bmi,
            'high_risk_probability': round(float(high_risk_prob), 3),
            'alert': bool(alert_needed)
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=5000)