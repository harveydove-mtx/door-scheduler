import { useEffect, useState } from 'react';
import { onAuthStateChanged, signOut, type User } from 'firebase/auth';
import { ensureMe, errorMessage, type Me } from './data/api';
import { auth, missingConfig, usingEmulators } from './data/firebase';
import { MatCodes } from './pages/MatCodes';
import { Products } from './pages/Products';
import { SignIn } from './pages/SignIn';

const PAGES = { 'mat-codes': 'MAT codes & rates', products: 'Products' } as const;
type Page = keyof typeof PAGES;
const pageFromHash = (): Page => (location.hash.replace('#/', '') in PAGES ? (location.hash.replace('#/', '') as Page) : 'mat-codes');

export function App() {
  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [me, setMe] = useState<Me | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [page, setPage] = useState<Page>(pageFromHash);

  useEffect(() => {
    const onHash = () => setPage(pageFromHash());
    addEventListener('hashchange', onHash);
    return () => removeEventListener('hashchange', onHash);
  }, []);

  useEffect(() => onAuthStateChanged(auth, async u => {
    setMe(null);
    setUser(u);
    if (!u) return;
    try {
      setMe(await ensureMe());
      setNotice(null);
    } catch (e) {
      // e.g. a non-Matrix account: the server refuses it, so sign straight back out
      setNotice(`Signed out: ${errorMessage(e)}`);
      await signOut(auth);
    }
  }), []);

  if (missingConfig.length) {
    return <main className="signin"><div className="card"><h1>Not configured</h1>
      <p>Missing Firebase settings: {missingConfig.join(', ')}. See docs/v2-firebase-setup.md.</p></div></main>;
  }
  if (user === undefined) return <p className="muted pad">Loading…</p>;
  if (!user) return <SignIn notice={notice} />;
  if (!me) return <p className="muted pad">Signing in…</p>;

  return (
    <div className="shell">
      <header className="topbar">
        <div className="brand">Matrix <span>Door Scheduler</span> <small>V2 preview</small></div>
        <nav aria-label="Pages">
          {(Object.keys(PAGES) as Page[]).map(p => (
            <a key={p} href={`#/${p}`} aria-current={page === p ? 'page' : undefined}>{PAGES[p]}</a>
          ))}
        </nav>
        <div className="me">
          <span title={me.email}>{me.display_name}</span>
          <button onClick={() => void signOut(auth)}>Sign out</button>
        </div>
      </header>
      {usingEmulators && <div className="banner">Local test mode: using the Firebase emulators, not real data.</div>}
      <main className="content">
        {page === 'mat-codes' ? <MatCodes /> : <Products />}
      </main>
    </div>
  );
}
