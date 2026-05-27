from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import joblib
import pandas as pd
from datetime import datetime
import uvicorn
import numpy as np

app = FastAPI()


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    raw_body = await request.body()
    print("VALIDATION ERROR:", exc.errors())
    print("RAW BODY:", raw_body.decode("utf-8", errors="replace"))
    return JSONResponse(status_code=422, content={"detail": exc.errors()})

# ══════════════════════════════════════════════════════
# HARDCODED CONFIG (no model_config.pkl needed)
# ══════════════════════════════════════════════════════
EXPECTED_FEATURES   = ['heart_rate', 'spo2', 'systolic_bp',
                        'diastolic_bp', 'temperature', 'age', 'gender']
HIGH_RISK_THRESHOLD = 0.3

# ══════════════════════════════════════════════════════
# LOAD ASSETS
# ══════════════════════════════════════════════════════
try:
    model   = joblib.load('rf_risk_model.pkl')
    scaler  = joblib.load('scaler.pkl')
    encoder = joblib.load('label_encoder_risk.pkl')
    print("✅ RF Risk Model loaded successfully")
    print(f"   Classes   : {encoder.classes_}")
    print(f"   Threshold : {HIGH_RISK_THRESHOLD}")
except Exception as e:
    print(f"❌ Error loading assets: {e}")

# ══════════════════════════════════════════════════════
# REQUEST SCHEMA
# ══════════════════════════════════════════════════════
class SensorData(BaseModel):
    heart_rate   : float
    spo2         : float    # ← was oxygen_saturation in old API
    systolic_bp  : float
    diastolic_bp : float
    temperature  : float    # ← was body_temperature in old API
    age          : int
    gender       : str      # 'M' or 'F'
    patient_id   : int

# ══════════════════════════════════════════════════════
# PREDICT ENDPOINT
# ══════════════════════════════════════════════════════
@app.post("/predict")
async def predict(data: SensorData):
    try:
        print("DEBUG /predict payload:", data.dict())
        # 1. Encode gender
        gender_encoded = 0 if data.gender.upper() == 'M' else 1

        # 2. Build input DataFrame
        input_dict = {
            'heart_rate'  : data.heart_rate,
            'spo2'        : data.spo2,
            'systolic_bp' : data.systolic_bp,
            'diastolic_bp': data.diastolic_bp,
            'temperature' : data.temperature,
            'age'         : data.age,
            'gender'      : gender_encoded
        }
        input_df = pd.DataFrame([input_dict])[EXPECTED_FEATURES]

        # 3. Scale
        scaled_data = scaler.transform(input_df)

        # 4. Predict with tuned threshold
        probabilities = model.predict_proba(scaled_data)[0]
        high_idx      = list(encoder.classes_).index('High')
        prob_high     = float(probabilities[high_idx])

        if prob_high >= HIGH_RISK_THRESHOLD:
            risk_label = 'High'
        else:
            pred_idx   = int(np.argmax(probabilities))
            risk_label = encoder.classes_[pred_idx]

        # 5. Probability map
        prob_map = {
            cls: round(float(prob), 4)
            for cls, prob in zip(encoder.classes_, probabilities)
        }

        # 6. Alert
        alert_needed = risk_label == 'High'
        print("debug / prediction:", risk_label)
        return {
            'patient_id'    : data.patient_id,
            'predicted_risk': risk_label,
            'probabilities' : prob_map,
            'high_risk_prob': round(prob_high, 4),
            'alert'         : bool(alert_needed),
            'threshold_used': HIGH_RISK_THRESHOLD,
            'timestamp'     : datetime.now().isoformat()
        }

    except Exception as e:
        print(f"Prediction Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# ══════════════════════════════════════════════════════
# HEALTH CHECK
# ══════════════════════════════════════════════════════
@app.get("/health")
async def health():
    return {
        "status"   : "ok",
        "model"    : "RandomForest Risk Classifier v1.0",
        "classes"  : list(encoder.classes_),
        "features" : EXPECTED_FEATURES,
        "threshold": HIGH_RISK_THRESHOLD
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5000)