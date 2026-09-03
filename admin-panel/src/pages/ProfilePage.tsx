import { Phone, MapPin, IdCard, ShieldCheck } from 'lucide-react';
import type { User } from '../types';

interface ProfilePageProps {
  currentUser: User;
}

function roleLabel(role: string) {
  return role.replace(/_/g, ' ');
}

function initials(name: string | null, username: string) {
  const source = (name || username).trim();
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  return (parts[0][0] + (parts[1]?.[0] ?? '')).toUpperCase();
}

function Section({ title, icon, children }: { title: string; icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <div>
      <p className="flex items-center gap-1.5 text-[10px] font-bold text-muted uppercase tracking-wide mb-2">
        {icon} {title}
      </p>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs bg-cream border border-line rounded-xl p-3">
        {children}
      </div>
    </div>
  );
}

function Field({ label, value, badge }: { label: string; value?: string | null; badge?: 'emerald' | 'slate' }) {
  return (
    <div>
      <p className="text-[10px] font-bold text-muted uppercase mb-0.5">{label}</p>
      {badge ? (
        <span className={`inline-block text-[10px] font-bold uppercase px-2 py-0.5 rounded-full border ${
          badge === 'emerald' ? 'bg-emerald-50 text-emerald-700 border-emerald-200' : 'bg-slate-100 text-slate-500 border-slate-200'
        }`}>
          {value || '—'}
        </span>
      ) : (
        <p className="text-ink font-medium">{value || '—'}</p>
      )}
    </div>
  );
}

export default function ProfilePage({ currentUser }: ProfilePageProps) {
  return (
    <div className="max-w-lg">
      <div className="bg-white border border-line rounded-2xl shadow-sm overflow-hidden">
        <div className="bg-gradient-to-br from-accent to-accent-dark px-5 pt-5 pb-6 text-white">
          <div className="flex items-center gap-3">
            <div className="w-14 h-14 rounded-full bg-white/15 border border-white/25 flex items-center justify-center font-bold text-base">
              {initials(currentUser.name, currentUser.username)}
            </div>
            <div className="min-w-0">
              <h2 className="font-bold text-base leading-tight truncate">{currentUser.name || currentUser.username}</h2>
              <p className="text-xs text-white/75">@{currentUser.username}</p>
            </div>
            <span className="ml-auto shrink-0 text-[10px] font-bold uppercase px-2.5 py-1 rounded-full bg-white/15 border border-white/25">
              {roleLabel(currentUser.role)}
            </span>
          </div>
        </div>

        <div className="p-5 space-y-4">
          <Section title="Contact" icon={<Phone className="w-3.5 h-3.5" />}>
            <Field label="Phone No." value={currentUser.mobile} />
            <Field label="Email" value={currentUser.email} />
          </Section>

          <Section title="Jurisdiction" icon={<MapPin className="w-3.5 h-3.5" />}>
            <Field label="Department" value={currentUser.department?.name} />
            <Field label="District" value={currentUser.district?.name} />
            <Field label="Block" value={currentUser.block?.name} />
            <Field label="Panchayat" value={currentUser.panchayat?.name} />
          </Section>

          <Section title="Identifiers" icon={<IdCard className="w-3.5 h-3.5" />}>
            <Field label="Employee ID" value={currentUser.employee_id} />
            <Field label="Member ID" value={currentUser.member_id} />
            <Field label="Family ID" value={currentUser.family_id} />
          </Section>

          <Section title="Account" icon={<ShieldCheck className="w-3.5 h-3.5" />}>
            <Field label="Status" value={currentUser.is_active ? 'Active' : 'Inactive'} badge={currentUser.is_active ? 'emerald' : 'slate'} />
            <Field label="Registration" value={currentUser.registration_status} />
            <Field label="Joined" value={new Date(currentUser.created_at).toLocaleDateString()} />
          </Section>
        </div>
      </div>
    </div>
  );
}
