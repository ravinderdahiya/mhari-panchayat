<?php

namespace App\Services;

use App\Models\AssetSurvey;
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

    // Asset-survey review workflow.
    public const TYPE_SURVEY_REVIEW = 'SURVEY_REVIEW_NEEDED';

    public const TYPE_SURVEY_RETURNED = 'SURVEY_RETURNED';

    public const TYPE_SURVEY_REJECTED = 'SURVEY_REJECTED';

    public const TYPE_SURVEY_APPROVED = 'SURVEY_APPROVED';

    public function notify(
        int $userId,
        string $type,
        string $title,
        string $message,
        ?int $complaintId = null,
        ?int $assetSurveyId = null,
    ): UserNotification {
        $notification = UserNotification::create([
            'user_id' => $userId,
            'complaint_id' => $complaintId,
            'asset_survey_id' => $assetSurveyId,
            'type' => $type,
            'title' => $title,
            'message' => $message,
            'is_read' => false,
        ]);

        // Push is best-effort: the inbox row above is the source of truth.
        try {
            app(FcmService::class)->sendToUser($userId, $title, $message, [
                'notificationId' => $notification->id,
                'type' => $type,
                'complaintId' => $complaintId ?? '',
                'assetSurveyId' => $assetSurveyId ?? '',
            ]);
        } catch (\Throwable $e) {
            report($e);
        }

        return $notification;
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

    // ------------------------------------------------------------ asset surveys

    // Who owns a survey once an action has moved it to its next stage, by role.
    private const SURVEY_NEXT_REVIEWER = [
        'forwardSubmission' => 'gram_sachiv',
        'gramSachivForward' => 'bdpo',
        'forward' => 'ddpo',
        'xenForward' => 'ceo_zp',
    ];

    /**
     * Called after a review action was applied (see AssetSurveyController::applyTransition):
     *  - the next stage's reviewers (in the survey's own panchayat / block / district) are
     *    told a survey is waiting for them;
     *  - the surveyor is told when it is returned, rejected or finally approved.
     */
    public function surveyTransitioned(AssetSurvey $survey, string $action, User $actor, ?string $reason = null): void
    {
        $survey->loadMissing(['assetType:id,name,requires_technical_review', 'surveyor:id,name,username']);

        $nextRole = self::SURVEY_NEXT_REVIEWER[$action] ?? null;
        if ($action === 'approve') { // DDPO approved: technical types go to XEN-PR, the rest straight to CEO-ZP
            $nextRole = ($survey->assetType?->requires_technical_review ?? true) ? 'xen_pr' : 'ceo_zp';
        }
        if ($nextRole) {
            $by = $survey->surveyor?->name ?: $survey->surveyor?->username ?: 'a surveyor';
            foreach ($this->surveyReviewers($survey, $nextRole) as $reviewerId) {
                if ($reviewerId === $actor->id) {
                    continue;
                }
                $this->notify(
                    $reviewerId,
                    self::TYPE_SURVEY_REVIEW,
                    'Survey waiting for your review',
                    $this->surveyLabel($survey)." (surveyed by {$by}) is waiting for your review.",
                    null,
                    $survey->id,
                );
            }
        }

        $surveyorId = $survey->surveyor_id;
        if (! $surveyorId || $surveyorId === $actor->id) {
            return;
        }
        $label = $this->surveyLabel($survey);
        $reasonText = $reason ? " Reason: {$reason}" : '';

        match ($action) {
            'return' => $this->notify($surveyorId, self::TYPE_SURVEY_RETURNED, 'Survey returned for correction', "{$label} was returned for correction.{$reasonText}", null, $survey->id),
            'reject' => $this->notify($surveyorId, self::TYPE_SURVEY_REJECTED, 'Survey rejected', "{$label} was rejected.{$reasonText}", null, $survey->id),
            'finalApprove' => $this->notify($surveyorId, self::TYPE_SURVEY_APPROVED, 'Survey approved', "{$label} received final approval.", null, $survey->id),
            default => null,
        };
    }

    private function surveyLabel(AssetSurvey $survey): string
    {
        $name = trim((string) $survey->asset_name) !== '' ? $survey->asset_name : ($survey->assetType?->name ?? 'Survey');
        $place = collect([$survey->village, $survey->panchayat])->filter()->unique()->implode(', ');

        return $place !== '' ? "{$name} ({$place})" : $name;
    }

    /**
     * Active users holding $role whose jurisdiction covers the survey: a Gram Sachiv's
     * panchayat(s), a BDPO's block(s), a DDPO / XEN-PR / CEO-ZP's district. A survey with
     * no location for that level has no reviewers yet (nobody is notified).
     *
     * @return array<int, int>
     */
    private function surveyReviewers(AssetSurvey $survey, string $role): array
    {
        $query = User::query()->where('role', $role)->where('is_active', true);

        switch ($role) {
            case 'gram_sachiv':
                if (! $survey->panchayat_id) {
                    return [];
                }
                $query->where(fn ($q) => $q->where('panchayat_id', $survey->panchayat_id)
                    ->orWhereHas('panchayats', fn ($p) => $p->where('panchayats.id', $survey->panchayat_id)));
                break;
            case 'bdpo':
                if (! $survey->block_id) {
                    return [];
                }
                $query->where(fn ($q) => $q->where('block_id', $survey->block_id)
                    ->orWhereHas('blocks', fn ($b) => $b->where('blocks.id', $survey->block_id)));
                break;
            default:
                if (! $survey->district_id) {
                    return [];
                }
                $query->where('district_id', $survey->district_id);
        }

        return $query->pluck('id')->map(fn ($id) => (int) $id)->all();
    }
}
