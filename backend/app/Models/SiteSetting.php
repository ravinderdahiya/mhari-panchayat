<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Cache;

#[Fillable(['key', 'value'])]
class SiteSetting extends Model
{
    public $incrementing = false;

    protected $primaryKey = 'key';

    protected $keyType = 'string';

    /** Editable keys and what an unset one falls back to. */
    public const DEFAULTS = [
        'helpline' => '',
        'support_email' => '',
        'office_hours' => '',
        'announcement_active' => '0',
        'announcement_tag' => '',
        'announcement_tag_hi' => '',
        'announcement_title' => '',
        'announcement_title_hi' => '',
        'announcement_body' => '',
        'announcement_body_hi' => '',
        'announcement_cta_label' => '',
        'announcement_cta_label_hi' => '',
        'announcement_cta_url' => '',
    ];

    /** @return array<string,string> */
    public static function values(): array
    {
        return Cache::remember('site_settings.all', 300, fn () => array_merge(
            self::DEFAULTS,
            static::query()->pluck('value', 'key')->map(fn ($v) => (string) $v)->all(),
        ));
    }

    public static function forget(): void
    {
        Cache::forget('site_settings.all');
        Cache::forget('public.home');
    }
}
