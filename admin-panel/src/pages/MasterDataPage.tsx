import { useEffect, useState } from 'react';
import {
  AlertCircle, Briefcase, Building2, CheckCircle2, ChevronLeft, ChevronRight,
  Home, IdCard, Inbox, Landmark, LayoutGrid, ListChecks, LoaderCircle, MapPin,
  Pencil, Plus, ShieldCheck, SignalHigh, Tags, Trash2, X,
} from 'lucide-react';
import { masterApi } from '../services/api';
import type { MasterPagination } from '../services/api';

interface FieldConfig {
  key: string;
  label: string;
  type: 'text' | 'number' | 'select';
  optionsFrom?: string;
  required?: boolean;
}

interface EntityConfig {
  key: string;
  label: string;
  icon: typeof Landmark;
  fields: FieldConfig[];
  readOnly?: boolean;
}

interface EntityGroup {
  label: string;
  entities: EntityConfig[];
}

const GROUPS: EntityGroup[] = [
  { label: 'Geographic Hierarchy', entities: [
    { key: 'states', label: 'States', icon: Landmark, fields: [
      { key: 'name', label: 'Name', type: 'text', required: true },
      { key: 'code', label: 'Code', type: 'text', required: true },
    ] },
    { key: 'districts', label: 'Districts', icon: MapPin, fields: [
      { key: 'name', label: 'Name', type: 'text', required: true },
      { key: 'code', label: 'Code', type: 'text', required: true },
      { key: 'state_id', label: 'State', type: 'select', optionsFrom: 'states', required: true },
    ] },
    { key: 'tehsils', label: 'Tehsils / Sub-Tehsils', icon: MapPin, fields: [
      { key: 'name', label: 'Name', type: 'text', required: true },
      { key: 'code', label: 'Code', type: 'text', required: true },
      { key: 'district_id', label: 'District', type: 'select', optionsFrom: 'districts', required: true },
    ] },
    { key: 'blocks', label: 'Blocks', icon: LayoutGrid, fields: [
      { key: 'name', label: 'Name', type: 'text', required: true },
      { key: 'code', label: 'Code', type: 'text', required: true },
      { key: 'district_id', label: 'District', type: 'select', optionsFrom: 'districts', required: true },
    ] },
    { key: 'panchayats', label: 'Panchayats', icon: Building2, fields: [
      { key: 'name', label: 'Name', type: 'text', required: true },
      { key: 'code', label: 'Code', type: 'text', required: true },
      { key: 'block_id', label: 'Block', type: 'select', optionsFrom: 'blocks', required: true },
    ] },
    { key: 'villages', label: 'Villages', icon: Home, fields: [
      { key: 'name', label: 'Name', type: 'text', required: true },
      { key: 'code', label: 'Code', type: 'text', required: true },
      { key: 'panchayat_id', label: 'Panchayat', type: 'select', optionsFrom: 'panchayats', required: true },
    ] },
  ] },
  { label: 'Organization', entities: [
    { key: 'departments', label: 'Departments', icon: Briefcase, fields: [
      { key: 'name', label: 'Name', type: 'text', required: true },
      { key: 'code', label: 'Code', type: 'text', required: true },
    ] },
    { key: 'designations', label: 'Designations', icon: IdCard, fields: [
      { key: 'name', label: 'Name', type: 'text', required: true },
    ] },
  ] },
  { label: 'Complaint Setup', entities: [
    { key: 'complaint-categories', label: 'Complaint Categories', icon: Tags, fields: [
      { key: 'name', label: 'Name', type: 'text', required: true },
      { key: 'code', label: 'Code', type: 'text', required: true },
      { key: 'sort_order', label: 'Sort Order', type: 'number' },
      { key: 'parent_id', label: 'Parent Category', type: 'select', optionsFrom: 'complaint-categories' },
      { key: 'district_id', label: 'District', type: 'select', optionsFrom: 'districts' },
    ] },
    { key: 'complaint-priorities', label: 'Complaint Priorities', icon: SignalHigh, fields: [
      { key: 'name', label: 'Name', type: 'text', required: true },
      { key: 'level', label: 'Sort Level', type: 'number' },
    ] },
  ] },
  { label: 'Reference (read-only)', entities: [
    { key: 'roles', label: 'Roles', icon: ShieldCheck, readOnly: true, fields: [
      { key: 'name', label: 'Name', type: 'text' },
    ] },
    { key: 'complaint-statuses', label: 'Complaint Statuses', icon: ListChecks, readOnly: true, fields: [
      { key: 'name', label: 'Name', type: 'text' },
    ] },
  ] },
];

