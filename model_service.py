from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import joblib
import pandas as pd
from datetime import datetime
import uvicorn
import numpy as np

app = FastAPI()

# --- LOAD ASSETS ---
try:
    model = joblib.load('clinical_risk_model.pkl')
    encoder = joblib.load('risk_encoder.pkl')
    expected_features = joblib.load('feature_columns.pkl')
    print("✅ Models and Feature List loaded successfully")
except Exception as e:
    print(f"❌ Error loading assets: {e}")

class SensorData(BaseModel):
    heart_rate: float
    body_temperature: float
    oxygen_saturation: float
    systolic_bp: float
    diastolic_bp: float
    age: int
    gender: str
    weight_kg: float
    height_m: float 
    patient_id: int

# --- REFINED CALCULATIONS ---
def calculate_clinical_metrics(data: SensorData):
    # Standard Clinical Formulas
    pulse_pressure = data.systolic_bp - data.diastolic_bp
    map_value = round(data.diastolic_bp + (pulse_pressure / 3), 2)
    return pulse_pressure, map_value
def calculate_bmi(weight_kg, height_m):
    bmi = weight_kg / (height_m ** 2)
    return round(bmi, 2)

@app.post("/predict")
async def predict(data: SensorData):
    try:
        pp, map_val = calculate_clinical_metrics(data)
        
        # 1. Reconstruct features with EXACT names used in Training
        # Note: I'm matching the 'columns_to_keep' list from your earlier training script
        input_dict = {
            'Heart Rate': data.heart_rate,
            'Body Temperature': data.body_temperature,
            'Oxygen Saturation': data.oxygen_saturation,
            'Systolic Blood Pressure': data.systolic_bp,
            'Diastolic Blood Pressure': data.diastolic_bp,
            'Age': data.age,
            'Gender': data.gender.capitalize(),
            'Derived_Pulse_Pressure': pp,
            'Derived_BMI': calculate_bmi(data.weight_kg, data.height_m),
            'Derived_MAP': map_val
        }

        input_df = pd.DataFrame([input_dict])

        # 2. Match Feature Order
        input_df = input_df[expected_features]

        # 3. Handle Categorical Types (Crucial for XGBoost)
        for col in input_df.columns:
            if input_df[col].dtype == 'object':
                input_df[col] = input_df[col].astype('category')

        # 4. PREDICTION
        # Get the integer prediction and the raw probabilities
        pred_int = model.predict(input_df)[0]
        probabilities = model.predict_proba(input_df)[0]

        # Convert integer back to string (e.g., 2 -> 'High Risk')
        risk_label = encoder.inverse_transform([pred_int])[0]

        # Map probabilities to class names
        prob_map = {str(cls): round(float(prob), 4) for cls, prob in zip(encoder.classes_, probabilities)}
        
        # 5. ALERT LOGIC
        # Find index for 'High Risk' in the encoder to check its specific probability
        # We handle case sensitivity by searching the encoder classes
        high_risk_label = next((s for s in encoder.classes_ if 'high' in str(s).lower()), None)
        high_risk_prob = prob_map.get(str(high_risk_label), 0) if high_risk_label else 0
        
        alert_needed = (risk_label == high_risk_label) or (high_risk_prob > 0.70)

        return {
            'patient_id': data.patient_id,
            'predicted_risk': str(risk_label),
            'metrics': {
                'pulse_pressure': pp,
                'mean_arterial_pressure': map_val,
                'bmi': input_dict['Derived_BMI']

            },
            'probabilities': prob_map,
            'alert': bool(alert_needed),
            'timestamp': datetime.now().isoformat()
        }

    except Exception as e:
        print(f"Prediction Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5000)