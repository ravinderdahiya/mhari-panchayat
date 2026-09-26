import { useState } from 'react';
import { Phone, Mail, MapPin, IdCard, ShieldCheck, Pencil, X } from 'lucide-react';
import * as api from '../services/api';
import type { User } from '../types';

interface ProfilePageProps {
  currentUser: User;
  onProfileUpdated: (user: User) => void;
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

function EditField({ label, value, onChange, icon, placeholder }: {
  label: string; value: string; onChange: (value: string) => void; icon?: React.ReactNode; placeholder?: string;
}) {
  return (
    <div>
      <label className="text-[10px] font-bold text-muted uppercase block mb-0.5">{label}</label>
      <div className="relative">
        {icon && <span className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted">{icon}</span>}
        <input
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          className={`w-full text-xs border border-line rounded-lg py-1.5 bg-white focus:outline-none focus:ring-2 focus:ring-accent ${icon ? 'pl-8 pr-2.5' : 'px-2.5'}`}
        />
      </div>
    </div>
  );
}

export default function ProfilePage({ currentUser, onProfileUpdated }: ProfilePageProps) {
  const [isEditing, setIsEditing] = useState(false);
  const [name, setName] = useState(currentUser.name ?? '');
  const [mobile, setMobile] = useState(currentUser.mobile ?? '');
  const [email, setEmail] = useState(currentUser.email ?? '');
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState('');

  const startEditing = () => {
    setName(currentUser.name ?? '');
    setMobile(currentUser.mobile ?? '');
    setEmail(currentUser.email ?? '');
    setError('');
    setIsEditing(true);
  };

  const cancelEditing = () => {
    setIsEditing(false);
    setError('');
  };

  const save = async () => {
    setIsSaving(true);
    setError('');
    try {
      const { user } = await api.updateProfile({
        name: name.trim() || null,
        mobile: mobile.trim() || null,
        email: email.trim() || null,
      });
      onProfileUpdated(user);
      setIsEditing(false);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="max-w-lg">
      <div className="bg-white border border-line rounded-2xl shadow-sm overflow-hidden">
        <div className="bg-gradient-to-br from-accent to-accent-dark px-5 pt-5 pb-6 text-white">
          <div className="flex items-center gap-3">
            <div className="w-14 h-14 rounded-full bg-white/15 border border-white/25 flex items-center justify-center font-bold text-base shrink-0">
              {initials(currentUser.name, currentUser.username)}
            </div>
            <div className="min-w-0 flex-1">
              {isEditing ? (
                <input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="Full name"
                  className="w-full text-sm font-bold bg-white/15 border border-white/25 rounded-lg px-2 py-1 text-white placeholder-white/50 focus:outline-none focus:ring-2 focus:ring-white/40"
                />
              ) : (
                <h2 className="font-bold text-base leading-tight truncate">{currentUser.name || currentUser.username}</h2>
              )}
              <p className="text-xs text-white/75 mt-0.5">@{currentUser.username}</p>
            </div>
            <span className="ml-auto shrink-0 text-[10px] font-bold uppercase px-2.5 py-1 rounded-full bg-white/15 border border-white/25">
              {roleLabel(currentUser.role)}
            </span>
            {!isEditing && (
              <button
                type="button"
                onClick={startEditing}
                title="Edit profile"
                className="shrink-0 w-7 h-7 rounded-full bg-white/15 border border-white/25 flex items-center justify-center hover:bg-white/25"
              >
                <Pencil className="w-3.5 h-3.5" />
              </button>
            )}
          </div>
        </div>

        <div className="p-5 space-y-4">
          {error && <p className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg p-2">{error}</p>}

          {isEditing ? (
            <div>
              <p className="flex items-center gap-1.5 text-[10px] font-bold text-muted uppercase tracking-wide mb-2">
                <Phone className="w-3.5 h-3.5" /> Contact
              </p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 bg-cream border border-line rounded-xl p-3">
                <EditField label="Phone No." value={mobile} onChange={setMobile} icon={<Phone className="w-3.5 h-3.5" />} placeholder="Phone number" />
                <EditField label="Email" value={email} onChange={setEmail} icon={<Mail className="w-3.5 h-3.5" />} placeholder="Email address" />
              </div>
            </div>
          ) : (
            <Section title="Contact" icon={<Phone className="w-3.5 h-3.5" />}>
              <Field label="Phone No." value={currentUser.mobile} />
              <Field label="Email" value={currentUser.email} />
            </Section>
          )}

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

          {isEditing && (
            <div className="flex items-center gap-2 pt-1">
              <button
                type="button"
                disabled={isSaving}
                onClick={save}
                className="bg-accent hover:bg-accent-dark disabled:opacity-50 text-white text-xs font-bold px-4 py-2 rounded-lg"
              >
                {isSaving ? 'Saving…' : 'Save Changes'}
              </button>
              <button
                type="button"
                onClick={cancelEditing}
                disabled={isSaving}
                className="flex items-center gap-1 text-xs font-bold px-4 py-2 rounded-lg border border-line text-muted hover:bg-cream"
              >
                <X className="w-3.5 h-3.5" /> Cancel
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
