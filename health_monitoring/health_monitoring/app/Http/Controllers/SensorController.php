<?php
namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use App\Events\HealthUpdateEvent;
use App\Models\HealthData;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;

class SensorController extends Controller
{
    public function ingest(Request $request)
    {
        Log::debug('incoming health data' , ['payload'=> $request->all()]);
        // 1. Get the authenticated user (via Sanctum token)
        $user = Auth::user();

        if (!$user) {
            Log::warning('Unauthenticated request', ['headers' => $request->headers->all()]);
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        // 2. Validate incoming vitals from the Python Listener
        $vitals = $request->validate([
            'heart_rate' => 'required|numeric',
            'body_temperature' => 'required|numeric',
            'oxygen_saturation' => 'required|numeric',
        ]);
        Log::info('Vitals validated', ['vitals' => $vitals, 'user_id' => $user->id]);
        
        $mlPayload = [
            'heart_rate'       => (float)$vitals['heart_rate'],       
            'body_temperature' => (float)$vitals['body_temperature'],  
            'oxygen_saturation'=> (float)$vitals['oxygen_saturation'], 
            'systolic_bp'      => (float)$user->systolic_bp,          
            'diastolic_bp'     => (float)$user->diastolic_bp,          
            'age'              => (int)(date('Y') - date('Y', strtotime($user->dob))),
            'weight_kg'        => (float)$user->weight,
            'height_m'         => (float)$user->height,
            'gender'           => $user->gender ?? 'M',
            'patient_id'       => (int)$user->id
        ];
        Log::debug('ML Payload prepared', ['mlPayload' => $mlPayload]);
        // 4. Call the Python ML FastAPI Service
        try {
            $response = Http::timeout(3)->post('http://127.0.0.1:5000/predict', $mlPayload);

            if ($response->failed()) {
                throw new \Exception("ML Service returned an error");
            }

            $mlResult = $response->json();
            $pulsePressure = $mlResult['metrics']['pulse_pressure'] ?? null;
            $mapValue      = $mlResult['metrics']['mean_arterial_pressure'] ?? null;
            $bmi = $mlResult['metrics']['bmi'] ?? (
                    $user->weight && $user->height
                        ? round($user->weight / ($user->height * $user->height), 2)
                        : null
                );
        } catch (\Exception $e) {
           Log::error('ML service error', [
                'error' => $e->getMessage(),
                'payload' => $request->all()
            ]);
            return response()->json([
                'error' => 'Machine Learning Service Unavailable',
                'message' => $e->getMessage()
            ], 503);
        }

        // 5. Broadcast to Frontend via WebSockets
        // We pass the User ID so the frontend can listen on a private channel
        //broadcast(new HealthUpdateEvent($user->id, $mlResult, $vitals))->toOthers();

        $healthData = HealthData::create([
            'heart_rate'       => (float)$vitals['heart_rate'],        
            'body_temperature' => (float)$vitals['body_temperature'],  
            'oxygen_saturation'=> (float)$vitals['oxygen_saturation'], 
            'systolic_bp'      => (float)$user->systolic_bp,           
            'diastolic_bp'     => (float)$user->diastolic_bp,          
            'age'              => (int)(date('Y') - date('Y', strtotime($user->dob))),
            'weight_kg'        => (float)$user->weight,
            'height_m'         => (float)$user->height,
            'gender'           => $user->gender ?? 'M',
            'user_id'       => (int)$user->id,
            'bmi'           =>  $bmi,
            'pulse_pressure' => $pulsePressure,
            'map'            => $mapValue,
            'device_id'      => 1,
            'predicted_risk' => $mlResult['predicted_risk'],
            'probabilities'  => $mlResult['probabilities'],
            'alert'          => $mlResult['alert']

        ]);
        Log::info('HealthData saved', ['healthData_id' => $healthData->id]);
        return response()->json([
            'status' => 'success',
            'data' => [
                'vitals' => $vitals,
                'analysis' => $mlResult
            ]
        ]);
    }

    public function getDetailedAnalysis(Request $request)
    {
        $user = Auth::user();
        $latest = HealthData::where('user_id', $user->id)->latest()->first();

        if (!$latest) {
            return response()->json(['error' => 'No data found'], 404);
        }

        try {
            $response = Http::timeout(20)->post('http://127.0.0.1:9000/generate-clinical-report', [
                'language' => $request->get('lang', 'amharic'),
                'vitals' => [
                    // MUST MATCH Python expected_features EXACTLY
                    'Heart Rate'              => (float)$latest->heart_rate,
                    'Body Temperature'       => (float)$latest->body_temperature,
                    'Oxygen Saturation'      => (float)$latest->oxygen_saturation,
                    'Systolic Blood Pressure' => (float)$latest->systolic_bp,
                    'Diastolic Blood Pressure'=> (float)$latest->diastolic_bp,
                    'Age'                     => (int)$latest->age,
                    'Gender'                  => $latest->gender, // e.g., "Male"
                    'Derived_Pulse_Pressure'  => (float)$latest->pulse_pressure,
                    'Derived_BMI'             => (float)$latest->bmi,
                    'Derived_MAP'             => (float)$latest->map,
                ]
            ]);

            return response()->json($response->json());
        } catch (\Exception $e) {
            return response()->json(['error' => 'AI Service Unavailable: ' . $e->getMessage()], 503);
        }
    }
}
