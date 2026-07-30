import { useState } from 'react';
import { Landmark, KeyRound } from 'lucide-react';
import * as api from '../services/api';

interface ForgotPasswordPageProps {
  onDone: () => void;
  onNavigateLogin: () => void;
}

export default function ForgotPasswordPage({ onDone, onNavigateLogin }: ForgotPasswordPageProps) {
  const [step, setStep] = useState<'request' | 'reset'>('request');
  const [username, setUsername] = useState('');
  const [devToken, setDevToken] = useState('');
  const [token, setToken] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');

  const handleRequest = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setIsLoading(true);
    try {
      const { message, devToken } = await api.requestPasswordReset(username.trim());
      setInfo(message);
      if (devToken) {
        setDevToken(devToken);
        setToken(devToken);
      }
      setStep('reset');
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsLoading(false);
    }
  };

  const handleReset = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    if (newPassword.length < 8) {
      setError('Password must be at least 8 characters');
      return;
    }
    if (newPassword !== confirmPassword) {
      setError('Passwords do not match');
      return;
    }
    setIsLoading(true);
    try {
      await api.resetPassword(token.trim(), newPassword, confirmPassword);
      onDone();
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
          <p className="text-xs text-muted mt-1">Reset your password</p>
        </div>

        {step === 'request' ? (
          <form onSubmit={handleRequest} className="bg-paper border border-line rounded-2xl shadow-sm p-6 space-y-4">
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
            {error && <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2">{error}</p>}
            <button
              type="submit"
              disabled={isLoading}
              className="w-full bg-accent hover:bg-accent-dark disabled:opacity-50 text-white font-bold py-2.5 rounded-lg text-sm flex items-center justify-center gap-2 cursor-pointer"
            >
              <KeyRound className="w-4 h-4" />
              {isLoading ? 'Requesting…' : 'Request Reset Token'}
            </button>
            <p className="text-center text-xs text-muted">
              <button type="button" onClick={onNavigateLogin} className="text-accent font-bold hover:underline cursor-pointer">
                Back to Sign In
              </button>
            </p>
          </form>
        ) : (
          <form onSubmit={handleReset} className="bg-paper border border-line rounded-2xl shadow-sm p-6 space-y-4">
            {info && <p className="text-xs text-status-closed bg-status-closed/10 border border-status-closed/20 rounded-lg p-2">{info}</p>}
            {devToken && (
              <p className="text-[11px] text-status-accepted bg-status-accepted/10 border border-status-accepted/20 rounded-lg p-2">
                <strong>Development only</strong> — no email/SMS provider is configured yet, so the reset
                token is shown here directly: <span className="font-mono break-all">{devToken}</span>
              </p>
            )}
            <div>
              <label className="text-[10px] font-bold text-muted uppercase block mb-1">Reset Token</label>
              <input
                value={token}
                onChange={(e) => setToken(e.target.value)}
                className="w-full border border-line rounded-lg px-3 py-2.5 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-accent"
              />
            </div>
            <div>
              <label className="text-[10px] font-bold text-muted uppercase block mb-1">New Password (min 8 chars)</label>
              <input
                type="password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                className="w-full border border-line rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-accent"
              />
            </div>
            <div>
              <label className="text-[10px] font-bold text-muted uppercase block mb-1">Confirm New Password</label>
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
              className="w-full bg-accent hover:bg-accent-dark disabled:opacity-50 text-white font-bold py-2.5 rounded-lg text-sm cursor-pointer"
            >
              {isLoading ? 'Resetting…' : 'Reset Password'}
            </button>
            <p className="text-center text-xs text-muted">
              <button type="button" onClick={onNavigateLogin} className="text-accent font-bold hover:underline cursor-pointer">
                Back to Sign In
              </button>
            </p>
          </form>
        )}
      </div>
    </div>
  );
}
