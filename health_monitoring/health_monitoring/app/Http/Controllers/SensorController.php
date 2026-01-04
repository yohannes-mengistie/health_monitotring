<?php
namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use App\Events\HealthUpdateEvent;
use Illuminate\Support\Facades\Auth;

class SensorController extends Controller
{
    public function ingest(Request $request)
    {
        // 1. Get the authenticated user (via Sanctum token)
        $user = Auth::user();

        if (!$user) {
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        // 2. Validate incoming vitals from the Python Listener
        $vitals = $request->validate([
            'heart_rate' => 'required|numeric',
            'body_temperature' => 'required|numeric',
        ]);

        // 3. Prepare payload using real User data
        // $user->age is the dynamic accessor we created in the Model
        $mlPayload = [
            'heart_rate'       => $vitals['heart_rate'],
            'body_temperature' => $vitals['body_temperature'],
            'age'              => $user->age,
            'weight_kg'        => $user->weight,
            'height_m'         => $user->height,
            'gender'           => $user->gender,
            'patient_id'       => $user->id,
        ];

        // 4. Call the Python ML FastAPI Service
        try {
            $response = Http::timeout(3)->post('http://127.0.0.1:5000/predict', $mlPayload);

            if ($response->failed()) {
                throw new \Exception("ML Service returned an error");
            }

            $mlResult = $response->json();
        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Machine Learning Service Unavailable',
                'message' => $e->getMessage()
            ], 503);
        }

        // 5. Broadcast to Frontend via WebSockets
        // We pass the User ID so the frontend can listen on a private channel
        broadcast(new HealthUpdateEvent($user->id, $mlResult, $vitals))->toOthers();

        return response()->json([
            'status' => 'success',
            'data' => [
                'vitals' => $vitals,
                'analysis' => $mlResult
            ]
        ]);
    }
}
