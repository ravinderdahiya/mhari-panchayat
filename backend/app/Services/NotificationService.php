<?php

namespace App\Services;

use App\Models\Complaint;
use App\Models\UserNotification;

class NotificationService
{
    public const TYPE_SUBMITTED = 'COMPLAINT_SUBMITTED';

    public const TYPE_ASSIGNED = 'COMPLAINT_ASSIGNED';

    public const TYPE_RESOLVED = 'COMPLAINT_RESOLVED';

    public const TYPE_REJECTED = 'COMPLAINT_REJECTED';

    public function notify(
        int $userId,
        string $type,
        string $title,
        string $message,
        ?int $complaintId = null,
    ): UserNotification {
        return UserNotification::create([
            'user_id' => $userId,
            'complaint_id' => $complaintId,
            'type' => $type,
            'title' => $title,
            'message' => $message,
            'is_read' => false,
        ]);
    }

    public function complaintSubmitted(Complaint $complaint): void
    {
        $code = $complaint->code ?? "#{$complaint->id}";
        $this->notify(
            $complaint->user_id,
            self::TYPE_SUBMITTED,
            'Complaint submitted',
            "Your complaint {$code} was submitted successfully.",
            $complaint->id,
        );
    }

    public function complaintAssigned(Complaint $complaint, ?int $assigneeId = null): void
    {
        $code = $complaint->code ?? "#{$complaint->id}";

        $this->notify(
            $complaint->user_id,
            self::TYPE_ASSIGNED,
            'Complaint acknowledged',
            "Your complaint {$code} has been acknowledged and assigned for action.",
            $complaint->id,
        );

        $assigneeId ??= $complaint->assigned_to_id;
        if ($assigneeId && $assigneeId !== $complaint->user_id) {
            $this->notify(
                $assigneeId,
                self::TYPE_ASSIGNED,
                'Complaint assigned to you',
                "Complaint {$code} has been assigned to you.",
                $complaint->id,
            );
        }
    }

    public function complaintResolved(Complaint $complaint): void
    {
        $code = $complaint->code ?? "#{$complaint->id}";
        $this->notify(
            $complaint->user_id,
            self::TYPE_RESOLVED,
            'Complaint resolved',
            "Your complaint {$code} has been marked as resolved.",
            $complaint->id,
        );
    }

    public function complaintRejected(Complaint $complaint, ?string $reason = null): void
    {
        $code = $complaint->code ?? "#{$complaint->id}";
        $message = "Your complaint {$code} was rejected.";
        if ($reason) {
            $message .= " Reason: {$reason}";
        }

        $this->notify(
            $complaint->user_id,
            self::TYPE_REJECTED,
            'Complaint rejected',
            $message,
            $complaint->id,
        );
    }

    public function complaintTransferred(Complaint $complaint, int $toUserId): void
    {
        $code = $complaint->code ?? "#{$complaint->id}";

        $this->notify(
            $complaint->user_id,
            self::TYPE_ASSIGNED,
            'Complaint reassigned',
            "Your complaint {$code} has been reassigned to another officer.",
            $complaint->id,
        );

        if ($toUserId !== $complaint->user_id) {
            $this->notify(
                $toUserId,
                self::TYPE_ASSIGNED,
                'Complaint assigned to you',
                "Complaint {$code} has been transferred to you.",
                $complaint->id,
            );
        }
    }
}
