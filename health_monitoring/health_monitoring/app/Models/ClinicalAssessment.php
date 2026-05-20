<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ClinicalAssessment extends Model
{
    protected $fillable = [
        'user_id',
        'source_endpoint',
        'symptom_key',
        'symptom_label',
        'severity',
        'high_risk',
        'red_flag_yes',
        'medication_taken_today',
        'known_conditions',
        'opqrst',
        'structured_assessment',
        'ai_success',
        'ai_model',
        'predicted_risk',
        'recommendation_excerpt',
    ];

    protected $casts = [
        'known_conditions' => 'array',
        'opqrst' => 'array',
        'structured_assessment' => 'array',
        'high_risk' => 'boolean',
        'red_flag_yes' => 'boolean',
        'ai_success' => 'boolean',
        'severity' => 'integer',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
