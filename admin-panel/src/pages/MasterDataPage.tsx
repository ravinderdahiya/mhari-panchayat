import { useEffect, useState } from 'react';
import {
  Landmark, MapPin, LayoutGrid, Building2, Home, Briefcase, IdCard,
  Tags, SignalHigh, ShieldCheck, ListChecks, Pencil, Trash2, Inbox, Plus, X,
} from 'lucide-react';
import { masterApi } from '../services/api';

interface FieldConfig {
  key: string;
  label: string;
  type: 'text' | 'number' | 'select';
  optionsFrom?: string; // another entity's key, for FK dropdowns
}

interface EntityConfig {
  key: string;   // maps to /api/master/<key>
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
      { key: 'name', label: 'Name', type: 'text' },
      { key: 'code', label: 'Code', type: 'text' },
    ]},
    { key: 'districts', label: 'Districts', icon: MapPin, fields: [
      { key: 'name', label: 'Name', type: 'text' },
      { key: 'code', label: 'Code', type: 'text' },
      { key: 'state_id', label: 'State', type: 'select', optionsFrom: 'states' },
    ]},
    { key: 'blocks', label: 'Blocks', icon: LayoutGrid, fields: [
      { key: 'name', label: 'Name', type: 'text' },
      { key: 'code', label: 'Code', type: 'text' },
      { key: 'district_id', label: 'District', type: 'select', optionsFrom: 'districts' },
    ]},
    { key: 'panchayats', label: 'Panchayats', icon: Building2, fields: [
      { key: 'name', label: 'Name', type: 'text' },
      { key: 'code', label: 'Code', type: 'text' },
      { key: 'block_id', label: 'Block', type: 'select', optionsFrom: 'blocks' },
    ]},
    { key: 'villages', label: 'Villages', icon: Home, fields: [
      { key: 'name', label: 'Name', type: 'text' },
      { key: 'code', label: 'Code', type: 'text' },
      { key: 'panchayat_id', label: 'Panchayat', type: 'select', optionsFrom: 'panchayats' },
    ]},
  ]},
  { label: 'Organization', entities: [
    { key: 'departments', label: 'Departments', icon: Briefcase, fields: [
      { key: 'name', label: 'Name', type: 'text' },
      { key: 'code', label: 'Code', type: 'text' },
    ]},
    { key: 'designations', label: 'Designations', icon: IdCard, fields: [
      { key: 'name', label: 'Name', type: 'text' },
    ]},
  ]},
  { label: 'Complaint Setup', entities: [
    { key: 'complaint-categories', label: 'Complaint Categories', icon: Tags, fields: [
      { key: 'name', label: 'Name', type: 'text' },
      { key: 'code', label: 'Code', type: 'text' },
      { key: 'sort_order', label: 'Sort Order', type: 'number' },
      { key: 'parent_id', label: 'Parent Category', type: 'select', optionsFrom: 'complaint-categories' },
      { key: 'district_id', label: 'District', type: 'select', optionsFrom: 'districts' },
    ]},
    { key: 'complaint-priorities', label: 'Complaint Priorities', icon: SignalHigh, fields: [
      { key: 'name', label: 'Name', type: 'text' },
      { key: 'level', label: 'Sort Level', type: 'number' },
    ]},
  ]},
  { label: 'Reference (read-only)', entities: [
    { key: 'roles', label: 'Roles', icon: ShieldCheck, readOnly: true, fields: [
      { key: 'name', label: 'Name', type: 'text' },
    ]},
    { key: 'complaint-statuses', label: 'Complaint Statuses', icon: ListChecks, readOnly: true, fields: [
      { key: 'name', label: 'Name', type: 'text' },
    ]},
  ]},
];

const ENTITIES: EntityConfig[] = GROUPS.flatMap((g) => g.entities);

