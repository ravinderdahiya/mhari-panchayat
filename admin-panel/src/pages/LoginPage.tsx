import { useState } from 'react';
import { Landmark, Eye, EyeOff, LogIn } from 'lucide-react';
import * as api from '../services/api';
import type { User } from '../types';
import VillagePhotoBanner from '../components/VillagePhotoBanner';

interface LoginPageProps {
  onLoginSuccess: (user: User) => void;
  onNavigateRegister: () => void;
  onNavigateForgotPassword: () => void;
}

export default function LoginPage({ onLoginSuccess, onNavigateRegister, onNavigateForgotPassword }: LoginPageProps) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    if (!username.trim() || !password) {
      setError('Username and password are both required');
      return;
    }
    setIsLoading(true);
    try {
      const { token, user } = await api.login(username.trim(), password);
      api.setToken(token);
      onLoginSuccess(user);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="relative min-h-screen flex items-center justify-center p-6 overflow-hidden font-sans">
      <VillagePhotoBanner />

      <div className="relative z-10 w-full max-w-sm">
        <div className="flex flex-col items-center text-center mb-6">
          <div className="w-14 h-14 rounded-2xl bg-sidebar border border-accent flex items-center justify-center shadow-lg">
            <Landmark className="w-7 h-7 text-accent" />
          </div>
          <h1 className="mt-3 text-xl font-serif font-semibold text-white drop-shadow">Mhari Panchayat</h1>
          <p className="text-xs text-white/90 mt-1 drop-shadow">Admin Panel — please sign in</p>
        </div>

        <form onSubmit={handleLogin} className="bg-paper/95 backdrop-blur border border-white/60 rounded-2xl shadow-xl p-6 space-y-4">
          <div>
            <label className="text-[10px] font-bold text-muted uppercase block mb-1">Username</label>
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="w-full border border-line rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-accent"
              autoFocus
            />
          </div>
          <div>
            <label className="text-[10px] font-bold text-muted uppercase block mb-1">Password</label>
            <div className="relative">
              <input
                type={showPassword ? 'text' : 'password'}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full border border-line rounded-lg px-3 py-2.5 pr-10 text-sm focus:outline-none focus:ring-2 focus:ring-accent"
              />
              <button
                type="button"
                onClick={() => setShowPassword((v) => !v)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted hover:text-ink"
              >
                {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
          </div>

          <div className="flex justify-end">
            <button type="button" onClick={onNavigateForgotPassword} className="text-xs text-accent font-semibold hover:underline cursor-pointer">
              Forgot password?
            </button>
          </div>

          {error && <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2">{error}</p>}

          <button
            type="submit"
            disabled={isLoading}
            className="w-full bg-accent hover:bg-accent-dark disabled:opacity-50 text-white font-bold py-2.5 rounded-lg text-sm flex items-center justify-center gap-2 cursor-pointer"
          >
            <LogIn className="w-4 h-4" />
            {isLoading ? 'Signing in…' : 'Sign In'}
          </button>

          <p className="text-center text-xs text-muted">
            Don't have an account?{' '}
            <button type="button" onClick={onNavigateRegister} className="text-accent font-bold hover:underline cursor-pointer">
              Register
            </button>
          </p>
        </form>
      </div>
    </div>
  );
}
