<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'user_id', 'assigned_to_id', 'category_id', 'priority_id', 'village', 'panchayat',
    'district_id', 'tehsil_id', 'village_id', 'panchayat_id',
    'department_id', 'asset_type_id',
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
            'department_id' => 'integer',
            'asset_type_id' => 'integer',
            'district_id' => 'integer',
            'tehsil_id' => 'integer',
            'village_id' => 'integer',
            'panchayat_id' => 'integer',
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

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    public function assetType(): BelongsTo
    {
        return $this->belongsTo(AssetType::class);
    }

    public function district(): BelongsTo
    {
        return $this->belongsTo(District::class);
    }

    public function tehsil(): BelongsTo
    {
        return $this->belongsTo(Tehsil::class);
    }

    public function villageMaster(): BelongsTo
    {
        return $this->belongsTo(Village::class, 'village_id');
    }

    public function panchayatMaster(): BelongsTo
    {
        return $this->belongsTo(Panchayat::class, 'panchayat_id');
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
