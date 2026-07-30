<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'user_id', 'assigned_to_id', 'category_id', 'priority_id', 'village', 'panchayat',
    'description', 'lat', 'long', 'before_photo_url', 'during_photo_url', 'after_photo_url',
    'voice_note_url', 'status', 'citizen_rating', 'citizen_feedback', 'duplicate_of_id',
    'verified_at', 'verified_by_id',
])]
class Complaint extends Model
{
    protected function casts(): array
    {
        return [
            'category_id' => 'integer',
            'priority_id' => 'integer',
            'assigned_to_id' => 'integer',
            'duplicate_of_id' => 'integer',
            'verified_by_id' => 'integer',
            'lat' => 'float',
            'long' => 'float',
            'citizen_rating' => 'integer',
            'verified_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function assignedTo(): BelongsTo
    {
        return $this->belongsTo(User::class, 'assigned_to_id');
    }

    public function verifiedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'verified_by_id');
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(ComplaintCategory::class, 'category_id');
    }

    public function priority(): BelongsTo
    {
        return $this->belongsTo(ComplaintPriority::class, 'priority_id');
    }

    public function timeline(): HasMany
    {
        return $this->hasMany(ComplaintTimelineEvent::class)->orderBy('created_at');
    }

    public function transfers(): HasMany
    {
        return $this->hasMany(ComplaintTransfer::class)->orderBy('created_at');
    }

    public function duplicateOf(): BelongsTo
    {
        return $this->belongsTo(Complaint::class, 'duplicate_of_id');
    }
}
