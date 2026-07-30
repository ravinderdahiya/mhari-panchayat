import { useState } from 'react';
import {
  LayoutDashboard, Database, FileBarChart, MessageSquareWarning,
  Users, ShieldCheck, Settings, ScrollText, Landmark, LogOut, MapPinned,
  ChevronRight, ClipboardCheck, HardHat,
} from 'lucide-react';
import type { User } from '../types';

export type View =
  | 'dashboard' | 'master' | 'reports' | 'complaints' | 'my-surveys' | 'village-assets'
  | 'surveyors' | 'users' | 'roles' | 'settings' | 'audit-log';

interface LayoutProps {
  currentUser: User;
  activeView: View;
  onNavigate: (view: View) => void;
  onLogout: () => void;
  children: React.ReactNode;
}

const ADMIN_ROLES = ['super_admin'];

const NAV_ITEMS: {
  id: View; label: string; icon: typeof LayoutDashboard; adminOnly?: boolean; roles?: string[]; section?: 'operations' | 'system';
}[] = [
  { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { id: 'master', label: 'Master Management', icon: Database, adminOnly: true },
  { id: 'reports', label: 'Reports', icon: FileBarChart },
  { id: 'complaints', label: 'Complaints', icon: MessageSquareWarning, section: 'operations' },
  { id: 'my-surveys', label: 'My Surveys', icon: ClipboardCheck, roles: ['engineer'], section: 'operations' },
  { id: 'village-assets', label: 'Village Assets', icon: MapPinned, section: 'operations' },
  { id: 'surveyors', label: 'Surveyors', icon: HardHat, adminOnly: true, section: 'operations' },
  { id: 'users', label: 'Users', icon: Users, adminOnly: true, section: 'operations' },
  { id: 'roles', label: 'Roles', icon: ShieldCheck, adminOnly: true, section: 'operations' },
  { id: 'settings', label: 'Settings', icon: Settings, adminOnly: true, section: 'system' },
  { id: 'audit-log', label: 'Audit Log', icon: ScrollText, adminOnly: true, section: 'system' },
];

const PAGE_SUBTITLES: Record<View, string> = {
  dashboard: 'Grievance overview across all panchayats',
  master: 'Manage master data used across the system',
  reports: 'Generate and view system reports',
  complaints: 'Track and resolve citizen grievances',
  'my-surveys': 'Your assigned field surveys',
  'village-assets': 'GIS infrastructure tracking',
  surveyors: 'Assign villages, track visits, and verify submitted reports',
  users: 'Manage admin users and access',
  roles: 'Configure role-based permissions',
  settings: 'System configuration',
  'audit-log': 'System activity history',
};

function initials(name: string) {
  return name.split(' ').filter(Boolean).slice(0, 2).map((n) => n[0]!.toUpperCase()).join('');
}

export default function Layout({ currentUser, activeView, onNavigate, onLogout, children }: LayoutProps) {
  const [expanded, setExpanded] = useState(true);
  const visibleNavItems = NAV_ITEMS.filter((item) =>
    (!item.adminOnly || ADMIN_ROLES.includes(currentUser.role)) &&
    (!item.roles || item.roles.includes(currentUser.role)));
  const activeLabel = NAV_ITEMS.find((item) => item.id === activeView)?.label ?? '';
  const displayName = currentUser.name || currentUser.username;

  let lastSection: string | undefined;

  return (
    <div className="h-screen flex bg-cream overflow-hidden font-sans text-ink">
      <aside
        className={`relative shrink-0 bg-sidebar flex flex-col py-4 transition-[width] duration-200 ease-in-out ${
          expanded ? 'w-56' : 'w-[68px]'
        }`}
      >
        <button
          onClick={() => setExpanded((v) => !v)}
          className="absolute top-5 -right-2.5 w-5 h-5 rounded-full bg-accent border-2 border-cream flex items-center justify-center z-10 cursor-pointer"
          aria-label={expanded ? 'Collapse sidebar' : 'Expand sidebar'}
        >
          <ChevronRight className={`w-2.5 h-2.5 text-sidebar transition-transform duration-200 ${expanded ? 'rotate-180' : ''}`} />
        </button>

        <div className="flex items-center gap-3 px-4 pb-4 mb-2 border-b border-white/10 overflow-hidden whitespace-nowrap">
          <div className="w-8 h-8 shrink-0 rounded border border-accent flex items-center justify-center font-serif text-accent text-base">
            <Landmark className="w-4 h-4" />
          </div>
          <span className={`font-serif font-semibold text-white text-[14.5px] transition-opacity duration-150 ${expanded ? 'opacity-100' : 'opacity-0'}`}>
            Mhari Panchayat
          </span>
        </div>

        <nav className="flex-1 overflow-y-auto overflow-x-hidden px-2.5">
          {visibleNavItems.map((item) => {
            const Icon = item.icon;
            const isActive = activeView === item.id;
            const showDivider = !!item.section && item.section !== lastSection;
            lastSection = item.section;
            return (
              <div key={item.id}>
                {showDivider && (
                  <>
                    <div className="h-px bg-white/10 my-2.5 mx-1" />
                    {expanded && (
                      <div className="text-[10px] tracking-wider uppercase text-white/40 px-3 pb-1.5 whitespace-nowrap">
                        {item.section}
                      </div>
                    )}
                  </>
                )}
                <button
                  onClick={() => onNavigate(item.id)}
                  className={`group relative w-full flex items-center gap-3.5 px-3 py-2.5 rounded-md mb-0.5 text-[13.5px] border-l-[3px] transition-colors whitespace-nowrap cursor-pointer ${
                    isActive
                      ? 'bg-sidebar-active text-white border-accent'
                      : 'text-white/70 hover:bg-sidebar-hover hover:text-white border-transparent'
                  }`}
                >
                  <Icon className="w-[19px] h-[19px] shrink-0" />
                  <span className={`transition-opacity duration-150 ${expanded ? 'opacity-100' : 'opacity-0 w-0 overflow-hidden'}`}>
                    {item.label}
                  </span>
                  {!expanded && (
                    <span className="pointer-events-none absolute left-[60px] top-1/2 -translate-y-1/2 whitespace-nowrap bg-sidebar text-white text-xs px-2.5 py-1.5 rounded shadow-lg opacity-0 group-hover:opacity-100 transition-opacity duration-150 z-50">
                      {item.label}
                    </span>
                  )}
                </button>
              </div>
            );
          })}
        </nav>

        <div className="shrink-0 border-t border-white/10 pt-3.5 px-2.5">
          <div className="flex items-center gap-3 px-2.5 pb-2.5 overflow-hidden whitespace-nowrap">
            <div className="w-8 h-8 shrink-0 rounded-full bg-accent-soft text-sidebar font-serif font-semibold text-[13px] flex items-center justify-center">
              {initials(displayName)}
            </div>
            <div className={`transition-opacity duration-150 ${expanded ? 'opacity-100' : 'opacity-0'}`}>
              <p className="text-[13px] text-white font-medium leading-tight">{displayName}</p>
              <p className="text-[10px] tracking-wide uppercase text-accent leading-tight">{currentUser.role.replace('_', ' ')}</p>
            </div>
          </div>
          <button
            onClick={onLogout}
            className="w-full flex items-center justify-center gap-1.5 text-[11px] font-semibold text-white/80 hover:text-white bg-black/15 hover:bg-black/25 border border-white/10 px-3 py-2 rounded-md mb-1 cursor-pointer"
          >
            <LogOut className="w-3.5 h-3.5" />
            {expanded && 'Logout'}
          </button>
        </div>
      </aside>

      <div className="flex-1 flex flex-col overflow-hidden">
        <header className="shrink-0 bg-paper/90 backdrop-blur border-b border-line px-6 py-3.5 flex items-center justify-between">
          <div>
            <h1 className="font-serif font-medium text-[19px] text-ink leading-tight">
              {activeView === 'dashboard' ? `Welcome, ${displayName}` : activeLabel}
            </h1>
            <p className="text-[12.5px] text-muted mt-0.5">{PAGE_SUBTITLES[activeView]}</p>
          </div>
          <div className="font-mono text-[10.5px] text-muted border border-line bg-paper px-2.5 py-1.5 rounded">
            {currentUser.role.replace('_', ' ').toUpperCase()}
          </div>
        </header>
        <main className="flex-1 p-6 overflow-y-auto overflow-x-auto">{children}</main>
      </div>
    </div>
  );
}
