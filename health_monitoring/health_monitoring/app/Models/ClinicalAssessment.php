<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

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
        'structured_response',
        'ai_success',
        'ai_model',
        'predicted_risk',
        'risk_level',
        'language',
        'requires_review',
        'vitals_snapshot',
        'recommendation_excerpt',
    ];

    protected $casts = [
        'structured_response' => 'array',
        'vitals_snapshot' => 'array',
        'requires_review' => 'boolean',
        'known_conditions' => 'array',
        'opqrst' => 'array',
        'structured_assessment' => 'array',
        'high_risk' => 'boolean',
        'red_flag_yes' => 'boolean',
        'ai_success' => 'boolean',
        'severity' => 'integer',
        'created_at' => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function feedback(): HasMany
    {
        return $this->hasMany(RecommendationFeedback::class, 'clinical_assessment_id');
    }
}
