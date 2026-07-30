import { useState } from 'react';
import { Landmark, UserPlus } from 'lucide-react';
import * as api from '../services/api';
import type { User } from '../types';

interface RegisterPageProps {
  onRegisterSuccess: (user: User) => void;
  onNavigateLogin: () => void;
}

export default function RegisterPage({ onRegisterSuccess, onNavigateLogin }: RegisterPageProps) {
  const [name, setName] = useState('');
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    if (!username.trim() || !password) {
      setError('Username and password are required');
      return;
    }
    if (password.length < 8) {
      setError('Password must be at least 8 characters');
      return;
    }
    if (password !== confirmPassword) {
      setError('Passwords do not match');
      return;
    }
    setIsLoading(true);
    try {
      const { token, user } = await api.register(username.trim(), password, name.trim() || undefined, email.trim() || undefined);
      api.setToken(token);
      onRegisterSuccess(user);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-cream p-6 font-sans">
      <div className="w-full max-w-sm">
        <div className="flex flex-col items-center text-center mb-6">
          <div className="w-14 h-14 rounded-2xl bg-sidebar border border-accent flex items-center justify-center shadow-lg">
            <Landmark className="w-7 h-7 text-accent" />
          </div>
          <h1 className="mt-3 text-xl font-serif font-semibold text-sidebar">Mhari Panchayat</h1>
          <p className="text-xs text-muted mt-1">Create your admin account</p>
        </div>

        <form onSubmit={handleSubmit} className="bg-paper border border-line rounded-2xl shadow-sm p-6 space-y-3">
          <div>
            <label className="text-[10px] font-bold text-muted uppercase block mb-1">Name</label>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full border border-line rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-accent"
            />
          </div>
          <div>
            <label className="text-[10px] font-bold text-muted uppercase block mb-1">Username *</label>
            <input
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="w-full border border-line rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-accent"
            />
          </div>
          <div>
            <label className="text-[10px] font-bold text-muted uppercase block mb-1">Email</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full border border-line rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-accent"
            />
          </div>
          <div>
            <label className="text-[10px] font-bold text-muted uppercase block mb-1">Password * (min 8 chars)</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full border border-line rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-accent"
            />
          </div>
          <div>
            <label className="text-[10px] font-bold text-muted uppercase block mb-1">Confirm Password *</label>
            <input
              type="password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              className="w-full border border-line rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-accent"
            />
          </div>

          {error && <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2">{error}</p>}

          <button
            type="submit"
            disabled={isLoading}
            className="w-full bg-accent hover:bg-accent-dark disabled:opacity-50 text-white font-bold py-2.5 rounded-lg text-sm flex items-center justify-center gap-2 cursor-pointer"
          >
            <UserPlus className="w-4 h-4" />
            {isLoading ? 'Creating account…' : 'Register'}
          </button>

          <p className="text-center text-xs text-muted">
            Already have an account?{' '}
            <button type="button" onClick={onNavigateLogin} className="text-accent font-bold hover:underline cursor-pointer">
              Sign In
            </button>
          </p>
        </form>
      </div>
    </div>
  );
}
