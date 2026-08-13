<?php

namespace App\Console\Commands;

use App\Models\Complaint;
use App\Models\ComplaintTimelineEvent;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;

#[Signature('complaints:auto-close-resolved')]
#[Description('Close Resolved complaints the citizen never rated within the response window')]
class AutoCloseResolvedComplaints extends Command
{
    private const AUTO_CLOSE_AFTER_DAYS = 7;

    /**
     * Execute the console command.
     */
    public function handle(): void
    {
        $complaints = Complaint::query()
            ->where('status', 'Resolved')
            ->whereNotNull('resolved_at')
            ->where('resolved_at', '<=', now()->subDays(self::AUTO_CLOSE_AFTER_DAYS))
            ->get();

        foreach ($complaints as $complaint) {
            $complaint->update(['status' => 'Closed']);

            ComplaintTimelineEvent::create([
                'complaint_id' => $complaint->id,
                'status' => 'Closed',
                'title' => 'Auto-closed',
                'description' => 'Automatically closed after '.self::AUTO_CLOSE_AFTER_DAYS.' days with no citizen response.',
                'performed_by_id' => null,
                'created_at' => now(),
            ]);
        }

        $this->info("Auto-closed {$complaints->count()} resolved complaint(s).");
    }
}
