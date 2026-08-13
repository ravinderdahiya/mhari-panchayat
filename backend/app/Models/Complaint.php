<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

#[Fillable([
    'user_id', 'assigned_to_id', 'category_id', 'priority_id', 'village', 'panchayat',
    'district_id', 'tehsil_id', 'village_id', 'panchayat_id',
    'location_state', 'location_district', 'location_tehsil', 'location_block',
    'department_id', 'asset_type_id',
    'description', 'lat', 'long', 'before_photo_url', 'issue_photo_urls',
    'during_photo_url', 'after_photo_url',
    'voice_note_url', 'status', 'citizen_rating', 'citizen_feedback', 'duplicate_of_id',
    'verified_at', 'verified_by_id',
    'sla_due_at', 'escalation_level', 'escalated_at', 'resolved_at',
])]
class Complaint extends Model
{
    protected static function booted(): void
    {
        static::creating(function (Complaint $complaint) {
            $complaint->code ??= self::generateCode($complaint->district_id);
        });
    }

    // COMP-{districtShortCode}-{MM_YYYY}-{seq}, seq resetting to 1 each month
    // per district. `complaint_sequences` holds the last issued number per
    // (district, year, month) row, locked with SELECT ... FOR UPDATE so two
    // complaints filed at the same moment in the same district never get the
    // same number. Districtless complaints (district_id is nullable on this
    // table) share sequence bucket 0 and code "GEN" - matching the "GEN"
    // fallback UserController already uses for district-less employee IDs.
    private static function generateCode(?int $districtId): string
    {
        $districtCode = $districtId ? District::find($districtId)?->short_code : null;
        $districtCode ??= 'GEN';

        $year = (int) now()->format('Y');
        $month = (int) now()->format('n');
        $key = ['district_id' => $districtId ?? 0, 'year' => $year, 'month' => $month];

        $sequenceNumber = DB::transaction(function () use ($key) {
            $sequence = ComplaintSequence::where($key)->lockForUpdate()->first();

            if (! $sequence) {
                try {
                    $sequence = ComplaintSequence::create([...$key, 'last_number' => 0]);
                } catch (QueryException) {
                    // Lost the create race to a concurrent request - read its row instead.
                    $sequence = ComplaintSequence::where($key)->lockForUpdate()->firstOrFail();
                }
            }

            $sequence->increment('last_number');

            return $sequence->last_number;
        });

        $monthYear = sprintf('%02d_%04d', $month, $year);
        $paddedNumber = str_pad((string) $sequenceNumber, 3, '0', STR_PAD_LEFT);

        return "COMP-{$districtCode}-{$monthYear}-{$paddedNumber}";
    }

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
            'issue_photo_urls' => 'array',
            'citizen_rating' => 'integer',
            'verified_at' => 'datetime',
            'sla_due_at' => 'datetime',
            'escalation_level' => 'integer',
            'escalated_at' => 'datetime',
            'resolved_at' => 'datetime',
        ];
    }

    // Called by every status-changing controller action so the SLA clock
    // always reflects "time since last action", not just time since filing.
    public function refreshSlaDueAt(): void
    {
        $hours = $this->priority?->sla_hours;
        $this->sla_due_at = $hours ? now()->addHours($hours) : null;
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
