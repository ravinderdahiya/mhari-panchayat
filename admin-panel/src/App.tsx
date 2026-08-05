import { useEffect, useState } from 'react';
import * as api from './services/api';
import type { ComplaintStatus, User } from './types';
import LoginPage from './pages/LoginPage';
import RegisterPage from './pages/RegisterPage';
import ForgotPasswordPage from './pages/ForgotPasswordPage';
import DashboardPage from './pages/DashboardPage';
import MasterDataPage from './pages/MasterDataPage';
import ComplaintsPage from './pages/ComplaintsPage';
import MySurveysPage from './pages/MySurveysPage';
import SurveyorsPage from './pages/SurveyorsPage';
import RolesPage from './pages/RolesPage';
import UsersPage from './pages/UsersPage';
import CitizensPage from './pages/CitizensPage';
import VillageAssetsPage from './pages/VillageAssetsPage';
import AssetTypesPage from './pages/AssetTypesPage';
import AssetSurveysPage from './pages/AssetSurveysPage';
import ProjectMeetingPage from './pages/ProjectMeetingPage';
import ComingSoon from './components/ComingSoon';
import Layout from './components/Layout';
import type { View } from './components/Layout';

type PreAuthView = 'login' | 'register' | 'forgot';

const PLACEHOLDER_TITLES: Partial<Record<View, string>> = {
  reports: 'Reports',
  settings: 'Settings',
  'audit-log': 'Audit Log',
};

export default function App() {
  const [currentUser, setCurrentUser] = useState<User | null>(null);
  const [isBootstrapping, setIsBootstrapping] = useState(!!api.getToken());
  const [activeView, setActiveView] = useState<View>('dashboard');
  const [masterEntityKey, setMasterEntityKey] = useState('states');
  const [preAuthView, setPreAuthView] = useState<PreAuthView>('login');
  const [complaintsFilter, setComplaintsFilter] = useState<ComplaintStatus | 'All' | null>(null);
  const [complaintsInitialId, setComplaintsInitialId] = useState<number | null>(null);

  const handleNavigate = (view: View, childId?: string) => {
    if (view !== 'complaints') {
      setComplaintsFilter(null);
      setComplaintsInitialId(null);
    }
    if (view === 'master' && childId) {
      setMasterEntityKey(childId);
    }
    setActiveView(view);
  };

  const goToComplaints = (status: ComplaintStatus | 'All') => {
    setComplaintsFilter(status);
    setComplaintsInitialId(null);
    setActiveView('complaints');
  };

  const goToComplaint = (id: number) => {
    setComplaintsFilter('All');
    setComplaintsInitialId(id);
    setActiveView('complaints');
  };

  useEffect(() => {
    if (!api.getToken()) return;
    api.getMe()
      .then(({ user }) => setCurrentUser(user))
      .catch(() => api.clearToken())
      .finally(() => setIsBootstrapping(false));
  }, []);

  const handleLogout = () => {
    api.clearToken();
    setCurrentUser(null);
    setActiveView('dashboard');
    setPreAuthView('login');
  };

  if (isBootstrapping) {
    return <div className="min-h-screen flex items-center justify-center bg-cream text-sidebar font-serif font-medium text-sm">Restoring session…</div>;
  }

  if (!currentUser) {
    if (preAuthView === 'register') {
      return <RegisterPage onRegisterSuccess={setCurrentUser} onNavigateLogin={() => setPreAuthView('login')} />;
    }
    if (preAuthView === 'forgot') {
      return <ForgotPasswordPage onDone={() => setPreAuthView('login')} onNavigateLogin={() => setPreAuthView('login')} />;
    }
    return (
      <LoginPage
        onLoginSuccess={setCurrentUser}
        onNavigateRegister={() => setPreAuthView('register')}
        onNavigateForgotPassword={() => setPreAuthView('forgot')}
      />
    );
  }

  return (
    <Layout currentUser={currentUser} activeView={activeView}
      activeChildId={activeView === 'master' ? masterEntityKey : null}
      onNavigate={handleNavigate} onLogout={handleLogout}>
      {activeView === 'dashboard' && <DashboardPage onNavigateToComplaints={goToComplaints} onNavigateToComplaint={goToComplaint} />}
      {activeView === 'master' && <MasterDataPage initialEntityKey={masterEntityKey} />}
      {activeView === 'complaints' && <ComplaintsPage currentUser={currentUser} initialStatus={complaintsFilter} initialComplaintId={complaintsInitialId} />}
      {activeView === 'my-surveys' && <MySurveysPage currentUser={currentUser} onNavigateToComplaint={goToComplaint} />}
      {activeView === 'surveyors' && <SurveyorsPage onNavigateToComplaint={goToComplaint} />}
      {activeView === 'asset-surveys' && <AssetSurveysPage />}
      {activeView === 'asset-types' && <AssetTypesPage />}
      {activeView === 'village-assets' && <VillageAssetsPage />}
      {activeView === 'roles' && <RolesPage />}
      {activeView === 'users' && <UsersPage currentUser={currentUser} />}
      {activeView === 'citizens' && <CitizensPage />}
      {activeView === 'project-meeting' && <ProjectMeetingPage />}
      {PLACEHOLDER_TITLES[activeView] && <ComingSoon title={PLACEHOLDER_TITLES[activeView]!} />}
    </Layout>
  );
}
