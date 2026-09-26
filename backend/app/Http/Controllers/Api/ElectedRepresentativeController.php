<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ElectedRepresentative;
use Illuminate\Http\Request;

// Read-only directory of Panchayati Raj representatives who have no login
// role in this app (Zila Parishad members, Panchayat Samiti members,
// Panches) - imported from "ER-Data.xlsx" via `er:import`. Sarpanches are
// the one tier from that workbook with a portal role and live in `users`
// instead (see UserController), so they're not part of this directory.
class ElectedRepresentativeController extends Controller
{
    public function index(Request $request)
    {
        $data = $request->validate([
            'tier' => ['required', 'string', 'in:zp,ps,panch'],
            'district_id' => ['sometimes', 'nullable', 'integer'],
            'block_id' => ['sometimes', 'nullable', 'integer'],
            'panchayat_id' => ['sometimes', 'nullable', 'integer'],
            'q' => ['sometimes', 'nullable', 'string', 'max:100'],
            'page' => ['sometimes', 'integer', 'min:1'],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:100'],
        ]);

        $query = ElectedRepresentative::with(['district:id,name', 'block:id,name', 'panchayat:id,name'])
            ->where('tier', $data['tier']);

        if (! empty($data['district_id'])) {
            $query->where('district_id', $data['district_id']);
        }
        if (! empty($data['block_id'])) {
            $query->where('block_id', $data['block_id']);
        }
        if (! empty($data['panchayat_id'])) {
            $query->where('panchayat_id', $data['panchayat_id']);
        }

        $search = trim((string) ($data['q'] ?? ''));
        if ($search !== '') {
            $needle = '%'.mb_strtolower($search).'%';
            $query->where(function ($q) use ($needle) {
                $q->whereRaw('LOWER(name) LIKE ?', [$needle])
                    ->orWhereRaw('LOWER(father_name) LIKE ?', [$needle])
                    ->orWhere('mobile', 'like', $needle);
            });
        }

        $query->orderBy('source_sr_no');

        $paginator = $query->paginate((int) ($data['per_page'] ?? 25));

        return response()->json([
            'success' => true,
            'representatives' => $paginator->getCollection()->values(),
            'pagination' => [
                'currentPage' => $paginator->currentPage(),
                'lastPage' => $paginator->lastPage(),
                'perPage' => $paginator->perPage(),
                'total' => $paginator->total(),
                'from' => $paginator->firstItem(),
                'to' => $paginator->lastItem(),
            ],
            'counts' => ElectedRepresentative::query()
                ->selectRaw('tier, count(*) as count')
                ->groupBy('tier')
                ->pluck('count', 'tier'),
        ]);
    }
}
