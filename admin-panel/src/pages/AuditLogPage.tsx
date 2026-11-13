import { useEffect, useState } from 'react';
import { CheckCircle2, ChevronLeft, ChevronRight, Inbox, RefreshCw, Search, XCircle } from 'lucide-react';
import * as api from '../services/api';
import type { LoginLog, LoginLogPage, LoginLogStatus } from '../types';
import { describeDevice } from './loginLogs';

function formatDate(value: string) {
  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', second: '2-digit',
  }).format(new Date(value));
}

const METHOD_LABEL: Record<LoginLog['method'], string> = { password: 'Password', otp: 'OTP' };

export default function AuditLogPage() {
  const [status, setStatus] = useState<LoginLogStatus | 'all'>('all');
  const [method, setMethod] = useState<'' | 'password' | 'otp'>('');
  const [searchInput, setSearchInput] = useState('');
  const [search, setSearch] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [page, setPage] = useState(1);
  const [reloadKey, setReloadKey] = useState(0);
  const [data, setData] = useState<LoginLogPage | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  // Debounce the search box so each keystroke doesn't hit the API.
  useEffect(() => {
    const id = setTimeout(() => { setSearch(searchInput.trim()); setPage(1); }, 350);
    return () => clearTimeout(id);
  }, [searchInput]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError('');
    api.getLoginLogs({
      status: status === 'all' ? undefined : status,
      method: method || undefined,
      search, from, to, page,
    })
      .then((res) => { if (!cancelled) setData(res); })
      .catch((reason: Error) => { if (!cancelled) setError(reason.message); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [status, method, search, from, to, page, reloadKey]);

  const summary = data?.summary ?? { success: 0, failed: 0 };
  const meta = data?.meta;
  const logs = data?.logs ?? [];

  const tab = (value: LoginLogStatus | 'all', label: string, count: number) => (
    <button
      key={value}
      type="button"
      onClick={() => { setStatus(value); setPage(1); }}
      className={`text-xs font-semibold rounded-full border px-3 py-1.5 cursor-pointer ${
        status === value ? 'bg-sidebar text-white border-sidebar' : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-50'
      }`}
    >
      {label} ({count})
    </button>
  );

  const inputCls = 'text-xs border border-slate-200 rounded-lg px-2.5 py-1.5 bg-white text-slate-700 focus:outline-none focus:ring-2 focus:ring-accent/30';

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-base font-bold text-slate-800">Login history</h2>
        <p className="text-xs text-slate-400">Every sign-in attempt to the admin panel and mobile app, newest first.</p>
      </div>

      {error && (
        <div role="alert" className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg px-3 py-2">{error}</div>
      )}

      <div className="flex flex-wrap items-center gap-2">
        {tab('all', 'All', summary.success + summary.failed)}
        {tab('success', 'Successful', summary.success)}
        {tab('failed', 'Failed', summary.failed)}

        <div className="flex flex-wrap items-center gap-2 ml-auto">
          <label className="relative">
            <Search className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 top-1/2 -translate-y-1/2" />
            <input
              type="search"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              placeholder="Name, username, mobile, IP"
              aria-label="Search login history"
              className={`${inputCls} pl-8 w-56`}
            />
          </label>
          <select aria-label="Login method" value={method} onChange={(e) => { setMethod(e.target.value as typeof method); setPage(1); }} className={inputCls}>
            <option value="">All methods</option>
            <option value="password">Password (staff)</option>
            <option value="otp">OTP (citizen)</option>
          </select>
          <input type="date" aria-label="From date" value={from} max={to || undefined} onChange={(e) => { setFrom(e.target.value); setPage(1); }} className={inputCls} />
          <input type="date" aria-label="To date" value={to} min={from || undefined} onChange={(e) => { setTo(e.target.value); setPage(1); }} className={inputCls} />
          <button
            type="button"
            onClick={() => setReloadKey((k) => k + 1)}
            className="inline-flex items-center gap-1 text-xs font-semibold text-slate-600 border border-slate-200 rounded-lg px-2.5 py-1.5 bg-white hover:bg-slate-50 cursor-pointer"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} /> Refresh
          </button>
        </div>
      </div>

      <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden">
        {loading && !data ? (
          <p className="text-sm text-slate-400 p-6 text-center">Loading login history...</p>
        ) : logs.length === 0 ? (
          <div className="p-10 text-center">
            <Inbox className="w-6 h-6 text-slate-300 mx-auto mb-2" />
            <p className="text-sm text-slate-400">No sign-ins match these filters.</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 text-[11px] uppercase tracking-wide text-slate-500">
                <tr>
                  <th className="text-left font-semibold px-4 py-2.5">Time</th>
                  <th className="text-left font-semibold px-4 py-2.5">User</th>
                  <th className="text-left font-semibold px-4 py-2.5">Role</th>
                  <th className="text-left font-semibold px-4 py-2.5">Method</th>
                  <th className="text-left font-semibold px-4 py-2.5">Result</th>
                  <th className="text-left font-semibold px-4 py-2.5">IP address</th>
                  <th className="text-left font-semibold px-4 py-2.5">Device</th>
                </tr>
              </thead>
              <tbody className={`divide-y divide-slate-100 ${loading ? 'opacity-60' : ''}`}>
                {logs.map((log) => (
                  <tr key={log.id} className="align-top">
                    <td className="px-4 py-2.5 whitespace-nowrap text-slate-600 tabular-nums">{formatDate(log.createdAt)}</td>
                    <td className="px-4 py-2.5">
                      <p className="font-semibold text-slate-800">{log.userName || <span className="text-slate-400 font-normal">Unknown account</span>}</p>
                      {log.identifier && <p className="text-[11px] text-slate-400">{log.identifier}</p>}
                    </td>
                    <td className="px-4 py-2.5 text-slate-600 capitalize whitespace-nowrap">{log.role ? log.role.replaceAll('_', ' ') : '—'}</td>
                    <td className="px-4 py-2.5 text-slate-600">{METHOD_LABEL[log.method] ?? log.method}</td>
                    <td className="px-4 py-2.5">
                      {log.status === 'success' ? (
                        <span className="inline-flex items-center gap-1 text-[11px] font-bold text-emerald-700 bg-emerald-50 border border-emerald-200 rounded-full px-2 py-0.5">
                          <CheckCircle2 className="w-3 h-3" /> Success
                        </span>
                      ) : (
                        <div>
                          <span className="inline-flex items-center gap-1 text-[11px] font-bold text-red-700 bg-red-50 border border-red-200 rounded-full px-2 py-0.5">
                            <XCircle className="w-3 h-3" /> Failed
                          </span>
                          {log.reason && <p className="text-[11px] text-slate-500 mt-1">{log.reason}</p>}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-2.5 text-slate-600 tabular-nums whitespace-nowrap">{log.ipAddress || '—'}</td>
                    <td className="px-4 py-2.5 text-slate-600 whitespace-nowrap" title={log.userAgent ?? undefined}>{describeDevice(log.userAgent)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {meta && meta.lastPage > 1 && (
          <div className="flex items-center justify-between border-t border-slate-100 px-4 py-2.5 text-xs text-slate-500">
            <span>Page {meta.page} of {meta.lastPage} · {meta.total} entries</span>
            <div className="flex gap-1">
              <button type="button" aria-label="Previous page" disabled={meta.page <= 1 || loading} onClick={() => setPage((p) => p - 1)}
                className="p-1.5 rounded-lg border border-slate-200 disabled:opacity-40 hover:bg-slate-50 cursor-pointer disabled:cursor-default">
                <ChevronLeft className="w-3.5 h-3.5" />
              </button>
              <button type="button" aria-label="Next page" disabled={meta.page >= meta.lastPage || loading} onClick={() => setPage((p) => p + 1)}
                className="p-1.5 rounded-lg border border-slate-200 disabled:opacity-40 hover:bg-slate-50 cursor-pointer disabled:cursor-default">
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
