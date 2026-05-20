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
        
        # 1. Reconstruct features
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

        # 3. Handle Categorical Types (UPDATED LOGIC)
        # Best Practice: Explicitly convert known categorical columns
        # Assuming 'Gender' is your only categorical column. Add others if necessary.
        categorical_cols = ['Gender'] 
        
        for col in categorical_cols:
            if col in input_df.columns:
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






# from fastapi import FastAPI, HTTPException
# from pydantic import BaseModel
# import joblib
# import pandas as pd
# from datetime import datetime
# import uvicorn
# import numpy as np

# app = FastAPI()

# # --- LOAD NEW ASSETS ---
# try:
#     # Using the XGBoost model as the primary, but you can swap to rf_model if preferred
#     model = joblib.load('vital_signs_xgb_model_3class.pkl') 
#     scaler = joblib.load('scaler_3class.pkl')
#     encoder = joblib.load('label_encoder_3class.pkl')
    
#     # Note: If your new script didn't save 'feature_columns.pkl', 
#     # ensure these match the order of columns in your training DataFrame exactly.
#     expected_features = [
#         'Heart Rate', 'Body Temperature', 'Oxygen Saturation', 
#         'Systolic Blood Pressure', 'Diastolic Blood Pressure', 'Age', 
#         'Gender', 'Derived_Pulse_Pressure', 'Derived_BMI', 'Derived_MAP'
#     ]
#     print("✅ New 3-Class Models and Scaler loaded successfully")
# except Exception as e:
#     print(f"❌ Error loading assets: {e}")

# class SensorData(BaseModel):
#     heart_rate: float
#     body_temperature: float
#     oxygen_saturation: float
#     systolic_bp: float
#     diastolic_bp: float
#     age: int
#     gender: str
#     weight_kg: float
#     height_m: float 
#     patient_id: int


# def resolve_class_labels(model_obj, encoder_obj, num_classes):
#     if hasattr(model_obj, "classes_"):
#         labels = list(model_obj.classes_)
#         if len(labels) == num_classes:
#             return labels

#     if hasattr(encoder_obj, "classes_"):
#         labels = list(encoder_obj.classes_)
#         if len(labels) == num_classes:
#             return labels

#     return list(range(num_classes))


# def decode_risk_label(prediction, model_obj, encoder_obj):
#     try:
#         return encoder_obj.inverse_transform([prediction])[0]
#     except Exception:
#         labels = getattr(model_obj, "classes_", None)
#         if labels is not None and 0 <= int(prediction) < len(labels):
#             return labels[int(prediction)]
#         return prediction


# RISK_LABEL_MAP = {
#     0: "Low",
#     1: "Moderate",
#     2: "High",
# }

# def calculate_clinical_metrics(data: SensorData):
#     pulse_pressure = data.systolic_bp - data.diastolic_bp
#     map_value = round(data.diastolic_bp + (pulse_pressure / 3), 2)
#     return pulse_pressure, map_value

# def calculate_bmi(weight_kg, height_m):
#     return round(weight_kg / (height_m ** 2), 2)

# @app.post("/predict")
# async def predict(data: SensorData):
#     try:
#         pp, map_val = calculate_clinical_metrics(data)
        
#         # 1. Reconstruct features
#         input_dict = {
#             'Heart Rate': data.heart_rate,
#             'Body Temperature': data.body_temperature,
#             'Oxygen Saturation': data.oxygen_saturation,
#             'Systolic Blood Pressure': data.systolic_bp,
#             'Diastolic Blood Pressure': data.diastolic_bp,
#             'Age': data.age,
#             'Gender': 1 if data.gender.lower() == 'male' else 0, # Manual encoding if LE wasn't used for Gender
#             'Derived_Pulse_Pressure': pp,
#             'Derived_BMI': calculate_bmi(data.weight_kg, data.height_m),
#             'Derived_MAP': map_val
#         }

#         input_df = pd.DataFrame([input_dict])

#         # 2. Match Feature Order
#         input_df = input_df[expected_features]

#         # 3. NEW STEP: SCALING
#         # The new model expects data in the same scale as the training set
#         scaled_data = scaler.transform(input_df)

#         # 4. PREDICTION
#         pred_int = model.predict(scaled_data)[0]
#         probabilities = model.predict_proba(scaled_data)[0]

#         # 5. DECODE LABEL
#         pred_index = int(pred_int)
#         risk_label = RISK_LABEL_MAP.get(pred_index, str(pred_int))

#         class_labels = [
#             RISK_LABEL_MAP.get(idx, str(idx))
#             for idx in range(len(probabilities))
#         ]
#         prob_map = {
#             str(cls): round(float(prob), 4)
#             for cls, prob in zip(class_labels, probabilities)
#         }
        
#         # 6. ALERT LOGIC
#         # Checks if the word 'high' exists in the predicted label
#         alert_needed = 'high' in str(risk_label).lower() or any(
#             prob > 0.70 for cls, prob in prob_map.items() if 'high' in str(cls).lower()
#         )

#         return {
#             'patient_id': data.patient_id,
#             'predicted_risk': str(risk_label),
#             'metrics': {
#                 'pulse_pressure': pp,
#                 'mean_arterial_pressure': map_val,
#                 'bmi': input_dict['Derived_BMI']
#             },
#             'probabilities': prob_map,
#             'alert': bool(alert_needed),
#             'timestamp': datetime.now().isoformat()
#         }

#     except Exception as e:
#         print(f"Prediction Error: {e}")
#         raise HTTPException(status_code=500, detail=str(e))

# if __name__ == "__main__":
#     uvicorn.run(app, host="0.0.0.0", port=5000)