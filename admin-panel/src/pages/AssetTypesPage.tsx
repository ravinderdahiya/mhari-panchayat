import { useEffect, useState } from 'react';
import {
  AlertCircle, CheckCircle2, ChevronLeft, ChevronRight, Layers3, LoaderCircle,
  Pencil, Plus, RefreshCw, Trash2, X,
} from 'lucide-react';
import * as api from '../services/api';
import type { MasterPagination } from '../services/api';
import type { Department } from '../types';

interface AdminAssetType {
  id: string;
  name: string;
  iconKey: string;
  sort_order: number;
  is_active: boolean;
  department_ids: number[];
  departments: { id: number; name: string; code: string | null }[];
}

interface AssetTypeForm {
  name: string;
  icon_key: string;
  sort_order: string;
  is_active: boolean;
  department_ids: number[];
}

type ModalAlert = { type: 'success' | 'error'; message: string } | null;

const EMPTY_PAGINATION: MasterPagination = {
  currentPage: 1, lastPage: 1, perPage: 10, total: 0, from: null, to: null,
};

function emptyForm(): AssetTypeForm {
  return { name: '', icon_key: 'apartment', sort_order: '0', is_active: true, department_ids: [] };
}

function visiblePages(currentPage: number, lastPage: number) {
  const count = Math.min(5, lastPage);
  const start = Math.max(1, Math.min(currentPage - 2, lastPage - count + 1));
  return Array.from({ length: count }, (_, index) => start + index);
}

