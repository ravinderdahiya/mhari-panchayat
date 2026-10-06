<?php

namespace App\Services;

use App\Models\AssetSurvey;
use App\Support\XlsxWriter;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

// Builds the "Asset Surveys" Excel export: one row per survey with its details,
// up to three embedded photo thumbnails and links to every photo.
class AssetSurveyExcelExport
{
    public const MAX_ROWS = 1500;

    private const PHOTO_COLUMNS = 3;
    private const THUMB_W = 110;
    private const THUMB_H = 84;

    // Photos are embedded as-is (no image library needed - the app's camera saves
    // small JPEGs, ~50-100 KB). A photo bigger than this, or one that would push
    // the workbook past the total budget, is exported as a link instead.
    private const MAX_EMBED_BYTES = 800 * 1024;
    private const TOTAL_EMBED_BUDGET = 150 * 1024 * 1024;

    private int $embeddedBytes = 0;

    private const REVIEW_LABEL = [
        'submitted' => 'Submitted (not yet forwarded)',
        'pending' => 'Pending review',
        'returned' => 'Returned for correction',
        'gram_sachiv_reviewed' => 'Reviewed by Gram Sachiv',
        'gram_sachiv_approved' => 'Forwarded by Gram Sachiv',
        'bdpo_reviewed' => 'Reviewed by BDPO',
        'bdpo_forwarded' => 'Forwarded by BDPO',
        'ddpo_reviewed' => 'Reviewed by DDPO',
        'ddpo_approved' => 'Approved by DDPO',
        'xen_reviewed' => 'Reviewed by XEN-PR',
        'xen_forwarded' => 'Forwarded by XEN-PR',
        'approved' => 'Final approved',
        'rejected' => 'Rejected',
    ];

    /**
     * @param  Collection<int, AssetSurvey>  $surveys  with surveyor, department, assetType, reviewedBy loaded
     * @return string absolute path of the generated .xlsx (caller deletes it)
     */
    public function build(Collection $surveys): string
    {
        $this->embeddedBytes = 0;
        $sheet = new XlsxWriter('Asset Surveys');

        $headers = [
            'S.No.', 'Asset code', 'Asset name', 'Asset type', 'Department',
            'Surveyor', 'Surveyor ID', 'Surveyor mobile',
            'District', 'Panchayat', 'Village', 'Latitude', 'Longitude',
            'Condition', 'Survey date', 'Review status', 'Reviewed by', 'Reviewed at',
            'Remarks / reason', 'Description', 'Photos',
        ];
        $photoStart = count($headers);
        for ($i = 1; $i <= self::PHOTO_COLUMNS; $i++) {
            $headers[] = "Photo {$i}";
        }
        $headers[] = 'All photo links';
        $sheet->addRow($headers, 28);

        $widths = [6, 14, 24, 18, 20, 20, 14, 14, 14, 18, 18, 11, 11, 11, 18, 24, 18, 18, 28, 30, 8];
        foreach ($widths as $col => $width) {
            $sheet->setColumnWidth($col, $width);
        }
        $photoWidth = round((self::THUMB_W + 12) / 7, 1);
        for ($i = 0; $i < self::PHOTO_COLUMNS; $i++) {
            $sheet->setColumnWidth($photoStart + $i, $photoWidth);
        }
        $sheet->setColumnWidth($photoStart + self::PHOTO_COLUMNS, 50);

        $rowHeight = (self::THUMB_H + 10) * 0.75;

        foreach ($surveys->values() as $index => $survey) {
            $paths = array_values($survey->photo_paths ?? []);
            $urls = array_map(fn (string $path) => $this->photoUrl($path), $paths);

            $cells = [
                $index + 1,
                $survey->asset_code,
                $survey->asset_name,
                $survey->assetType?->name,
                $survey->department?->name,
                $survey->surveyor?->name ?: $survey->surveyor?->username,
                $survey->surveyor?->employee_id ?: $survey->surveyor?->username,
                $survey->surveyor?->mobile,
                $survey->district,
                $survey->panchayat,
                $survey->village,
                $survey->latitude,
                $survey->longitude,
                $survey->condition,
                $survey->survey_date?->timezone('Asia/Kolkata')->format('d M Y, h:i a'),
                self::REVIEW_LABEL[$survey->review_status] ?? $survey->review_status,
                $survey->reviewedBy?->name ?: $survey->reviewedBy?->username,
                $survey->reviewed_at?->timezone('Asia/Kolkata')->format('d M Y, h:i a'),
                $survey->rejection_reason,
                $survey->description,
                count($paths),
            ];

            // Photo cells: the picture itself when it can be embedded, otherwise a clickable link.
            $pictures = [];
            for ($i = 0; $i < self::PHOTO_COLUMNS; $i++) {
                $pictures[$i] = isset($paths[$i]) ? $this->embeddablePhoto($paths[$i]) : null;
                $cells[] = isset($urls[$i]) && ! $pictures[$i] ? ['link' => $urls[$i], 'text' => 'Photo '.($i + 1)] : null;
            }
            $cells[] = implode("\n", $urls);

            $rowNumber = $sheet->addRow($cells, array_filter($pictures) ? $rowHeight : null);

            foreach ($pictures as $i => $picture) {
                if ($picture) {
                    $sheet->addPicture($rowNumber, $photoStart + $i, $picture['bytes'], $picture['ext'], $picture['width'], $picture['height']);
                }
            }
        }

        $dir = storage_path('app/tmp');
        File::ensureDirectoryExists($dir);
        $path = $dir.DIRECTORY_SEPARATOR.'asset_surveys_'.Str::random(16).'.xlsx';
        $sheet->save($path);

        return $path;
    }

    private function photoUrl(string $path): string
    {
        return rtrim((string) config('app.url'), '/').'/storage/'.ltrim($path, '/');
    }

    /**
     * The photo's own bytes plus the size to draw it at (fitted into the thumbnail box),
     * or null when it should be exported as a link instead.
     *
     * @return array{bytes: string, ext: string, width: int, height: int}|null
     */
    private function embeddablePhoto(string $relativePath): ?array
    {
        $disk = Storage::disk('public');
        if (! $disk->exists($relativePath)) {
            return null;
        }

        $size = $disk->size($relativePath);
        if ($size > self::MAX_EMBED_BYTES || $this->embeddedBytes + $size > self::TOTAL_EMBED_BUDGET) {
            return null;
        }

        $bytes = $disk->get($relativePath);
        $info = @getimagesizefromstring($bytes);
        if (! $info || $info[0] < 1 || $info[1] < 1) {
            return null;
        }

        // Only formats every Excel version renders; anything else becomes a link.
        $ext = match ($info[2]) {
            IMAGETYPE_JPEG => 'jpeg',
            IMAGETYPE_PNG => 'png',
            default => null,
        };
        if ($ext === null) {
            return null;
        }

        $scale = min(self::THUMB_W / $info[0], self::THUMB_H / $info[1], 1);
        $this->embeddedBytes += $size;

        return [
            'bytes' => $bytes,
            'ext' => $ext,
            'width' => max(1, (int) round($info[0] * $scale)),
            'height' => max(1, (int) round($info[1] * $scale)),
        ];
    }
}
