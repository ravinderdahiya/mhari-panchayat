import type { ComplaintStatus } from '../types';

const STATUS_COLORS: Record<ComplaintStatus, string> = {
  Pending: 'bg-status-new/10 text-status-new border-status-new/25',
  Acknowledged: 'bg-status-accepted/10 text-status-accepted border-status-accepted/25',
  Surveyed: 'bg-status-progress/10 text-status-progress border-status-progress/25',
  In_Progress: 'bg-status-progress/10 text-status-progress border-status-progress/25',
  Resolved: 'bg-status-closed/10 text-status-closed border-status-closed/25',
  Rejected: 'bg-status-rejected/10 text-status-rejected border-status-rejected/25',
  Closed: 'bg-status-closed/10 text-status-closed border-status-closed/25',
  Reopened: 'bg-accent/10 text-accent-dark border-accent/25',
};

export function StatusBadge({ status }: { status: ComplaintStatus }) {
  return (
    <span className={`text-[10px] font-bold uppercase px-2.5 py-1 rounded-full border ${STATUS_COLORS[status]}`}>
      {status.replace('_', ' ')}
    </span>
  );
}

// Left-accent bar + timeline dot colors, keyed the same as STATUS_COLORS but
// as solid tailwind classes (not the softer badge tints) so they read at a
// glance in a 4px strip or an 8px dot.
const STATUS_ACCENTS: Record<ComplaintStatus, string> = {
  Pending: 'bg-status-new',
  Acknowledged: 'bg-status-accepted',
  Surveyed: 'bg-status-progress',
  In_Progress: 'bg-status-progress',
  Resolved: 'bg-status-closed',
  Rejected: 'bg-status-rejected',
  Closed: 'bg-status-closed',
  Reopened: 'bg-accent',
};

export function statusAccent(status: ComplaintStatus): string {
  return STATUS_ACCENTS[status] || 'bg-muted';
}

// Priority is admin-configurable master data (ComplaintPriority), not a
// fixed union, so this maps the common names but falls back gracefully for
// any custom priority an admin adds via Master Management.
const PRIORITY_COLORS: Record<string, string> = {
  Low: 'bg-line text-muted',
  Medium: 'bg-status-accepted/10 text-status-accepted',
  High: 'bg-status-progress/10 text-status-progress',
  Critical: 'bg-status-new/10 text-status-new',
};

export function PriorityBadge({ priority }: { priority: string }) {
  return (
    <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full ${PRIORITY_COLORS[priority] || 'bg-line text-muted'}`}>
      {priority}
    </span>
  );
}
