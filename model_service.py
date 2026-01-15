from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
import pandas as pd
import numpy as np
import pickle
from datetime import datetime
import uvicorn
import logging

# =========================
# LOGGING SETUP
# =========================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler("medical_api.log"),  # log to file
        logging.StreamHandler()                  # log to console
    ]
)
logger = logging.getLogger(__name__)

app = FastAPI(title="Medical Risk Prediction API")

# =========================
# LOAD MODEL & ENCODER
# =========================
try:
    with open("risk_category_model.pkl", "rb") as f:
        saved_data = pickle.load(f)

    model = saved_data["model"]
    label_encoder = saved_data["label_encoder"]

    logger.info("✅ Model & encoder loaded successfully")

except Exception as e:
    logger.exception("❌ Model loading failed")
    raise RuntimeError("Model loading error") from e

# =========================
# DATA SCHEMA
# =========================
class SensorData(BaseModel):
    heart_rate: float
    body_temperature: float
    age: int
    weight_kg: float
    height_m: float
    gender: str
    patient_id: int

# =========================
# UTILITY FUNCTIONS
# =========================
def calculate_bmi(weight_kg, height_m):
    bmi = round(weight_kg / (height_m ** 2), 2) if height_m > 0 else 0
    logger.debug(f"Calculated BMI: {bmi}")
    return bmi

# =========================
# MEDICAL GUARDRAILS
# =========================
def medical_guardrails(data):
    hr = data["Heart Rate"]
    temp = data["Body Temperature"]
    bmi = data["Derived_BMI"]
    age = data["Age"]

    if temp >= 40.0:
        logger.warning(f"High fever detected: {temp}°C")
        return "High Risk", "Rule: Extreme fever"

    if hr <= 40 or hr >= 140:
        logger.warning(f"Dangerous heart rate detected: {hr} bpm")
        return "High Risk", "Rule: Dangerous heart rate"

    if bmi >= 40:
        logger.warning(f"Morbid obesity detected: BMI={bmi}")
        return "High Risk", "Rule: Morbid obesity"

    if age >= 65 and temp >= 38.0:
        return "High Risk", "Rule: Elderly + fever"

    if age <= 2 and (temp >= 38.5 or hr >= 160):
        return "High Risk", "Rule: Infant danger zone"

    return None, None

# =========================
# CONFIDENCE-BASED LOGIC
# =========================
def confidence_based_adjustment(pred_label, probs, threshold=0.60):
    max_prob = max(probs.values())
    if max_prob < threshold:
        logger.info(f"Low confidence ({max_prob:.2f}) → escalated to Medium Risk")
        return "Medium Risk", "Low confidence → escalated to Medium Risk"
    return pred_label, "High confidence prediction"

# =========================
# EXPLAINABILITY
# =========================
def explain_prediction(model, X_row):
    clf = model.named_steps["classifier"]
    if hasattr(clf, "feature_importances_"):
        feature_names = model.named_steps["preprocessor"].get_feature_names_out()
        importances = clf.feature_importances_
        explanation = sorted(
            zip(feature_names, importances),
            key=lambda x: x[1],
            reverse=True
        )[:5]
        logger.debug(f"Feature importance explanation: {explanation}")
        return explanation
    return "Explainability not supported"

# =========================
# PREDICTION ENDPOINT
# =========================
@app.post("/predict")
async def predict(data: SensorData, request: Request):
    try:
        timestamp = datetime.now()
        logger.info(f"Received prediction request from patient_id={data.patient_id} | {request.client.host}")

        bmi = calculate_bmi(data.weight_kg, data.height_m)
        is_male = 1 if data.gender.lower() == "male" else 0

        hour = timestamp.hour
        day_of_week = timestamp.weekday()
        is_night = 1 if 20 <= hour or hour < 6 else 0

        input_dict = {
            "Heart Rate": data.heart_rate,
            "Body Temperature": data.body_temperature,
            "Age": data.age,
            "Weight (kg)": data.weight_kg,
            "Height (m)": data.height_m,
            "Derived_BMI": bmi,
            "Hour": hour,
            "Day_of_Week": day_of_week,
            "Is_Night": is_night,
            "Gender": data.gender,
        }

        # 1️⃣ Medical guardrails
        rule_result, rule_note = medical_guardrails(input_dict)
        if rule_result:
            logger.info(f"Medical rule triggered for patient_id={data.patient_id}: {rule_note}")
            return {
                "patient_id": data.patient_id,
                "predicted_risk": rule_result,
                "bmi": bmi,
                "note": rule_note,
                "source": "medical_rule",
                "alert": True
            }

        # 2️⃣ ML prediction
        proba = model.predict_proba(pd.DataFrame([input_dict]))[0]
        classes = label_encoder.inverse_transform(np.arange(len(proba)))
        probs = dict(zip(classes, np.round(proba, 3)))
        ml_pred = classes[np.argmax(proba)]

        logger.info(f"ML prediction for patient_id={data.patient_id}: {ml_pred} | probs={probs}")

        # 3️⃣ Confidence adjustment
        final_pred, confidence_note = confidence_based_adjustment(ml_pred, probs)

        # 4️⃣ Explainability
        explanation = explain_prediction(model, pd.DataFrame([input_dict]))
        alert_needed = final_pred == "High Risk"

        return {
            "patient_id": data.patient_id,
            "predicted_risk": final_pred,
            "bmi": bmi,
            "probabilities": probs,
            "note": confidence_note,
            "source": "ml_model",
            "alert": alert_needed,
            "explanation": explanation
        }

    except Exception as e:
        logger.exception(f"Error during prediction for patient_id={data.patient_id}")
        raise HTTPException(status_code=500, detail=str(e))


# =========================
# RUN SERVER
# =========================
if __name__ == "__main__":
    logger.info("Starting Medical Risk Prediction API...")
    uvicorn.run(app, host="127.0.0.1", port=5000)
