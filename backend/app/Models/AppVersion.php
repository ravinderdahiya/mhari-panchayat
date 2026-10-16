<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;

#[Fillable(['platform', 'latest_version_code', 'min_version_code', 'store_url', 'message'])]
class AppVersion extends Model
{
    protected function casts(): array
    {
        return [
            'latest_version_code' => 'integer',
            'min_version_code' => 'integer',
        ];
    }

    public static function forPlatform(string $platform): ?self
    {
        return static::where('platform', $platform)->first();
    }

    /** 'ok' | 'optional_update' | 'force_update' for an installed build number. */
    public function statusFor(int $versionCode): string
    {
        if ($versionCode < $this->min_version_code) {
            return 'force_update';
        }

        return $versionCode < $this->latest_version_code ? 'optional_update' : 'ok';
    }
}
