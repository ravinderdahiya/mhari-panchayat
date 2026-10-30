<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\DistrictSlaPerformance;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Cache;

/** Public, aggregate-only "top districts by SLA compliance" for the home page. */
class PublicDistrictPerformanceController extends Controller
{
    public function __invoke(DistrictSlaPerformance $performance): JsonResponse
    {
        $districts = Cache::remember('public.district_performance', 300, fn () => $performance->top());

        return response()->json([
            'success' => true,
            'data' => ['districts' => $districts, 'min_sample' => DistrictSlaPerformance::MIN_SAMPLE],
        ]);
    }
}
