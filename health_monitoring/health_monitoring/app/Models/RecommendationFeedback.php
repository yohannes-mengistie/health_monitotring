<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class RecommendationFeedback extends Model
{
    protected $fillable = [
        'clinical_assessment_id',
        'user_id',
        'action',
        'note',
    ];

    protected $casts = [
        'action' => 'string',
    ];

    public function clinicalAssessment(): BelongsTo
    {
        return $this->belongsTo(ClinicalAssessment::class, 'clinical_assessment_id');
    }
}