const ENTITIES = GROUPS.flatMap((group) => group.entities);
const EMPTY_PAGINATION: MasterPagination = {
  currentPage: 1, lastPage: 1, perPage: 10, total: 0, from: null, to: null,
};

function getVisiblePages(currentPage: number, lastPage: number) {
  const count = Math.min(5, lastPage);
  const start = Math.max(1, Math.min(currentPage - 2, lastPage - count + 1));
  return Array.from({ length: count }, (_, index) => start + index);
}

interface MasterDataPageProps {
  initialEntityKey?: string | null;
}

type ModalAlert = { type: 'success' | 'error'; message: string } | null;

export default function MasterDataPage({ initialEntityKey }: MasterDataPageProps) {
  const [activeKey, setActiveKey] = useState(
    ENTITIES.some((entity) => entity.key === initialEntityKey) ? initialEntityKey! : ENTITIES[0].key,
  );
  const active = ENTITIES.find((entity) => entity.key === activeKey)!;
  const ActiveIcon = active.icon;

  const [items, setItems] = useState<any[]>([]);
  const [pagination, setPagination] = useState<MasterPagination>(EMPTY_PAGINATION);
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(10);
  const [refreshKey, setRefreshKey] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [pageError, setPageError] = useState('');

  const [modalOpen, setModalOpen] = useState(false);
  const [form, setForm] = useState<Record<string, string>>({});
  const [editingId, setEditingId] = useState<number | null>(null);
  const [modalAlert, setModalAlert] = useState<ModalAlert>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [optionsLoading, setOptionsLoading] = useState(false);
  const [optionSets, setOptionSets] = useState<Record<string, any[]>>({});

  useEffect(() => {
    if (initialEntityKey && ENTITIES.some((entity) => entity.key === initialEntityKey)) {
      setActiveKey(initialEntityKey);
      setPage(1);
      setModalOpen(false);
    }
  }, [initialEntityKey]);

  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);
    setPageError('');

    masterApi(active.key).list({ paginated: true, page, perPage })
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
        setItems(response.items);
        setPagination(nextPagination);
      })
      .catch((error) => {
        if (!cancelled) setPageError((error as Error).message);
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => { cancelled = true; };
  }, [active, page, perPage, refreshKey]);

  const loadOptions = async (entity: EntityConfig) => {
    const parentKeys = [...new Set(entity.fields
      .filter((field) => field.optionsFrom)
      .map((field) => field.optionsFrom!))];
    const uncached = parentKeys.filter((key) => !optionSets[key]);
    if (uncached.length === 0) return;

    setOptionsLoading(true);
    try {
      const responses = await Promise.all(uncached.map((key) => masterApi(key).list()));
      setOptionSets((current) => {
        const next = { ...current };
        uncached.forEach((key, index) => { next[key] = responses[index].items; });
        return next;
      });
    } catch (error) {
      setModalAlert({ type: 'error', message: (error as Error).message });
    } finally {
      setOptionsLoading(false);
    }
  };

  const openAdd = () => {
    setEditingId(null);
    setForm({});
    setModalAlert(null);
    setModalOpen(true);
    void loadOptions(active);
  };

  const openEdit = (item: any) => {
    const next: Record<string, string> = {};
    active.fields.forEach((field) => { next[field.key] = String(item[field.key] ?? ''); });
    setEditingId(item.id);
    setForm(next);
    setModalAlert(null);
    setModalOpen(true);
    void loadOptions(active);
  };

  const closeModal = () => {
    if (isSubmitting) return;
    setModalOpen(false);
    setForm({});
    setEditingId(null);
    setModalAlert(null);
  };

  const updateField = (key: string, value: string) => {
    setForm((current) => ({ ...current, [key]: value }));
    if (modalAlert) setModalAlert(null);
  };

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    setModalAlert(null);
    setIsSubmitting(true);

    const data: Record<string, unknown> = { ...form };
    active.fields
      .filter((field) => field.type === 'number' || field.type === 'select')
      .forEach((field) => {
        if (data[field.key] !== undefined && data[field.key] !== '') {
          data[field.key] = Number(data[field.key]);
        } else {
          delete data[field.key];
        }
      });

    try {
      if (editingId) {
        await masterApi(active.key).update(editingId, data);
        setModalAlert({ type: 'success', message: 'Entry updated successfully.' });
      } else {
        await masterApi(active.key).create(data);
        setForm({});
        setModalAlert({ type: 'success', message: 'Entry added successfully.' });
      }
      setRefreshKey((current) => current + 1);
    } catch (error) {
      setModalAlert({ type: 'error', message: (error as Error).message });
    } finally {
      setIsSubmitting(false);
    }
  };

  const remove = async (id: number) => {
    if (!window.confirm('Delete this entry?')) return;
    setPageError('');
    try {
      await masterApi(active.key).remove(id);
      if (items.length === 1 && page > 1) setPage((current) => current - 1);
      else setRefreshKey((current) => current + 1);
    } catch (error) {
      setPageError((error as Error).message);
    }
  };

  const displayValue = (item: any, field: FieldConfig) => {
    if (field.type === 'select' && field.optionsFrom) {
      const parentField = field.key.replace(/_id$/, '');
      return item[parentField]?.name ?? item[field.key] ?? '—';
    }
    return item[field.key] ?? '—';
  };

  return (
    <div className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <ActiveIcon className="w-4 h-4 text-accent-dark" />
            <h2 className="text-sm font-bold text-slate-800">{active.label}</h2>
            <span className="text-xs text-slate-400 tabular-nums">({pagination.total})</span>
          </div>
          {!active.readOnly && (
            <button type="button" onClick={openAdd}
              className="inline-flex items-center gap-1.5 bg-accent hover:bg-accent-dark text-white text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer">
              <Plus className="w-3.5 h-3.5" /> Add
            </button>
          )}
        </div>

        {pageError && <p className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg p-3">{pageError}</p>}

        <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden">
          {isLoading ? (
            <div className="p-10 flex items-center justify-center gap-2 text-sm text-slate-400">
              <LoaderCircle className="w-4 h-4 animate-spin" /> Loading data…
            </div>
          ) : items.length === 0 ? (
            <div className="p-10 text-center">
              <Inbox className="w-6 h-6 text-slate-300 mx-auto mb-2" />
              <p className="text-sm text-slate-400">No entries yet.</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="bg-slate-50 text-slate-500 uppercase text-[10px]">
                    <th className="text-left p-3 w-16">S.No.</th>
                    {active.fields.map((field) => <th key={field.key} className="text-left p-3">{field.label}</th>)}
                    {!active.readOnly && <th className="p-3 w-24 text-right">Actions</th>}
                  </tr>
                </thead>
                <tbody>
                  {items.map((item, index) => (
                    <tr key={item.id ?? item.name} className="border-t border-slate-100 hover:bg-slate-50/60">
                      <td className="p-3 text-slate-500 font-semibold">
                        {(pagination.currentPage - 1) * pagination.perPage + index + 1}
                      </td>
                      {active.fields.map((field) => (
                        <td key={field.key} className="p-3 text-slate-700">{displayValue(item, field)}</td>
                      ))}
                      {!active.readOnly && (
                        <td className="p-3">
                          <div className="flex justify-end gap-1">
                            <button type="button" onClick={() => openEdit(item)} title="Edit"
                              className="p-1.5 rounded-lg text-blue-600 hover:bg-blue-50 cursor-pointer">
                              <Pencil className="w-3.5 h-3.5" />
                            </button>
                            <button type="button" onClick={() => remove(item.id)} title="Delete"
                              className="p-1.5 rounded-lg text-red-600 hover:bg-red-50 cursor-pointer">
                              <Trash2 className="w-3.5 h-3.5" />
                            </button>
                          </div>
                        </td>
                      )}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {!isLoading && pagination.total > 0 && (
            <div className="border-t border-slate-200 px-4 py-3 flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-3 text-[11px] text-slate-500">
                <span>Showing {pagination.from}-{pagination.to} of {pagination.total}</span>
                <label className="flex items-center gap-1.5">Rows
                  <select value={perPage} onChange={(event) => { setPerPage(Number(event.target.value)); setPage(1); }}
                    className="border border-slate-200 rounded-md bg-white px-2 py-1 outline-none">
                    <option value={10}>10</option><option value={25}>25</option><option value={50}>50</option>
                  </select>
                </label>
              </div>
              <div className="flex items-center gap-1">
                <button type="button" aria-label="Previous page" disabled={pagination.currentPage <= 1}
                  onClick={() => setPage((current) => Math.max(1, current - 1))}
                  className="p-1.5 border border-slate-200 rounded-md text-slate-500 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-slate-50 cursor-pointer">
                  <ChevronLeft className="w-4 h-4" />
                </button>
                {getVisiblePages(pagination.currentPage, pagination.lastPage).map((pageNumber) => (
                  <button type="button" key={pageNumber} onClick={() => setPage(pageNumber)}
                    className={`min-w-8 h-8 px-2 rounded-md text-xs font-semibold border cursor-pointer ${
                      pageNumber === pagination.currentPage
                        ? 'bg-accent text-white border-accent'
                        : 'bg-white text-slate-700 border-slate-200 hover:bg-slate-50'
                    }`}>
                    {pageNumber}
                  </button>
                ))}
                <button type="button" aria-label="Next page" disabled={pagination.currentPage >= pagination.lastPage}
                  onClick={() => setPage((current) => Math.min(pagination.lastPage, current + 1))}
                  className="p-1.5 border border-slate-200 rounded-md text-slate-500 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-slate-50 cursor-pointer">
                  <ChevronRight className="w-4 h-4" />
                </button>
              </div>
            </div>
          )}
        </div>

      {modalOpen && (
        <div className="fixed inset-0 z-[80] bg-black/45 flex items-center justify-center p-4" onMouseDown={closeModal}>
          <div className="w-full max-w-2xl bg-white rounded-2xl shadow-xl overflow-hidden" onMouseDown={(event) => event.stopPropagation()}>
            <div className="px-5 py-4 border-b border-slate-200 flex items-center justify-between">
              <div>
                <h3 className="text-base font-bold text-slate-800">{editingId ? `Edit ${active.label}` : `Add ${active.label}`}</h3>
                <p className="text-[11px] text-slate-500 mt-0.5">Enter the details and submit the form.</p>
              </div>
              <button type="button" onClick={closeModal} disabled={isSubmitting}
                className="p-1.5 rounded-lg text-slate-500 hover:bg-slate-100 disabled:opacity-50 cursor-pointer">
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={submit}>
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

                {optionsLoading && (
                  <div className="flex items-center gap-2 text-xs text-slate-500">
                    <LoaderCircle className="w-3.5 h-3.5 animate-spin" /> Loading dropdown options…
                  </div>
                )}

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  {active.fields.map((field) => (
                    <label key={field.key} className="block">
                      <span className="text-[10px] font-bold text-slate-500 uppercase block mb-1.5">
                        {field.label}{field.required && <span className="text-red-500"> *</span>}
                      </span>
                      {field.type === 'select' ? (
                        <select value={form[field.key] || ''} required={field.required} disabled={optionsLoading}
                          onChange={(event) => updateField(field.key, event.target.value)}
                          className="w-full text-xs border border-slate-300 rounded-lg px-3 py-2.5 bg-white focus:outline-none focus:ring-2 focus:ring-accent/40 disabled:bg-slate-50">
                          <option value="">— select —</option>
                          {(optionSets[field.optionsFrom!] || []).map((option) => (
                            <option key={option.id} value={option.id}>{option.name}</option>
                          ))}
                        </select>
                      ) : (
                        <input type={field.type === 'number' ? 'number' : 'text'} value={form[field.key] || ''}
                          required={field.required} onChange={(event) => updateField(field.key, event.target.value)}
                          className="w-full text-xs border border-slate-300 rounded-lg px-3 py-2.5 focus:outline-none focus:ring-2 focus:ring-accent/40" />
                      )}
                    </label>
                  ))}
                </div>
              </div>

              <div className="px-5 py-4 border-t border-slate-200 bg-slate-50 flex justify-end gap-2">
                <button type="button" onClick={closeModal} disabled={isSubmitting}
                  className="text-xs font-semibold text-slate-600 border border-slate-300 bg-white px-4 py-2 rounded-lg hover:bg-slate-100 disabled:opacity-50 cursor-pointer">
                  Close
                </button>
                <button type="submit" disabled={isSubmitting || optionsLoading}
                  className="inline-flex items-center gap-1.5 bg-accent hover:bg-accent-dark text-white text-xs font-bold px-4 py-2 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer">
                  {isSubmitting ? <LoaderCircle className="w-3.5 h-3.5 animate-spin" /> : editingId ? <Pencil className="w-3.5 h-3.5" /> : <Plus className="w-3.5 h-3.5" />}
                  {isSubmitting ? 'Saving…' : editingId ? 'Update' : 'Submit'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
