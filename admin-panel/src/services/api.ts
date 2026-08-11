import type { AdminUser, AssetCategoryDef, AssetSurvey, AssignableUser, CitizenProfile, CitizenStats, Complaint, ComplaintReports, RolePermissionMatrix, User, VillageAsset } from '../types';

// 127.0.0.1, not localhost - on this machine "localhost" resolves to ::1
// first, and the dev server only listens on IPv4, so every request pays a
// ~200ms IPv6-then-IPv4 fallback penalty before falling back to the working
// address. Connecting to 127.0.0.1 directly skips that entirely.
const API_BASE_URL = (import.meta as any).env?.VITE_API_BASE_URL || 'http://127.0.0.1:8083';
const TOKEN_KEY = 'mhari_panchayat_token';

// Uploaded media URLs may have been persisted with an older host/port.
// Keep the stored path, but always serve it from the API currently in use.
export function mediaUrl(value: string): string {
  try {
    const parsed = new URL(value, API_BASE_URL);
    const api = new URL(API_BASE_URL);
    return `${api.origin}${parsed.pathname}${parsed.search}${parsed.hash}`;
  } catch {
    return value;
  }
}

export const getToken = () => localStorage.getItem(TOKEN_KEY);
export const setToken = (token: string) => localStorage.setItem(TOKEN_KEY, token);
export const clearToken = () => localStorage.removeItem(TOKEN_KEY);

async function request<T = any>(path: string, options: RequestInit = {}): Promise<T> {
  const token = getToken();
  const headers: Record<string, string> = {
    Accept: 'application/json',
    ...(options.headers as Record<string, string> || {}),
  };
  if (token) headers['Authorization'] = `Bearer ${token}`;

  const res = await fetch(`${API_BASE_URL}${path}`, { ...options, headers });
  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    const message = data.errors
      ? (Object.values(data.errors)[0] as string[])[0]
      : data.message || `Request failed (${res.status})`;
    throw new Error(message);
  }
  return data;
}

const jsonRequest = <T = any>(path: string, method: string, body?: object) =>
  request<T>(path, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });

// No Content-Type header here - the browser sets multipart/form-data with
// the correct boundary automatically when the body is a FormData instance.
const formRequest = <T = any>(path: string, method: string, form: FormData) =>
  request<T>(path, { method, body: form });

export const register = (username: string, password: string, name?: string, email?: string) =>
  jsonRequest<{ success: boolean; token: string; user: User }>('/api/auth/register', 'POST', { username, password, name, email });

export const login = (username: string, password: string) =>
  jsonRequest<{ success: boolean; token: string; user: User }>('/api/auth/login', 'POST', { username, password });

export const getMe = () => request<{ success: boolean; user: User }>('/api/auth/me');

export const changePassword = (current_password: string, new_password: string, new_password_confirmation: string) =>
  jsonRequest<{ success: boolean; message: string }>('/api/auth/change-password', 'POST', {
    current_password, new_password, new_password_confirmation,
  });

export const requestPasswordReset = (username: string) =>
  jsonRequest<{ success: boolean; message: string; devToken?: string }>('/api/auth/forgot-password/request', 'POST', { username });

export const resetPassword = (token: string, new_password: string, new_password_confirmation: string) =>
  jsonRequest<{ success: boolean; message: string }>('/api/auth/forgot-password/reset', 'POST', {
    token, new_password, new_password_confirmation,
  });

// --- MASTER DATA (Super Admin manages; any authenticated user can read) ---
// One generic helper reused for every master entity instead of ~9 bespoke
// functions - matches the backend's MasterDataController factory.
export interface MasterPagination {
  currentPage: number;
  lastPage: number;
  perPage: number;
  total: number;
  from: number | null;
  to: number | null;
}

export const masterApi = (entity: string) => ({
  list: (options: {
    paginated?: boolean; page?: number; perPage?: number; search?: string; status?: 'active' | 'inactive';
  } = {}) => {
    const params = new URLSearchParams();
    if (options.paginated) params.set('paginated', '1');
    if (options.page) params.set('page', String(options.page));
    if (options.perPage) params.set('per_page', String(options.perPage));
    if (options.search) params.set('search', options.search);
    if (options.status) params.set('status', options.status);
    const query = params.toString();

    return request<{
      success: boolean; items: any[]; pagination?: MasterPagination;
      counts?: { all: number; active: number; inactive: number };
    }>(`/api/master/${entity}${query ? `?${query}` : ''}`);
  },
  create: (data: object) => jsonRequest<{ success: boolean; item: any }>(`/api/master/${entity}`, 'POST', data),
  update: (id: number, data: object) => jsonRequest<{ success: boolean; item: any }>(`/api/master/${entity}/${id}`, 'PUT', data),
  remove: (id: number) => jsonRequest<{ success: boolean }>(`/api/master/${entity}/${id}`, 'DELETE'),
});

