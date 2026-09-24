import { useState, type FormEvent } from 'react';
import { sendPasswordResetEmail, signInWithEmailAndPassword } from 'firebase/auth';
import { auth } from '../data/firebase';

function authMessage(e: unknown): string {
  const code = (e as { code?: string })?.code ?? '';
  if (/invalid-credential|wrong-password|user-not-found|invalid-email/.test(code)) return 'That email or password is not right.';
  if (/too-many-requests/.test(code)) return 'Too many attempts. Wait a few minutes, or reset your password.';
  if (/user-disabled/.test(code)) return 'This account has been switched off. Ask an administrator.';
  if (/network/.test(code)) return 'Could not reach the server. Check your connection.';
  return 'Sign-in failed. Please try again.';
}

export function SignIn({ notice }: { notice?: string | null }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(notice ?? null);
  const [info, setInfo] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError(null); setInfo(null); setBusy(true);
    try {
      await signInWithEmailAndPassword(auth, email.trim(), password);
    } catch (err) {
      setError(authMessage(err));
    } finally {
      setBusy(false);
    }
  }

  async function reset() {
    setError(null); setInfo(null);
    if (!email.trim()) { setError('Enter your email address first, then choose "Forgot password".'); return; }
    try {
      await sendPasswordResetEmail(auth, email.trim());
      setInfo('If that account exists, a password reset email is on its way.');
    } catch (err) {
      setError(authMessage(err));
    }
  }

  return (
    <main className="signin">
      <form className="card signin__card" onSubmit={e => void submit(e)}>
        <div className="brand brand--large">Matrix <span>Door Scheduler</span></div>
        <p className="muted">Version 2 preview. Sign in with your Matrix account.</p>
        <label>Email<input type="email" autoComplete="username" value={email} onChange={e => setEmail(e.target.value)} required /></label>
        <label>Password<input type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} required /></label>
        {error && <p className="form-error" role="alert">{error}</p>}
        {info && <p className="form-info" role="status">{info}</p>}
        <button className="primary" type="submit" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button>
        <button type="button" className="link" onClick={() => void reset()}>Forgot password?</button>
        <p className="muted small">Accounts are set up by an administrator.</p>
      </form>
    </main>
  );
}
