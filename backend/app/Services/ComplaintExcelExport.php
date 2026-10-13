<?php

namespace App\Services;

use App\Models\Complaint;
use App\Support\XlsxWriter;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Str;

// Excel export of complaints for the admin Reports screen: one row per complaint
// with its category, priority, location, assignee, timings and photo links.
class ComplaintExcelExport
{
    public const MAX_ROWS = 5000;

    /**
     * @param  Collection<int, Complaint>  $complaints  with user, assignedTo, category, priority, department, assetType loaded
     * @return string absolute path of the generated .xlsx (caller deletes it)
     */
    public function build(Collection $complaints): string
    {
        $sheet = new XlsxWriter('Complaints');
        $sheet->addRow([
            'S.No.', 'Complaint code', 'Status', 'Category', 'Priority', 'Department', 'Asset type',
            'Description', 'Village', 'Panchayat', 'District', 'Tehsil', 'Block',
            'Citizen mobile', 'Assigned to', 'Raised on', 'Resolved on', 'SLA due', 'Escalation level',
            'Citizen rating', 'Citizen feedback', 'Latitude', 'Longitude', 'Photos',
        ], 28);

        foreach ([6, 18, 14, 22, 11, 24, 20, 40, 18, 18, 16, 16, 16, 14, 20, 18, 18, 18, 11, 9, 28, 11, 11, 50] as $col => $width) {
            $sheet->setColumnWidth($col, $width);
        }

        foreach ($complaints->values() as $index => $complaint) {
            $sheet->addRow([
                $index + 1,
                $complaint->code,
                str_replace('_', ' ', (string) $complaint->status),
                $complaint->category?->name,
                $complaint->priority?->name,
                $complaint->department?->name,
                $complaint->assetType?->name,
                $complaint->description,
                $complaint->village,
                $complaint->panchayat,
                $complaint->location_district,
                $complaint->location_tehsil,
                $complaint->location_block,
                $complaint->user?->mobile,
                $complaint->assignedTo?->name ?: $complaint->assignedTo?->username,
                $this->time($complaint->created_at),
                $this->time($complaint->resolved_at),
                $this->time($complaint->sla_due_at),
                (int) ($complaint->escalation_level ?? 0),
                $complaint->citizen_rating,
                $complaint->citizen_feedback,
                $complaint->lat,
                $complaint->long,
                implode("\n", $this->photoUrls($complaint)),
            ]);
        }

        $dir = storage_path('app/tmp');
        File::ensureDirectoryExists($dir);
        $path = $dir.DIRECTORY_SEPARATOR.'complaints_'.Str::random(16).'.xlsx';
        $sheet->save($path);

        return $path;
    }

    private function time(mixed $value): ?string
    {
        return $value?->copy()->timezone('Asia/Kolkata')->format('d M Y, h:i a');
    }

    /** @return array<int, string> */
    private function photoUrls(Complaint $complaint): array
    {
        $urls = [];
        foreach ([$complaint->before_photo_url, $complaint->during_photo_url, $complaint->after_photo_url] as $url) {
            $urls[] = $url;
        }
        $issue = $complaint->issue_photo_urls;
        foreach (is_array($issue) ? $issue : (json_decode((string) $issue, true) ?: []) as $url) {
            $urls[] = $url;
        }

        return array_values(array_unique(array_filter(array_map(
            fn ($url) => $url && ! preg_match('#^https?://#i', (string) $url)
                ? rtrim((string) config('app.url'), '/').'/'.ltrim((string) $url, '/')
                : $url,
            $urls,
        ))));
    }
}
