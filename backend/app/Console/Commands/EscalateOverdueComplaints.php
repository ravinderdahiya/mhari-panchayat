<?php

namespace App\Console\Commands;

use App\Models\Complaint;
use App\Models\ComplaintPriority;
use App\Models\ComplaintTimelineEvent;
use App\Models\User;
use App\Services\NotificationService;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;

#[Signature('complaints:escalate-overdue')]
#[Description('Bump priority and notify department heads for complaints stuck past their SLA')]
class EscalateOverdueComplaints extends Command
{
    /**
     * Execute the console command.
     */
    public function handle(NotificationService $notifications): void
    {
        $complaints = Complaint::query()
            ->whereNotIn('status', ['Resolved', 'Closed', 'Rejected'])
            ->whereNotNull('sla_due_at')
            ->where('sla_due_at', '<', now())
            ->get();

        foreach ($complaints as $complaint) {
            $nextPriority = ComplaintPriority::where('level', '>', $complaint->priority?->level ?? 0)
                ->orderBy('level')
                ->first();

            if ($nextPriority) {
                $complaint->priority_id = $nextPriority->id;
                $complaint->setRelation('priority', $nextPriority);
            }

            $complaint->escalation_level++;
            $complaint->escalated_at = now();
            $complaint->refreshSlaDueAt();
            $complaint->save();

            ComplaintTimelineEvent::create([
                'complaint_id' => $complaint->id,
                'status' => $complaint->status,
                'title' => 'SLA Breached — Escalated',
                'description' => $nextPriority
                    ? "No action within SLA window; priority escalated to {$nextPriority->name}."
                    : 'No action within SLA window; already at the highest priority.',
                'performed_by_id' => null,
                'created_at' => now(),
            ]);

            $recipientIds = User::where('department_id', $complaint->department_id)
                ->where('role', 'department_head')
                ->pluck('id')
                ->all();
            if ($complaint->assigned_to_id) {
                $recipientIds[] = $complaint->assigned_to_id;
            }

            $notifications->complaintEscalated($complaint, $recipientIds);
        }

        $this->info("Escalated {$complaints->count()} overdue complaint(s).");
    }
}