// --- COMPLAINTS ---
export const getComplaints = () => request<{ success: boolean; complaints: Complaint[] }>('/api/complaints');

export const getComplaint = (id: number) =>
  request<{ success: boolean; complaint: Complaint }>(`/api/complaints/${id}`);

export const getComplaintReports = () =>
  request<{ success: boolean; reports: ComplaintReports }>('/api/complaints/reports');

export const acknowledgeComplaint = (id: number, assigned_to_id?: number) => {
  const form = new FormData();
  if (assigned_to_id) form.append('assigned_to_id', String(assigned_to_id));
  return formRequest<{ success: boolean; complaint: Complaint }>(`/api/complaints/${id}/acknowledge`, 'PATCH', form);
};

const SURVEY_PHOTO_FIELD: Record<'Before' | 'During' | 'After', string> = {
  Before: 'before_photo', During: 'during_photo', After: 'after_photo',
};

export const submitSurvey = (id: number, stage: 'Before' | 'During' | 'After', notes?: string, photo?: File) => {
  const form = new FormData();
  form.append('stage', stage);
  if (notes) form.append('notes', notes);
  if (photo) form.append(SURVEY_PHOTO_FIELD[stage], photo);
  return formRequest<{ success: boolean; complaint: Complaint }>(`/api/complaints/${id}/survey`, 'PATCH', form);
};

export const resolveComplaint = (id: number, notes?: string) =>
  jsonRequest<{ success: boolean; complaint: Complaint }>(`/api/complaints/${id}/resolve`, 'PATCH', { notes });

export const verifyComplaint = (id: number, notes?: string) =>
  jsonRequest<{ success: boolean; complaint: Complaint }>(`/api/complaints/${id}/verify`, 'PATCH', { notes });

export const rateComplaint = (id: number, rating: number, feedback?: string) =>
  jsonRequest<{ success: boolean; complaint: Complaint }>(`/api/complaints/${id}/rate`, 'PATCH', { rating, feedback });

export const transferComplaint = (id: number, to_user_id: number, reason?: string) =>
  jsonRequest<{ success: boolean; complaint: Complaint }>(`/api/complaints/${id}/transfer`, 'PATCH', { to_user_id, reason });

export const reopenComplaint = (id: number, reason: string) =>
  jsonRequest<{ success: boolean; complaint: Complaint }>(`/api/complaints/${id}/reopen`, 'PATCH', { reason });

export const deleteComplaint = (id: number) =>
  jsonRequest<{ success: boolean }>(`/api/complaints/${id}`, 'DELETE');

// --- ROLES & PERMISSIONS ---
export const getRolePermissions = () =>
  request<{ success: boolean } & RolePermissionMatrix>('/api/roles/permissions');

export const updateRolePermissions = (role: string, permissions: string[]) =>
  jsonRequest<{ success: boolean; message: string; permissions: string[] }>(`/api/roles/${role}/permissions`, 'PUT', { permissions });

// --- USERS (admin management) ---
export const getUsers = () => request<{ success: boolean; users: AdminUser[] }>('/api/users');
export const getCitizens = (options: {
  page?: number;
  perPage?: number;
  query?: string;
  status?: 'all' | 'active' | 'inactive';
} = {}) => {
  const params = new URLSearchParams({
    page: String(options.page ?? 1),
    per_page: String(options.perPage ?? 10),
  });
  if (options.query?.trim()) params.set('q', options.query.trim());
  if (options.status && options.status !== 'all') params.set('status', options.status);

  return request<{
    success: boolean;
    citizens: CitizenProfile[];
    pagination: MasterPagination;
    stats: CitizenStats;
  }>(`/api/citizens?${params.toString()}`);
};

export const deleteCitizen = (id: number) =>
  jsonRequest<{ success: boolean; message: string }>(`/api/citizens/${id}`, 'DELETE');

export const updateUser = (
  id: number,
  fields: {
    role?: string;
    department_id?: number | null;
    department_ids?: number[];
    village_ids?: number[];
    is_active?: boolean;
  },
) => jsonRequest<{ success: boolean; message: string; user: AdminUser }>(`/api/users/${id}`, 'PATCH', fields);

export const deleteUser = (id: number) =>
  jsonRequest<{ success: boolean; message: string }>(`/api/users/${id}`, 'DELETE');

// --- REGISTRATION REVIEW (self-registered surveyors/officers) ---
export const approveRegistration = (id: number) =>
  jsonRequest<{ success: boolean; message: string }>(`/api/registrations/${id}/approve`, 'PATCH');