export default function MasterDataPage() {
  const [activeKey, setActiveKey] = useState(ENTITIES[0].key);
  const active = ENTITIES.find((e) => e.key === activeKey)!;

  const [items, setItems] = useState<any[]>([]);
  const [optionSets, setOptionSets] = useState<Record<string, any[]>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');
  const [form, setForm] = useState<Record<string, string>>({});
  const [editingId, setEditingId] = useState<number | null>(null);

  const load = async (entity: EntityConfig) => {
    setIsLoading(true);
    setError('');
    try {
      const { items } = await masterApi(entity.key).list();
      setItems(items);

      const parentKeys = entity.fields.filter((f) => f.optionsFrom).map((f) => f.optionsFrom!);
      const uncached = parentKeys.filter((k) => !optionSets[k]);
      if (uncached.length > 0) {
        const fetched = await Promise.all(uncached.map((k) => masterApi(k).list()));
        setOptionSets((prev) => {
          const next = { ...prev };
          uncached.forEach((k, i) => { next[k] = fetched[i].items; });
          return next;
        });
      }
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    setForm({});
    setEditingId(null);
    load(active);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeKey]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    try {
      const data: Record<string, any> = { ...form };
      const numberFields = active.fields.filter((f) => f.type === 'number' || f.type === 'select');
      numberFields.forEach((f) => {
        if (data[f.key] !== undefined && data[f.key] !== '') data[f.key] = Number(data[f.key]);
      });

      if (editingId) {
        await masterApi(active.key).update(editingId, data);
      } else {
        await masterApi(active.key).create(data);
      }
      setForm({});
      setEditingId(null);
      load(active);
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const startEdit = (item: any) => {
    setEditingId(item.id);
    const next: Record<string, string> = {};
    active.fields.forEach((f) => { next[f.key] = item[f.key] ?? ''; });
    setForm(next);
  };

  const remove = async (id: number) => {
    if (!confirm('Delete this entry?')) return;
    setError('');
    try {
      await masterApi(active.key).remove(id);
      load(active);
    } catch (err) {
      setError((err as Error).message);
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
    <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
      <div className="lg:col-span-3 space-y-4">
        {GROUPS.map((group) => (
          <div key={group.label}>
            <p className="text-[10px] font-bold text-slate-400 uppercase tracking-wide px-3 mb-1.5">{group.label}</p>
            <div className="space-y-1">
              {group.entities.map((e) => {
                const Icon = e.icon;
                const isActive = activeKey === e.key;
                return (
                  <button
                    key={e.key}
                    onClick={() => setActiveKey(e.key)}
                    className={`w-full flex items-center gap-2.5 text-left text-xs font-bold px-3 py-2 rounded-lg transition-colors ${
                      isActive ? 'bg-accent text-white shadow-sm' : 'bg-white text-slate-600 border border-slate-200 hover:border-slate-300'
                    }`}
                  >
                    <Icon className={`w-3.5 h-3.5 shrink-0 ${isActive ? 'text-white' : 'text-slate-400'}`} />
                    {e.label}
                  </button>
                );
              })}
            </div>
          </div>
        ))}
      </div>

      <div className="lg:col-span-9 space-y-4">
        <div className="flex items-center gap-2">
          <active.icon className="w-4 h-4 text-accent-dark" />
          <h2 className="text-sm font-bold text-slate-800">{active.label}</h2>
          <span className="text-xs text-slate-400 tabular-nums">({items.length})</span>
        </div>

        {error && <p className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg p-2">{error}</p>}

        {!active.readOnly && (
          <form onSubmit={submit} className="bg-white border border-slate-200 rounded-2xl p-4">
            <div className="flex flex-wrap items-end gap-3">
              {active.fields.map((f) => (
                <div key={f.key}>
                  <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">{f.label}</label>
                  {f.type === 'select' ? (
                    <select
                      value={form[f.key] || ''}
                      onChange={(e) => setForm((prev) => ({ ...prev, [f.key]: e.target.value }))}
                      className="text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 min-w-[150px] focus:outline-none focus:ring-2 focus:ring-accent"
                    >
                      <option value="">— select —</option>
                      {(optionSets[f.optionsFrom!] || []).map((opt) => (
                        <option key={opt.id} value={opt.id}>{opt.name}</option>
                      ))}
                    </select>
                  ) : (
                    <input
                      type={f.type === 'number' ? 'number' : 'text'}
                      value={form[f.key] || ''}
                      onChange={(e) => setForm((prev) => ({ ...prev, [f.key]: e.target.value }))}
                      className="text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-accent"
                    />
                  )}
                </div>
              ))}
              <button type="submit" className="flex items-center gap-1.5 bg-accent hover:bg-accent-dark text-white text-xs font-bold px-3.5 py-1.5 rounded-lg">
                {editingId ? <Pencil className="w-3.5 h-3.5" /> : <Plus className="w-3.5 h-3.5" />}
                {editingId ? 'Update' : 'Add'}
              </button>
              {editingId && (
                <button
                  type="button"
                  onClick={() => { setEditingId(null); setForm({}); }}
                  className="flex items-center gap-1 text-xs font-semibold text-slate-500 hover:text-slate-700 px-2 py-1.5"
                >
                  <X className="w-3.5 h-3.5" />
                  Cancel
                </button>
              )}
            </div>
          </form>
        )}

        <div className="bg-white border border-slate-200 rounded-2xl overflow-x-auto">
          {isLoading ? (
            <p className="text-sm text-slate-400 p-6">Loading…</p>
          ) : items.length === 0 ? (
            <div className="p-10 text-center">
              <Inbox className="w-6 h-6 text-slate-300 mx-auto mb-2" />
              <p className="text-sm text-slate-400">No entries yet.</p>
            </div>
          ) : (
            <table className="w-full text-xs">
              <thead>
                <tr className="bg-slate-50 text-slate-500 uppercase text-[10px]">
                  {active.fields.map((f) => <th key={f.key} className="text-left p-2.5">{f.label}</th>)}
                  {!active.readOnly && <th className="p-2.5 w-24"></th>}
                </tr>
              </thead>
              <tbody>
                {items.map((item) => (
                  <tr key={item.id ?? item.name} className="border-t border-slate-100 hover:bg-slate-50/60">
                    {active.fields.map((f) => <td key={f.key} className="p-2.5 text-slate-700">{displayValue(item, f)}</td>)}
                    {!active.readOnly && (
                      <td className="p-2.5">
                        <div className="flex gap-1">
                          <button
                            onClick={() => startEdit(item)}
                            title="Edit"
                            className="p-1.5 rounded-lg text-blue-600 hover:bg-blue-50"
                          >
                            <Pencil className="w-3.5 h-3.5" />
                          </button>
                          <button
                            onClick={() => remove(item.id)}
                            title="Delete"
                            className="p-1.5 rounded-lg text-red-600 hover:bg-red-50"
                          >
                            <Trash2 className="w-3.5 h-3.5" />
                          </button>
                        </div>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
}
