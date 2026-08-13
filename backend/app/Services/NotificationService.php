<?php

namespace App\Services;

use App\Models\Complaint;
use App\Models\User;
use App\Models\UserNotification;

class NotificationService
{
    public const TYPE_SUBMITTED = 'COMPLAINT_SUBMITTED';

    public const TYPE_ASSIGNED = 'COMPLAINT_ASSIGNED';

    public const TYPE_RESOLVED = 'COMPLAINT_RESOLVED';

    public const TYPE_REJECTED = 'COMPLAINT_REJECTED';

    public const TYPE_ESCALATED = 'COMPLAINT_ESCALATED';

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

    // Staff-facing only - an internal priority bump isn't citizen-relevant.
    public function complaintEscalated(Complaint $complaint, array $recipientUserIds): void
    {
        $code = $complaint->code ?? "#{$complaint->id}";
        $priorityName = $complaint->priority?->name ?? 'higher priority';

        foreach (array_unique(array_filter($recipientUserIds)) as $userId) {
            $this->notify(
                $userId,
                self::TYPE_ESCALATED,
                'Complaint SLA breached',
                "Complaint {$code} missed its SLA and was escalated to {$priorityName} priority.",
                $complaint->id,
            );
        }
    }

    // Notifies whoever should act next now that the complaint is back open -
    // the previous assignee, or a department_head fallback if it was never assigned.
    public function complaintReopened(Complaint $complaint): void
    {
        $code = $complaint->code ?? "#{$complaint->id}";
        $recipientIds = $complaint->assigned_to_id
            ? [$complaint->assigned_to_id]
            : User::where('department_id', $complaint->department_id)
                ->where('role', 'department_head')
                ->pluck('id')
                ->all();

        foreach (array_unique(array_filter($recipientIds)) as $userId) {
            $this->notify(
                $userId,
                self::TYPE_ASSIGNED,
                'Complaint reopened',
                "Complaint {$code} was reopened by the citizen and needs your attention again.",
                $complaint->id,
            );
        }
    }
}
