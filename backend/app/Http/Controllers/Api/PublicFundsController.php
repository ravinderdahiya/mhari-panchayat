<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Panchayat;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Panchayat funds for the public home page.
 *
 * DEMO DATA ONLY: no fund/expenditure source is connected yet (e-Gram Swaraj /
 * PFMS access is pending), so the figures are generated from the panchayat id and
 * financial year. The response says `demo: true` so the page can label it. When a
 * real source exists, replace demoFigures() and keep the response shape.
 */
class PublicFundsController extends Controller
{
    // name_hi, purpose_hi, base allocation (Rs lakh), share spent
    private const SOURCES = [
        ['15वां वित्त आयोग (बंधित)', 'स्वच्छता, पेयजल', 18.4, 0.66],
        ['15वां वित्त आयोग (अबंधित)', 'स्थानीय ज़रूरतें', 12.25, 0.77],
        ['राज्य वित्त आयोग', 'हरियाणा अनुदान', 9.6, 0.43],
        ['मनरेगा', 'मजदूरी व सामग्री', 15.3, 0.97],
        ['स्वच्छ भारत मिशन (ग्रामीण)', 'ठोस-तरल कचरा', 4.5, 0.27],
        ['पंचायत की अपनी आय', 'शामलात पट्टा, नीलामी', 23.8, 0.36],
    ];

    private const WORKS = [
        ['वार्ड %d में गली पक्की करना (220 मी.)', 465000, 0, 'completed'],
        ['जोहड़ की सफ़ाई व घाट मरम्मत', 380000, 3, 'completed'],
        ['चौपाल की छत की मरम्मत', 215000, 3, 'in_progress'],
        ['मुख्य नाली पर 12 जाली कवर', 96000, 0, 'approved'],
    ];

    public function show(Request $request): JsonResponse
    {
        $data = $request->validate([
            'panchayat_id' => ['required', 'integer'],
            'fy' => ['nullable', 'regex:/^\d{4}-\d{2}$/'],
        ]);
        $panchayat = Panchayat::with('block:id,name')->find($data['panchayat_id']);
        if (! $panchayat) {
            return response()->json(['success' => false, 'message' => 'Panchayat not found.'], 404);
        }
        $fy = $data['fy'] ?? $this->currentFy();

        // Stable per panchayat + year, so a refresh does not change the numbers.
        $seed = crc32($panchayat->id.'|'.$fy);
        $scale = 0.6 + ($seed % 90) / 100; // 0.60 .. 1.49
        $jitter = fn (int $i) => 0.85 + ((($seed >> ($i * 3)) % 30) / 100); // 0.85 .. 1.14

        $sources = [];
        foreach (self::SOURCES as $i => [$name, $purpose, $base, $share]) {
            $allocated = round($base * $scale, 2);
            $spent = round($allocated * min(0.99, $share * $jitter($i)), 2);
            $sources[] = ['name' => $name, 'purpose' => $purpose, 'allocated_lakh' => $allocated, 'spent_lakh' => $spent];
        }
        $received = round(array_sum(array_column($sources, 'allocated_lakh')), 2);
        $spentTotal = round(array_sum(array_column($sources, 'spent_lakh')), 2);

        $recent = [];
        foreach (self::WORKS as $i => [$title, $amount, $src, $status]) {
            $recent[] = [
                'title' => sprintf($title, 1 + ($seed + $i) % 9),
                'amount' => (int) round($amount * $scale / 1000) * 1000,
                'source' => self::SOURCES[$src][0],
                'status' => $status,
                'date' => now()->subDays(12 + $i * 17 + ($seed % 5))->toDateString(),
            ];
        }

        return response()->json(['success' => true, 'data' => [
            'demo' => true,
            'panchayat' => $panchayat->name,
            'block' => $panchayat->block?->name,
            'fy' => $fy,
            'received_lakh' => $received,
            'spent_lakh' => $spentTotal,
            'balance_lakh' => round($received - $spentTotal, 2),
            'sources' => $sources,
            'recent' => $recent,
            'as_of' => now()->toDateString(),
        ]]);
    }

    private function currentFy(): string
    {
        $y = (int) now()->format('Y');
        $start = (int) now()->format('n') >= 4 ? $y : $y - 1;

        return $start.'-'.substr((string) ($start + 1), 2);
    }
}
