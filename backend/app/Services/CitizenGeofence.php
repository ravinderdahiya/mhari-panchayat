<?php

namespace App\Services;

use App\Http\Controllers\Api\LocationController;
use App\Models\CitizenProfile;
use App\Models\Complaint;
use App\Models\Panchayat;
use App\Models\User;

/**
 * Keeps a citizen's complaints inside their own panchayat. The home panchayat is
 * fixed by the citizen's first complaint (registering or signing in from anywhere
 * does not fix it), so moving around later does not widen it. Staff accounts are never restricted.
 */
class CitizenGeofence
{
    public const MESSAGE = 'आप अपनी पंचायत के क्षेत्र से बाहर हैं। शिकायत केवल अपनी पंचायत की सीमा के अंदर ही दर्ज हो सकती है। '
        .'You are outside your panchayat area. A complaint can only be filed within your own panchayat boundary.';

    public function __construct(private LocationController $locations) {}

    /**
     * @return array{allowed: bool, home: ?string, current: ?string, message: ?string}
     */
    public function check(User $user, float $lat, float $lng): array
    {
        // A guard must never take complaint filing down with it (e.g. a migration not yet run).
        try {
            return $this->evaluate($user, $lat, $lng);
        } catch (Throwable $e) {
            report($e);

            return ['allowed' => true, 'home' => null, 'current' => null, 'message' => null];
        }
    }

    /** @return array{allowed: bool, home: ?string, current: ?string, message: ?string} */
    private function evaluate(User $user, float $lat, float $lng): array
    {
        $profile = CitizenProfile::where('user_id', $user->id)->first();
        $homeId = $profile ? $this->homePanchayatId($profile) : null;
        if (! $profile || ! $homeId) {
            return ['allowed' => true, 'home' => null, 'current' => null, 'message' => null];
        }

        $place = $this->locations->lookup($lat, $lng);
        // Both location services unreachable: the point cannot be judged, so do not block the citizen.
        if ($place === null) {
            return ['allowed' => true, 'home' => Panchayat::whereKey($homeId)->value('name'), 'current' => null, 'message' => null];
        }
        $currentId = $place['panchayatId'] ?? null;
        $allowed = $currentId !== null && (int) $currentId === $homeId;

        return [
            'allowed' => $allowed,
            'home' => Panchayat::whereKey($homeId)->value('name'),
            'current' => $place['panchayat'] ?? null,
            'message' => $allowed ? null : self::MESSAGE,
        ];
    }

    /** Home panchayat, remembered on first use from the saved location or the latest complaint. */
    public function homePanchayatId(CitizenProfile $profile): ?int
    {
        if ($profile->home_panchayat_id) {
            return (int) $profile->home_panchayat_id;
        }
        $fromComplaint = Complaint::where('user_id', $profile->user_id)->whereNotNull('panchayat_id')->orderBy('id')->value('panchayat_id');
        if ($fromComplaint) {
            $profile->update(['home_panchayat_id' => $fromComplaint]);
        }

        return $fromComplaint ? (int) $fromComplaint : null;
    }

    public function rememberHome(User $user, ?int $panchayatId): void
    {
        if (! $panchayatId) {
            return;
        }
        try {
            CitizenProfile::where('user_id', $user->id)->whereNull('home_panchayat_id')->update(['home_panchayat_id' => $panchayatId]);
        } catch (Throwable $e) {
            report($e);
        }
    }
}
