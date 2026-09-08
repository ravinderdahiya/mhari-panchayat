import { MapPin, Calendar, User, UserCheck, Layers, Copy } from 'lucide-react';
import type { Complaint } from '../types';
import { StatusBadge, PriorityBadge } from './StatusBadge';

const formatDate = (value: string) =>
  new Date(value).toLocaleString(undefined, { day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit' });

// The map popup's own answer to "view details" - it can't show everything
// the full complaint page does (no timeline, no actions), so it picks the
// fields a field team scans a marker for first: what/where/who/when, plus a
// thumbnail if a citizen photo exists.
export default function ComplaintPopupCard({ complaint }: { complaint: Complaint }) {
  const location = [complaint.village, complaint.panchayat].filter(Boolean).join(', ');
  const region = [complaint.tehsil?.name, complaint.district?.name].filter(Boolean).join(', ');
  const thumbnail = complaint.issue_photo_urls?.[0] ?? complaint.before_photo_url ?? null;
  const reporter = complaint.user?.name || complaint.user?.username;
  const assignee = complaint.assigned_to?.name || complaint.assigned_to?.username;

  return (
    <div className="w-72 -mx-1">
      <div className="flex items-center justify-between gap-2 mb-2.5">
        <StatusBadge status={complaint.status} />
        <PriorityBadge priority={complaint.priority?.name ?? 'Medium'} />
      </div>

      <div className="flex items-start gap-2 mb-2">
        <Layers className="w-3.5 h-3.5 text-muted shrink-0 mt-0.5" />
        <div className="text-[13px] font-semibold text-ink leading-snug">
          {complaint.category?.name ?? 'Uncategorised'}
          {complaint.department?.name && <span className="text-muted font-normal"> · {complaint.department.name}</span>}
        </div>
      </div>

      {(location || region) && (
        <div className="flex items-start gap-2 mb-2">
          <MapPin className="w-3.5 h-3.5 text-muted shrink-0 mt-0.5" />
          <div className="text-xs text-muted leading-snug">
            {location && <div className="text-ink/80">{location}</div>}
            {region && <div>{region}</div>}
          </div>
        </div>
      )}

      <p className="text-xs text-ink/80 leading-relaxed mb-2.5 line-clamp-3">
        {complaint.description || <span className="italic text-muted">No description provided.</span>}
      </p>

      {thumbnail && (
        <img
          src={thumbnail}
          alt="Complaint"
          className="w-full h-28 object-cover rounded-lg border border-line mb-2.5"
          onError={(e) => { e.currentTarget.style.display = 'none'; }}
        />
      )}

      {complaint.duplicate_of && (
        <div className="flex items-center gap-1.5 text-[11px] text-accent-dark bg-accent-soft/50 rounded-md px-2 py-1 mb-2.5">
          <Copy className="w-3 h-3 shrink-0" />
          Duplicate of {complaint.duplicate_of.code ?? `#${complaint.duplicate_of.id}`}
        </div>
      )}

      <div className="space-y-1 pt-2 border-t border-line text-[11px] text-muted">
        {reporter && (
          <div className="flex items-center gap-1.5">
            <User className="w-3 h-3 shrink-0" />
            Reported by <span className="text-ink/80 font-medium">{reporter}</span>
          </div>
        )}
        {assignee && (
          <div className="flex items-center gap-1.5">
            <UserCheck className="w-3 h-3 shrink-0" />
            Assigned to <span className="text-ink/80 font-medium">{assignee}</span>
          </div>
        )}
        <div className="flex items-center gap-1.5">
          <Calendar className="w-3 h-3 shrink-0" />
          {formatDate(complaint.created_at)}
        </div>
      </div>
    </div>
  );
}
