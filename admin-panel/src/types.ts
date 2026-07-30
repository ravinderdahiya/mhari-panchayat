// Mirrors mhari-panchayat/backend's User model + API.

export interface User {
  id: number;
  username: string;
  name: string | null;
  email: string | null;
  role: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface AssignableUser {
  id: number;
  name: string | null;
  username: string;
  role: string;
}

export const ALL_ROLES = [
  'super_admin', 'state_admin', 'district_admin', 'block_admin',
  'department_head', 'department_officer', 'engineer', 'sarpanch',
  'secretary', 'citizen', 'contractor', 'vendor',
] as const;

export type ComplaintStatus =
  | 'Pending' | 'Acknowledged' | 'Surveyed' | 'In_Progress' | 'Resolved' | 'Rejected' | 'Closed' | 'Reopened';

// --- MASTER DATA ---
export interface NamedEntity { id: number; name: string; code?: string | null }
export interface State extends NamedEntity {}
export interface District extends NamedEntity { state_id: number; state?: State }
export interface Block extends NamedEntity { district_id: number; district?: District }
export interface Panchayat extends NamedEntity { block_id: number; block?: Block }
export interface Village extends NamedEntity { panchayat_id: number; panchayat?: Panchayat }
export interface Department extends NamedEntity {}
export interface Designation extends NamedEntity {}
export interface ComplaintCategory extends NamedEntity {
  sort_order?: number;
  parent_id?: number | null;
  parent?: ComplaintCategory | null;
  district_id?: number | null;
  district?: District | null;
}
export interface ComplaintPriority extends NamedEntity { level: number }

export interface TimelineEntry {
  id: number;
  status: string;
  title: string;
  description: string | null;
  photo_url: string | null;
  created_at: string | null;
  performed_by: { id: number; name: string | null; username: string; role: string } | null;
}

export interface TransferEntry {
  id: number;
  reason: string | null;
  created_at: string;
  from_user: { id: number; name: string | null; username: string } | null;
  to_user: { id: number; name: string | null; username: string };
  transferred_by: { id: number; name: string | null; username: string };
}

export interface Complaint {
  id: number;
  user_id: number;
  assigned_to_id: number | null;
  category_id: number;
  category: ComplaintCategory;
  village: string | null;
  panchayat: string | null;
  description: string | null;
  priority_id: number;
  priority: ComplaintPriority;
  lat: number | null;
  long: number | null;
  before_photo_url: string | null;
  during_photo_url: string | null;
  after_photo_url: string | null;
  voice_note_url: string | null;
  status: ComplaintStatus;
  citizen_rating: number | null;
  citizen_feedback: string | null;
  duplicate_of_id: number | null;
  duplicate_of: { id: number; category: { name: string } } | null;
  verified_at: string | null;
  verified_by: { id: number; name: string | null; username: string } | null;
  created_at: string;
  updated_at: string;
  user: { id: number; name: string | null; username: string } | null;
  assigned_to: { id: number; name: string | null; username: string; role: string } | null;
  timeline: TimelineEntry[];
  transfers: TransferEntry[];
}

export interface TrendPoint {
  date: string;
  Pending: number;
  Acknowledged: number;
  Resolved: number;
  Closed: number;
}

export interface ClosedByPerson {
  user_id: number;
  name: string | null;
  username: string;
  count: number;
  avgHours: number;
}

export interface ComplaintReports {
  total: number;
  pending: number;
  inProgress: number;
  completed: number;
  rejected: number;
  today: number;
  thisMonth: number;
  avgResolutionHours: number | null;
  byStatus: Record<string, number>;
  byCategory: Record<string, number>;
  trend: TrendPoint[];
  closedByPerson: ClosedByPerson[];
}

// --- ROLES & PERMISSIONS ---
export interface Permission {
  key: string;
  label: string;
  group: string;
}

export interface RolePermissionMatrix {
  roles: string[];
  permissions: Permission[];
  matrix: Record<string, string[]>;
}

// --- USERS (admin management) ---
export interface AdminUser {
  id: number;
  username: string;
  name: string | null;
  email: string | null;
  role: string;
  is_active: boolean;
  department_id: number | null;
  department: Department | null;
  created_at: string;
  registration_status: 'pending_review' | 'active' | 'rejected' | null;
  rejection_reason: string | null;
}

// --- VILLAGE ASSETS (GIS infrastructure tracking) ---
export type AssetGeometryType = 'Point' | 'Line' | 'Polygon';
export type AssetStatus = 'Working' | 'Not Working' | 'Under Construction';
export type AssetCondition = 'Good' | 'Fair' | 'Poor';

export interface AssetSubtype {
  name: string;
  geometryType: AssetGeometryType;
}

export interface AssetCategoryDef {
  category: string;
  subtypes: AssetSubtype[];
}

export interface VillageAsset {
  id: number;
  village_id: number;
  village?: Village;
  category: string;
  subtype: string;
  asset_name: string;
  geometry_type: AssetGeometryType;
  latitude: number | null;
  longitude: number | null;
  path: [number, number][] | null;
  status: AssetStatus;
  condition: AssetCondition;
  ward_no: number | null;
  installed_date: string | null;
  last_inspected: string | null;
  remarks: string | null;
  photo_url: string | null;
  created_by: number;
  creator?: { id: number; name: string | null; username: string };
  created_at: string;
}
