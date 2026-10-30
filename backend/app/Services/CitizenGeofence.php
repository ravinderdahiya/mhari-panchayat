<?php

namespace App\Services;

use App\Http\Controllers\Api\GisController;
use App\Models\CitizenProfile;
use App\Models\User;

/**
 * Citizens may file a complaint from any village, but only from inside a village
 * (gram panchayat) boundary: a point in open land, a city or outside Haryana is
 * refused. Staff accounts are never restricted.
 */
class CitizenGeofence
{
    public const MESSAGE = 'आप किसी भी गाँव / पंचायत की सीमा के अंदर नहीं हैं। शिकायत केवल गाँव की सीमा के अंदर से ही दर्ज हो सकती है। '
        .'You are outside any village (panchayat) boundary. A complaint can only be filed from inside a village boundary.';

    public function __construct(private GisController $gis) {}

    /**
     * @return array{allowed: bool, panchayat: ?string, message: ?string}
     */
    public function check(User $user, float $lat, float $lng): array
    {
        $allowed = ['allowed' => true, 'panchayat' => null, 'message' => null];
        if (! CitizenProfile::where('user_id', $user->id)->exists()) {
            return $allowed;
        }

        // A guard must never take complaint filing down with it.
        try {
            $match = $this->gis->pointStatus($lat, $lng);
        } catch (\Throwable $e) {
            report($e);

            return $allowed;
        }

        return match ($match['status']) {
            'matched' => ['allowed' => true, 'panchayat' => $match['name'] ?? null, 'message' => null],
            // The boundary service could not be reached, so the point cannot be judged: do not block.
            'unavailable' => $allowed,
            default => ['allowed' => false, 'panchayat' => null, 'message' => self::MESSAGE],
        };
    }
}
