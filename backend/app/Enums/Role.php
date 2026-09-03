<?php

namespace App\Enums;

// Seeded system roles. The runtime list (admin CRUD, user assignment,
// permission matrix) lives in the `roles` table; this enum is the starting
// set plus the constants code still compares against (`admin`, `surveyor`,
// …). Individual `$user->role === 'admin'`-style checks stay as plain
// strings (users.role is a string column, not cast to this enum).
enum Role: string
{
    case SuperAdmin = 'super_admin';
    case Admin = 'admin';
    case StateAdmin = 'state_admin';
    case Ddpo = 'ddpo';
    case Bdpo = 'bdpo';
    case DepartmentHead = 'department_head';
    case DepartmentOfficer = 'department_officer';
    case Surveyor = 'surveyor';
    case Cplo = 'cplo';
    case XenPr = 'xen_pr';
    case Sarpanch = 'sarpanch';
    case Secretary = 'secretary';
    case Citizen = 'citizen';
    case Contractor = 'contractor';
    case Vendor = 'vendor';
    case DeputyCommissioner = 'deputy_commissioner';
    case GramSachiv = 'gram_sachiv';
    case CeoZp = 'ceo_zp';

    /** @return list<string> */
    public static function values(): array
    {
        return array_column(self::cases(), 'value');
    }
}
