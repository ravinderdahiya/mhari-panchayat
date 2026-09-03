<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Cache;

#[Fillable(['name', 'full_name', 'main_responsibility', 'is_active', 'is_super_admin'])]
class Role extends Model
{
    private const SUPER_ADMIN_CACHE_KEY = 'roles.super_admin_names';

    /** @var array<string, array{full_name: string, main_responsibility: string}> */
    public const CATALOG = [
        'super_admin' => [
            'full_name' => 'Super Admin / सुपर एडमिन',
            'main_responsibility' => 'Highest-level administrative role: complete system configuration, users, roles, permissions, masters, workflow, reports, audit logs and security settings',
        ],
        'admin' => [
            'full_name' => 'System Administrator / प्रशासनिक अधिकारी',
            'main_responsibility' => 'Complete system administration, user/role management, master data and reports',
        ],
        'citizen' => [
            'full_name' => 'Citizen / नागरिक',
            'main_responsibility' => 'Complaint or survey request submission and status tracking',
        ],
        'surveyor' => [
            'full_name' => 'Field Surveyor / क्षेत्र सर्वेक्षक',
            'main_responsibility' => 'Field survey, GPS/location capture, photos and data collection',
        ],
        'cplo' => [
            'full_name' => 'CPLO(CRID Panchayat Local Operator) / पंचायत स्तर अधिकारी',
            'main_responsibility' => 'Panchayat-level data collection, verification support, field activities, GPS/photo-based records and submission',
        ],
        'gram_sachiv' => [
            'full_name' => 'Gram Sachiv / ग्राम सचिव',
            'main_responsibility' => 'Village-level data verification and approval',
        ],
        'bdpo' => [
            'full_name' => 'Block Development & Panchayat Officer (BDPO)',
            'main_responsibility' => 'Block-level verification, monitoring and forwarding',
        ],
        'ddpo' => [
            'full_name' => 'District Development & Panchayat Officer (DDPO)',
            'main_responsibility' => 'District-level monitoring, verification and approval',
        ],
        'xen_pr' => [
            'full_name' => 'Executive Engineer – Panchayati Raj (XEN-PR)',
            'main_responsibility' => 'Technical/engineering verification of development works',
        ],
        'ceo_zp' => [
            'full_name' => 'Chief Executive Officer – Zila Parishad (CEO-ZP)',
            'main_responsibility' => 'Zila Parishad-level supervision and final approval',
        ],
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'is_super_admin' => 'boolean',
        ];
    }

    protected static function booted(): void
    {
        static::saved(fn () => static::forgetCached());
        static::deleted(fn () => static::forgetCached());
    }

    public static function forgetCached(): void
    {
        Cache::forget(self::SUPER_ADMIN_CACHE_KEY);
    }

    /** @return list<string> */
    public static function superAdminNames(): array
    {
        return Cache::remember(self::SUPER_ADMIN_CACHE_KEY, 60, function () {
            return static::query()->where('is_super_admin', true)->orderBy('name')->pluck('name')->all();
        });
    }

    public static function isSuperAdmin(?string $role): bool
    {
        return $role !== null && $role !== '' && in_array($role, static::superAdminNames(), true);
    }

    /** @return list<string> */
    public static function names(bool $activeOnly = false): array
    {
        $query = static::query()
            ->orderByDesc('is_super_admin')
            ->orderBy('name');
        if ($activeOnly) {
            $query->where('is_active', true);
        }

        return $query->pluck('name')->all();
    }
}
