<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Renames role strings to match the finalized role list:
 *   super_admin -> admin, block_admin -> bdpo, district_admin -> ddpo.
 *
 * 'engineer' is split, since it previously double-booked two different real
 * posts (see ImportHaryanaOfficials): most 'engineer' rows are generic
 * surveyors -> 'surveyor', but the ones imported from
 * database/data/haryana_officials.json's 'xen' list are Executive Engineers
 * -> 'xen_pr'. XEN rows are re-identified here with the exact same
 * username-derivation ImportHaryanaOfficials::usernameFor() uses (last-10-
 * digits-of-mobile, else email-local-part slug), so the two commands never
 * drift apart.
 */
return new class extends Migration
{
    private function normalizedMobile(?string $mobile): ?string
    {
        if (! $mobile) {
            return null;
        }
        $first = trim(explode(',', $mobile)[0]);
        $digits = preg_replace('/\D/', '', $first);

        return $digits !== '' ? $digits : null;
    }

    private function usernameFor(array $row): ?string
    {
        $mobile = $this->normalizedMobile($row['mobile'] ?? null);
        if ($mobile && strlen($mobile) >= 10) {
            return substr($mobile, -10);
        }
        $email = $row['email'] ?? null;

        return $email ? Str::slug(Str::before($email, '@'), '_') : null;
    }

    /** @return list<string> */
    private function xenUsernames(): array
    {
        $path = database_path('data/haryana_officials.json');
        if (! is_file($path)) {
            return [];
        }
        $data = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);

        return collect($data['xen'] ?? [])
            ->map(fn (array $row) => $this->usernameFor($row))
            ->filter()
            ->values()
            ->all();
    }

    public function up(): void
    {
        $xenUsernames = $this->xenUsernames();

        DB::transaction(function () use ($xenUsernames) {
            if ($xenUsernames !== []) {
                DB::table('users')->where('role', 'engineer')->whereIn('username', $xenUsernames)
                    ->update(['role' => 'xen_pr']);
            }
            DB::table('users')->where('role', 'engineer')->update(['role' => 'surveyor']);
            DB::table('users')->where('role', 'super_admin')->update(['role' => 'admin']);
            DB::table('users')->where('role', 'block_admin')->update(['role' => 'bdpo']);
            DB::table('users')->where('role', 'district_admin')->update(['role' => 'ddpo']);

            DB::table('role_permissions')->where('role', 'engineer')->update(['role' => 'surveyor']);
            DB::table('role_permissions')->where('role', 'super_admin')->update(['role' => 'admin']);
            DB::table('role_permissions')->where('role', 'block_admin')->update(['role' => 'bdpo']);
            DB::table('role_permissions')->where('role', 'district_admin')->update(['role' => 'ddpo']);

            DB::table('complaint_categories')->where('resolver_role', 'engineer')->update(['resolver_role' => 'xen_pr']);
            DB::table('complaint_categories')->where('resolver_role', 'block_admin')->update(['resolver_role' => 'bdpo']);
            DB::table('complaint_categories')->where('resolver_role', 'district_admin')->update(['resolver_role' => 'ddpo']);
            DB::table('complaint_categories')->where('resolver_role', 'super_admin')->update(['resolver_role' => 'admin']);
        });
    }

    public function down(): void
    {
        DB::transaction(function () {
            DB::table('users')->whereIn('role', ['surveyor', 'xen_pr'])->update(['role' => 'engineer']);
            DB::table('users')->where('role', 'admin')->update(['role' => 'super_admin']);
            DB::table('users')->where('role', 'bdpo')->update(['role' => 'block_admin']);
            DB::table('users')->where('role', 'ddpo')->update(['role' => 'district_admin']);

            DB::table('role_permissions')->whereIn('role', ['surveyor', 'xen_pr'])->update(['role' => 'engineer']);
            DB::table('role_permissions')->where('role', 'admin')->update(['role' => 'super_admin']);
            DB::table('role_permissions')->where('role', 'bdpo')->update(['role' => 'block_admin']);
            DB::table('role_permissions')->where('role', 'ddpo')->update(['role' => 'district_admin']);

            DB::table('complaint_categories')->where('resolver_role', 'xen_pr')->update(['resolver_role' => 'engineer']);
            DB::table('complaint_categories')->where('resolver_role', 'bdpo')->update(['resolver_role' => 'block_admin']);
            DB::table('complaint_categories')->where('resolver_role', 'ddpo')->update(['resolver_role' => 'district_admin']);
            DB::table('complaint_categories')->where('resolver_role', 'admin')->update(['resolver_role' => 'super_admin']);
        });
    }
};
