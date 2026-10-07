<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Database\Eloquent\Builder;

/**
 * Which asset surveys a reviewer (Gram Sachiv / BDPO / DDPO / XEN-PR / CEO-ZP) may
 * see: only those from their own jurisdiction. A reviewer with no jurisdiction
 * assigned yet sees nothing (not everything). Other roles are left untouched.
 *
 * Shared by the survey list and the asset map so both always agree.
 */
class SurveyJurisdiction
{
    public static function apply(Builder $query, User $user): void
    {
        if ($user->role === 'gram_sachiv') {
            $query->whereIn('panchayat_id', self::panchayatIds($user) ?: [0]);
        } elseif ($user->role === 'bdpo') {
            $blockIds = $user->blocks()->pluck('blocks.id')->all();
            if ($user->block_id) {
                $blockIds[] = $user->block_id;
            }
            $query->whereIn('block_id', $blockIds ?: [0]);
        } elseif ($user->role === 'ddpo') {
            $query->where('district_id', $user->district_id ?: 0);
        } elseif ($user->role === 'xen_pr') {
            // Only ever actionable on 'ddpo_approved' surveys whose asset
            // type actually needs technical review - other statuses (their
            // own forwarded/history) still show regardless.
            $query->where('district_id', $user->district_id ?: 0)
                ->where(function ($jurisdiction) {
                    $jurisdiction->where('review_status', '!=', 'ddpo_approved')
                        ->orWhereHas('assetType', fn ($assetType) => $assetType->where('requires_technical_review', true));
                });
        } elseif ($user->role === 'ceo_zp') {
            $query->where('district_id', $user->district_id ?: 0);
        }
    }

    /** Panchayats assigned to the user (the many-to-many list plus their primary one). @return array<int, int> */
    public static function panchayatIds(User $user): array
    {
        $ids = $user->panchayats()->pluck('panchayats.id')->all();
        if ($user->panchayat_id) {
            $ids[] = (int) $user->panchayat_id;
        }

        return array_values(array_unique(array_filter($ids)));
    }
}