export const unapproveRegistration = (id: number, reason?: string) =>
  jsonRequest<{ success: boolean; message: string }>(`/api/registrations/${id}/unapprove`, 'PATCH', {
    reason: reason || undefined,
  });

export const rejectRegistration = (id: number, reason: string) =>
  jsonRequest<{ success: boolean; message: string }>(`/api/registrations/${id}/reject`, 'PATCH', { reason });

// Lighter-weight than getUsers() - open to any non-citizen staff role, not
// just super_admin, so pickers like "assign to" / "transfer to" work for
// sarpanch/secretary/etc too.
export const getAssignableUsers = () => request<{ success: boolean; users: AssignableUser[] }>('/api/users/assignable');

// HARSAC's Panchayat/district boundary MapServer, reverse-proxied by our own
// backend (gis.harsac.in doesn't send CORS headers, so the browser can't hit
// it directly, and the real GIS credentials stay server-side either way).
export const gisPanchayatMapServerUrl = `${API_BASE_URL}/api/gis/panchayat`;

// Same reasoning, for HARSAC's hosted Panchayat/district boundary vector tile
// service (sharper at high zoom than the MapServer above).
export const gisPanchayatVectorTileUrl = `${API_BASE_URL}/api/gis/panchayat-vector`;

// --- VILLAGE ASSETS (GIS infrastructure tracking) ---
export const getAssetCategories = () =>
  request<{ success: boolean; categories: AssetCategoryDef[] }>('/api/master/asset-categories');

export const getVillageAssets = () =>
  request<{ success: boolean; assets: VillageAsset[] }>('/api/village-assets');

export const createVillageAsset = (form: FormData) =>
  formRequest<{ success: boolean; asset: VillageAsset }>('/api/village-assets', 'POST', form);

// Laravel can't parse a multipart body on a genuine PUT request (PHP only
// populates $_POST for multipart on POST) - so this spoofs the method via a
// `_method` field on an actual POST, same as Blade's @method('PUT').
export const updateVillageAsset = (id: number, form: FormData) => {
  form.append('_method', 'PUT');
  return formRequest<{ success: boolean; asset: VillageAsset }>(`/api/village-assets/${id}`, 'POST', form);
};

export const deleteVillageAsset = (id: number) =>
  jsonRequest<{ success: boolean }>(`/api/village-assets/${id}`, 'DELETE');

// --- SURVEY ASSET TYPES (department-linked catalog for mobile app) ---
export const listAdminAssetTypes = (options: {
  paginated?: boolean;
  page?: number;
  perPage?: number;
  departmentId?: number | 'all';
} = {}) => {
  const params = new URLSearchParams();
  if (options.paginated) params.set('paginated', '1');
  if (options.page) params.set('page', String(options.page));
  if (options.perPage) params.set('per_page', String(options.perPage));
  if (options.departmentId && options.departmentId !== 'all') {
    params.set('department_id', String(options.departmentId));
  }
  const query = params.toString();

  return request<{ success: boolean; items: any[]; pagination?: MasterPagination }>(
    `/api/admin/asset-types${query ? `?${query}` : ''}`,
  );
};

export const createAdminAssetType = (data: {
  name: string;
  icon_key?: string;
  sort_order?: number;
  is_active?: boolean;
  department_ids: number[];
}) => jsonRequest<{ success: boolean; item: any }>('/api/admin/asset-types', 'POST', data);

export const updateAdminAssetType = (
  id: number,
  data: {
    name?: string;
    icon_key?: string;
    sort_order?: number;
    is_active?: boolean;
    department_ids?: number[];
  },
) => jsonRequest<{ success: boolean; item: any }>(`/api/admin/asset-types/${id}`, 'PUT', data);

export const deleteAdminAssetType = (id: number) =>
  jsonRequest<{ success: boolean }>(`/api/admin/asset-types/${id}`, 'DELETE');

// --- MOBILE ASSET SURVEYS ---
export const getAssetSurveys = (options: {
  page?: number;
  perPage?: number;
  query?: string;
  condition?: string;
} = {}) => {
  const params = new URLSearchParams({
    paginated: '1',
    page: String(options.page ?? 1),
    per_page: String(options.perPage ?? 10),
  });
  if (options.query?.trim()) params.set('q', options.query.trim());
  if (options.condition && options.condition !== 'ALL') params.set('condition', options.condition);

  return request<{
    success: boolean;
    surveys: AssetSurvey[];
    pagination: import('../types').AssetSurveyPagination;
    stats: import('../types').AssetSurveyStats;
  }>(`/api/surveys?${params.toString()}`);
};

export const getAssetSurvey = (id: string) =>
  request<{ success: boolean; survey: AssetSurvey }>(`/api/surveys/${id}`);
