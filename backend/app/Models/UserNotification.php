<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'user_id',
    'complaint_id',
    'type',
    'title',
    'message',
    'is_read',
])]
class UserNotification extends Model
{
    protected function casts(): array
    {
        return [
            'is_read' => 'boolean',
            'complaint_id' => 'integer',
            'user_id' => 'integer',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function complaint(): BelongsTo
    {
        return $this->belongsTo(Complaint::class);
    }

    /** Shape expected by the Flutter NotificationApi client. */
    public function toApiArray(): array
    {
        return [
            'id' => (string) $this->id,
            'complaintId' => $this->complaint_id !== null ? (string) $this->complaint_id : '',
            'type' => $this->type,
            'title' => $this->title,
            'message' => $this->message,
            'isRead' => (bool) $this->is_read,
            'createdAt' => $this->created_at?->toIso8601String(),
        ];
    }
}