export default function AssetTypesPage() {
  const [items, setItems] = useState<AdminAssetType[]>([]);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [loading, setLoading] = useState(true);
  const [pageError, setPageError] = useState('');
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(10);
  const [pagination, setPagination] = useState<MasterPagination>(EMPTY_PAGINATION);
  const [filterDept, setFilterDept] = useState<number | 'all'>('all');
  const [refreshKey, setRefreshKey] = useState(0);

  const [modalOpen, setModalOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [form, setForm] = useState<AssetTypeForm>(emptyForm);
  const [saving, setSaving] = useState(false);
  const [modalAlert, setModalAlert] = useState<ModalAlert>(null);

  useEffect(() => {
    api.masterApi('departments').list()
      .then(({ items: departmentItems }) => setDepartments(departmentItems as Department[]))
      .catch((error) => setPageError((error as Error).message));
  }, []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setPageError('');

    api.listAdminAssetTypes({ paginated: true, page, perPage, departmentId: filterDept })
      .then((response) => {
        if (cancelled) return;
        const nextPagination = response.pagination ?? {
          ...EMPTY_PAGINATION,
          perPage,
          total: response.items.length,
          from: response.items.length ? 1 : null,
          to: response.items.length || null,
        };
        if (page > nextPagination.lastPage) {
          setPage(nextPagination.lastPage);
          return;
        }
        setItems(response.items as AdminAssetType[]);
        setPagination(nextPagination);
      })
      .catch((error) => {
        if (!cancelled) setPageError((error as Error).message || 'Failed to load asset types');
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => { cancelled = true; };
  }, [filterDept, page, perPage, refreshKey]);

  const openCreate = () => {
    setEditingId(null);
    setForm(emptyForm());
    setModalAlert(null);
    setModalOpen(true);
  };

  const openEdit = (item: AdminAssetType) => {
    setEditingId(item.id);
    setForm({
      name: item.name,
      icon_key: item.iconKey || 'apartment',
      sort_order: String(item.sort_order ?? 0),
      is_active: !!item.is_active,
      department_ids: [...(item.department_ids || [])],
    });
    setModalAlert(null);
    setModalOpen(true);
  };

  const closeModal = () => {
    if (saving) return;
    setModalOpen(false);
    setEditingId(null);
    setForm(emptyForm());
    setModalAlert(null);
  };

  const updateForm = (values: Partial<AssetTypeForm>) => {
    setForm((current) => ({ ...current, ...values }));
    if (modalAlert) setModalAlert(null);
  };

  const toggleDepartment = (id: number) => {
    updateForm({
      department_ids: form.department_ids.includes(id)
        ? form.department_ids.filter((departmentId) => departmentId !== id)
        : [...form.department_ids, id],
    });
  };

  const save = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!form.name.trim()) {
      setModalAlert({ type: 'error', message: 'Asset type name is required.' });
      return;
    }
    if (form.department_ids.length === 0) {
      setModalAlert({ type: 'error', message: 'Select at least one department.' });
      return;
    }

    setSaving(true);
    setModalAlert(null);
    const payload = {
      name: form.name.trim(),
      icon_key: form.icon_key.trim() || 'apartment',
      sort_order: Number(form.sort_order) || 0,
      is_active: form.is_active,
      department_ids: form.department_ids,
    };

    try {
      if (editingId) {
        await api.updateAdminAssetType(Number(editingId), payload);
        setModalAlert({ type: 'success', message: 'Asset type updated successfully.' });
      } else {
        await api.createAdminAssetType(payload);
        setForm(emptyForm());
        setModalAlert({ type: 'success', message: 'Asset type added successfully.' });
      }
      setRefreshKey((current) => current + 1);
    } catch (error) {
      setModalAlert({ type: 'error', message: (error as Error).message || 'Save failed' });
    } finally {
      setSaving(false);
    }
  };

  const remove = async (id: string) => {
    if (!window.confirm('Delete this asset type?')) return;
    setPageError('');
    try {
      await api.deleteAdminAssetType(Number(id));
      if (items.length === 1 && page > 1) setPage((current) => current - 1);
      else setRefreshKey((current) => current + 1);
    } catch (error) {
      setPageError((error as Error).message || 'Delete failed');
    }
  };

  return (
    <div className="space-y-4 w-full">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="font-serif text-xl text-ink flex items-center gap-2">
            <Layers3 className="w-5 h-5 text-sidebar" /> Survey Asset Types
          </h2>
          <p className="text-xs text-muted mt-1">
            Link each infrastructure asset to one or more departments for mobile surveys.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button type="button" onClick={() => setRefreshKey((current) => current + 1)} title="Refresh" disabled={loading}
            className="inline-flex items-center gap-1.5 text-ink border border-line bg-white hover:bg-cream text-xs font-bold px-3.5 py-2.5 rounded-lg cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed">
            <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} /> Refresh
          </button>
          <button type="button" onClick={openCreate}
            className="inline-flex items-center gap-1.5 bg-accent hover:bg-accent-dark text-white text-xs font-bold px-4 py-2.5 rounded-lg cursor-pointer">
            <Plus className="w-3.5 h-3.5" /> Add Asset Type
          </button>
        </div>
      </div>

      {pageError && (
        <div className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg px-3 py-2.5">
          {pageError}
        </div>
      )}

      <div className="bg-white border border-line rounded-xl overflow-hidden w-full">
        <div className="px-4 py-3 border-b border-line flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm font-semibold text-ink">{pagination.total} asset types</p>
          <select value={filterDept === 'all' ? 'all' : String(filterDept)}
            onChange={(event) => {
              setFilterDept(event.target.value === 'all' ? 'all' : Number(event.target.value));
              setPage(1);
            }}
            className="text-xs border border-line rounded-lg px-3 py-2 bg-white outline-none">
            <option value="all">All departments</option>
            {departments.map((department) => (
              <option key={department.id} value={department.id}>{department.name}</option>
            ))}
          </select>
        </div>

        {loading ? (
          <div className="p-10 flex items-center justify-center gap-2 text-sm text-muted">
            <LoaderCircle className="w-4 h-4 animate-spin" /> Loading asset types…
          </div>
        ) : items.length === 0 ? (
          <p className="p-10 text-sm text-muted text-center">No asset types found.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-cream/60 text-[10px] uppercase tracking-wide text-muted">
                <tr>
                  <th className="text-left px-4 py-3 font-semibold w-16">S.No.</th>
                  <th className="text-left px-4 py-3 font-semibold">Asset</th>
                  <th className="text-left px-4 py-3 font-semibold">Departments</th>
                  <th className="text-left px-4 py-3 font-semibold">Status</th>
                  <th className="text-right px-4 py-3 font-semibold w-24">Actions</th>
                </tr>
              </thead>
              <tbody>
                {items.map((item, index) => (
                  <tr key={item.id} className="border-t border-line/70 hover:bg-cream/30">
                    <td className="px-4 py-3 text-xs font-semibold text-muted">
                      {(pagination.currentPage - 1) * pagination.perPage + index + 1}
                    </td>
                    <td className="px-4 py-3 font-medium text-ink">{item.name}</td>
                    <td className="px-4 py-3 text-muted text-xs">
                      {(item.departments || []).map((department) => department.name).join(', ') || '—'}
                    </td>
                    <td className="px-4 py-3">
                      <span className={`text-[11px] font-bold px-2 py-0.5 rounded-full ${
                        item.is_active ? 'bg-status-closed/15 text-status-closed' : 'bg-line text-muted'
                      }`}>
                        {item.is_active ? 'Active' : 'Inactive'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right whitespace-nowrap">
                      <button type="button" onClick={() => openEdit(item)} title="Edit"
                        className="p-1.5 text-muted hover:text-blue-600 cursor-pointer">
                        <Pencil className="w-4 h-4" />
                      </button>
                      <button type="button" onClick={() => remove(item.id)} title="Delete"
                        className="p-1.5 text-muted hover:text-status-rejected cursor-pointer">
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {!loading && pagination.total > 0 && (
          <div className="border-t border-line px-4 py-3 flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-3 text-[11px] text-muted">
              <span>Showing {pagination.from}-{pagination.to} of {pagination.total}</span>
              <label className="flex items-center gap-1.5">Rows
                <select value={perPage} onChange={(event) => { setPerPage(Number(event.target.value)); setPage(1); }}
                  className="border border-line rounded-md bg-white px-2 py-1 outline-none">
                  <option value={10}>10</option><option value={25}>25</option><option value={50}>50</option>
                </select>
              </label>
            </div>
            <div className="flex items-center gap-1">
              <button type="button" aria-label="Previous page" disabled={pagination.currentPage <= 1}
                onClick={() => setPage((current) => Math.max(1, current - 1))}
                className="p-1.5 border border-line rounded-md text-muted disabled:opacity-40 disabled:cursor-not-allowed hover:bg-cream cursor-pointer">
                <ChevronLeft className="w-4 h-4" />
              </button>
              {visiblePages(pagination.currentPage, pagination.lastPage).map((pageNumber) => (
                <button type="button" key={pageNumber} onClick={() => setPage(pageNumber)}
                  className={`min-w-8 h-8 px-2 rounded-md text-xs font-semibold border cursor-pointer ${
                    pageNumber === pagination.currentPage
                      ? 'bg-accent text-white border-accent'
                      : 'bg-white text-ink border-line hover:bg-cream'
                  }`}>
                  {pageNumber}
                </button>
              ))}
              <button type="button" aria-label="Next page" disabled={pagination.currentPage >= pagination.lastPage}
                onClick={() => setPage((current) => Math.min(pagination.lastPage, current + 1))}
                className="p-1.5 border border-line rounded-md text-muted disabled:opacity-40 disabled:cursor-not-allowed hover:bg-cream cursor-pointer">
                <ChevronRight className="w-4 h-4" />
              </button>
            </div>
          </div>
        )}
      </div>

      {modalOpen && (
        <div className="fixed inset-0 z-[80] bg-black/45 flex items-center justify-center p-4" onMouseDown={closeModal}>
          <div className="w-full max-w-2xl max-h-[90vh] overflow-y-auto bg-white rounded-2xl shadow-xl"
            onMouseDown={(event) => event.stopPropagation()}>
            <div className="sticky top-0 bg-white z-10 px-5 py-4 border-b border-line flex items-center justify-between">
              <div>
                <h3 className="text-base font-bold text-ink">{editingId ? 'Edit Asset Type' : 'Add Asset Type'}</h3>
                <p className="text-[11px] text-muted mt-0.5">Link this asset type with at least one department.</p>
              </div>
              <button type="button" onClick={closeModal} disabled={saving}
                className="p-1.5 rounded-lg text-muted hover:bg-cream disabled:opacity-50 cursor-pointer">
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={save}>
              <div className="p-5 space-y-4">
                {modalAlert && (
                  <div role="alert" className={`flex items-start gap-2 rounded-lg border p-3 text-xs ${
                    modalAlert.type === 'success'
                      ? 'bg-emerald-50 border-emerald-200 text-emerald-700'
                      : 'bg-red-50 border-red-200 text-red-700'
                  }`}>
                    {modalAlert.type === 'success'
                      ? <CheckCircle2 className="w-4 h-4 shrink-0" />
                      : <AlertCircle className="w-4 h-4 shrink-0" />}
                    <span>{modalAlert.message}</span>
                  </div>
                )}

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <label className="block sm:col-span-2">
                    <span className="text-[10px] font-bold text-muted uppercase block mb-1.5">Name *</span>
                    <input value={form.name} required onChange={(event) => updateForm({ name: event.target.value })}
                      placeholder="e.g. Govt. Primary School"
                      className="w-full border border-line rounded-lg px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-accent/40" />
                  </label>
                  <label className="block">
                    <span className="text-[10px] font-bold text-muted uppercase block mb-1.5">Icon key</span>
                    <input value={form.icon_key} onChange={(event) => updateForm({ icon_key: event.target.value })}
                      className="w-full border border-line rounded-lg px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-accent/40" />
                  </label>
                  <label className="block">
                    <span className="text-[10px] font-bold text-muted uppercase block mb-1.5">Sort order</span>
                    <input type="number" min={0} value={form.sort_order}
                      onChange={(event) => updateForm({ sort_order: event.target.value })}
                      className="w-full border border-line rounded-lg px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-accent/40" />
                  </label>
                </div>

                <label className="inline-flex items-center gap-2 text-sm cursor-pointer">
                  <input type="checkbox" checked={form.is_active}
                    onChange={(event) => updateForm({ is_active: event.target.checked })} />
                  Active
                </label>

                <div>
                  <p className="text-[10px] font-bold text-muted uppercase mb-2">Departments *</p>
                  <div className="flex flex-wrap gap-2 max-h-52 overflow-y-auto border border-line rounded-lg p-3">
                    {departments.map((department) => {
                      const selected = form.department_ids.includes(department.id);
                      return (
                        <button key={department.id} type="button" onClick={() => toggleDepartment(department.id)}
                          className={`text-[11px] font-semibold px-2.5 py-1.5 rounded-full border cursor-pointer ${
                            selected ? 'bg-sidebar text-white border-sidebar' : 'bg-white text-muted border-line hover:border-sidebar/40'
                          }`}>
                          {department.name}
                        </button>
                      );
                    })}
                  </div>
                </div>
              </div>

              <div className="sticky bottom-0 bg-cream px-5 py-4 border-t border-line flex justify-end gap-2">
                <button type="button" onClick={closeModal} disabled={saving}
                  className="text-xs font-semibold text-muted border border-line bg-white px-4 py-2 rounded-lg hover:bg-cream disabled:opacity-50 cursor-pointer">
                  Close
                </button>
                <button type="submit" disabled={saving}
                  className="inline-flex items-center gap-1.5 bg-accent hover:bg-accent-dark text-white text-xs font-bold px-4 py-2 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer">
                  {saving ? <LoaderCircle className="w-3.5 h-3.5 animate-spin" /> : editingId ? <Pencil className="w-3.5 h-3.5" /> : <Plus className="w-3.5 h-3.5" />}
                  {saving ? 'Saving…' : editingId ? 'Update' : 'Submit'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
