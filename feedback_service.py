import joblib
import pandas as pd
import numpy as np
import xgboost as xgb
from fastapi import FastAPI, Request, HTTPException
from google import genai
import uvicorn

app = FastAPI(title="Clinical AI - Final Thesis Refactor")

# --- 1. SETUP ---
GEMINI_API_KEY = ""
client = genai.Client(api_key=GEMINI_API_KEY)

try:
    # Load the Scikit-learn wrapper
    model_wrapper = joblib.load('clinical_risk_model.pkl')
    risk_encoder = joblib.load('risk_encoder.pkl')
    explainer = joblib.load('shap_explainer.pkl')
    
    # Use the specific features you defined in your training
    expected_features = [
        'Heart Rate', 'Body Temperature', 'Oxygen Saturation',
        'Systolic Blood Pressure', 'Diastolic Blood Pressure', 'Age',
        'Gender', 'Derived_Pulse_Pressure', 'Derived_BMI', 'Derived_MAP'
    ]
    
    # Extract raw booster to bypass high-level validation
    booster = model_wrapper.get_booster() if hasattr(model_wrapper, 'get_booster') else model_wrapper
    print("✅ System Ready. Gender mapping enabled.")
except Exception as e:
    print(f"❌ Load Error: {e}")

@app.post("/generate-clinical-report")
async def generate_report(request: Request):
    try:
        body = await request.json()
        vitals = body.get('vitals', {})
        lang = body.get('language', 'amharic').lower()
        scenario_name = body.get('scenario_name', 'Live Monitoring')

        # --- 2. THE FIX: MANUAL ENCODING ---
        df = pd.DataFrame([vitals])
        
        # Manually convert Gender string to numeric (0 or 1)
        # This fixes the "Invalid columns: Gender: str" error
        if 'Gender' in df.columns:
            df['Gender'] = df['Gender'].apply(
                lambda x: 1 if str(x).lower() in ['male', 'm', '1', '1.0'] else 0
            )

        # Reindex ensures all 10 features exist in the right order
        df = df.reindex(columns=expected_features, fill_value=0)

        # Force all columns to numeric float32
        df = df.apply(pd.to_numeric, errors='coerce').fillna(0).astype(np.float32)

        # --- 3. PREDICTION ---
        # Using DMatrix to ensure no categorical metadata remains
        dmatrix = xgb.DMatrix(df)
        y_prob = booster.predict(dmatrix)
        
        # Get the predicted class index
        if len(y_prob.shape) > 1:
            pred_idx = int(np.argmax(y_prob, axis=1)[0])
        else:
            pred_idx = int((y_prob > 0.5)[0])

        risk_label = risk_encoder.inverse_transform([pred_idx])[0]

        # --- 4. SHAP EXPLAINABILITY ---
        shap_values = explainer.shap_values(df.values)
        if isinstance(shap_values, list):
            shap_array = shap_values[pred_idx][0]
        elif hasattr(shap_values, 'shape') and len(shap_values.shape) == 3:
            shap_array = shap_values[0, :, pred_idx]
        else:
            shap_array = shap_values[0]

        feature_impacts = []
        patient_series = df.iloc[0]
        for i, col in enumerate(df.columns):
            impact = float(shap_array[i])
            value = patient_series[col]
            direction = "↑ Increased Risk" if impact > 0 else "↓ Decreased Risk"
            feature_impacts.append((col, value, impact, direction))

        feature_impacts.sort(key=lambda x: abs(x[2]), reverse=True)
        top_3 = feature_impacts[:3]
        driver_text = ""
        for col, val, impact, direction in top_3:
            driver_text += f"- {col} ({val}) -> {direction} (SHAP: {impact:.4f})\\n"

        # --- 5. GEMINI CLINICAL REPORT ---
        vitals_formatted = "\n".join([f"- {k}: {v}" for k, v in vitals.items()])
        instruction = """
        CRITICAL INSTRUCTION: Write the ENTIRE report in AMHARIC (አማርኛ).
        Use professional, empathetic, and patient-friendly language.
        """ if lang == 'amharic' else "Write the entire report in English."

        prompt = f"""
        You are a Board-Certified Internal Medicine Physician.

        TEST SCENARIO: {scenario_name}

        PATIENT VITALS:
        {vitals_formatted}

        AI MODEL OUTPUT: {str(risk_label).upper()} RISK

        TOP 3 MOST INFLUENTIAL FACTORS (according to SHAP):
        {driver_text}

        {instruction}

        TASK:
        Write a clear, professional clinical summary using this exact structure:

        ### 🩺 Clinical Assessment
        (Give 2-3 sentences explaining the overall clinical picture and why the model predicted {str(risk_label).upper()} risk. Be honest about the acute vs chronic factors.)

        ### 🎯 Key Focus Areas
        (For each of the top 3 factors, explain in simple language whether it increased or decreased the predicted risk and why it matters clinically.)

        ### 📋 Recommended Actions
        (Give 3 practical, specific, and safe recommendations based on the actual numbers. Prioritize urgent issues first.)

        *Disclaimer: This is an AI-generated educational summary. Please consult a qualified doctor for proper medical advice.*
        """

        response = client.models.generate_content(
            model='gemini-2.5-flash',
            config=genai.types.GenerateContentConfig(temperature=0.25),
            contents=prompt,
        )

        return {
            "status": "success",
            "predicted_risk": str(risk_label).upper(),
            "report": response.text,
            "top_factors": [
                {
                    "feature": col,
                    "value": float(val) if isinstance(val, (int, float, np.number)) else str(val),
                    "shap": round(float(impact), 6),
                    "direction": direction,
                }
                for col, val, impact, direction in top_3
            ],
        }

    except Exception as e:
        print(f"❌ Error during inference: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=9000)