import { useCallback, useEffect, useRef, useState } from 'react';
import { ArrowLeft, LogOut, RefreshCw, Search } from 'lucide-react';
import type { AdminAction, AdminOverview, AdminServer } from '../shared/admin';
import { GALAXY_TYPES } from '../shared/galaxySettings';
import { AdminMatchView } from './AdminMatchView';
import './admin-panel.css';

export const adminStatus: Record<AdminServer['status'], string> = {
  running: 'Läuft',
  paused: 'Pausiert',
  finished: 'Beendet',
  provisioning: 'Wird erstellt',
  unavailable: 'Nicht erreichbar',
};
export function AdminPanel() {
  const [token, setToken] = useState('');
  const [key, setKey] = useState('');
  const [data, setData] = useState<AdminOverview | null>(null);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState('all');
  const [selected, setSelected] = useState(location.hash.slice(1));
  const requestId = useRef(0);
  const acting = useRef(false);
  const refresh = useCallback(async (credential: string) => {
    const id = ++requestId.current;
    setLoading(true);
    try {
      const response = await fetch('/api/admin/servers', {
        headers: { Authorization: `Bearer ${credential}` },
        signal: AbortSignal.timeout(90000),
      });
      const result = await response.json();
      if (id !== requestId.current) return;
      if (!response.ok) {
        if (response.status === 401) {
          setToken('');
          setData(null);
        }
        throw new Error(result.error || 'Übersicht konnte nicht geladen werden.');
      }
      setData(result);
      setToken(credential);
      setKey('');
      setError('');
    } catch (e) {
      if (id === requestId.current) setError(e instanceof Error ? e.message : 'Verbindung fehlgeschlagen.');
    } finally {
      if (id === requestId.current) setLoading(false);
    }
  }, []);
  useEffect(() => {
    if (!token) return;
    const timer = window.setInterval(() => {
      if (!document.hidden && !acting.current && !loading) void refresh(token);
    }, 15000);
    return () => window.clearInterval(timer);
  }, [token, refresh, loading]);
  useEffect(() => {
    const changed = () => setSelected(location.hash.slice(1));
    window.addEventListener('hashchange', changed);
    return () => {
      requestId.current++;
      window.removeEventListener('hashchange', changed);
    };
  }, []);
  async function act(code: string, action: AdminAction): Promise<boolean> {
    if (acting.current) return false;
    acting.current = true;
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const response = await fetch(`/api/admin/servers/${code}`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(action),
        signal: AbortSignal.timeout(60000),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Aktion fehlgeschlagen.');
      setNotice(
        action.action === 'delete' ? `Match ${code} gelöscht.` : `Änderung in Match ${code} gespeichert.`,
      );
      if (action.action === 'delete') {
        setSelected('');
        history.replaceState(null, '', location.pathname);
      }
      await refresh(token);
      return true;
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Aktion fehlgeschlagen.');
      return false;
    } finally {
      acting.current = false;
      setBusy(false);
    }
  }
  const servers = data?.servers ?? [];
  const visible = servers.filter(
    (s) =>
      (filter === 'all' || s.status === filter) &&
      `${s.code} ${s.database} ${s.players?.map((p) => p.name).join(' ') ?? ''}`
        .toLowerCase()
        .includes(search.toLowerCase().trim()),
  );
  const current = servers.find((s) => s.code === selected);
  const select = (code: string) => {
    if (acting.current) return;
    setSelected(code);
    location.hash = code;
    setNotice('');
  };
  return (
    <main className="admin-page">
      <header className="admin-header">
        <a href="/" className="admin-brand">
          SINGULARITY <span>/ Administration</span>
        </a>
        <nav aria-label="Admin-Navigation">
          <a href="/">
            <ArrowLeft size={14} /> Spiel
          </a>
          {token && (
            <button
              disabled={busy}
              onClick={() => {
                requestId.current++;
                setToken('');
                setData(null);
                setError('');
                setNotice('');
                setLoading(false);
              }}
            >
              <LogOut size={14} /> Abmelden
            </button>
          )}
        </nav>
      </header>
      {!token ? (
        <section className="admin-login">
          <h1>Administration</h1>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              void refresh(key.trim());
            }}
          >
            <label htmlFor="admin-key">Admin-Schlüssel</label>
            <input
              id="admin-key"
              type="password"
              autoComplete="off"
              required
              value={key}
              onChange={(e) => setKey(e.target.value)}
            />
            <button disabled={loading || !key.trim()}>
              {loading ? 'Verbindung wird geprüft …' : 'Anmelden'}
            </button>
          </form>
          <p>Schlüssel aus dem Gateway-Terminal oder ADMIN_PANEL_TOKEN.</p>
          {error && (
            <p role="alert" className="admin-error">
              {error}
            </p>
          )}
        </section>
      ) : (
        <>
          <div className="admin-toolbar">
            <h1>
              Matches <span>{servers.length}</span>
            </h1>
            <span className="admin-muted">
              {servers.filter((s) => s.status === 'running').length} aktiv ·{' '}
              {servers.flatMap((s) => s.players ?? []).filter((p) => p.online).length} Spieler online
            </span>
            <button disabled={loading || busy} onClick={() => void refresh(token)}>
              <RefreshCw size={14} /> {loading ? 'Lädt …' : 'Aktualisieren'}
            </button>
          </div>
          {error && (
            <p role="alert" className="admin-error">
              {error}
            </p>
          )}
          {notice && (
            <p role="status" className="admin-notice">
              {notice}
            </p>
          )}
          <div className="admin-filters">
            <label>
              <Search size={14} />
              <input
                aria-label="Matches suchen"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Raumcode oder Reich suchen"
              />
            </label>
            <select
              aria-label="Nach Status filtern"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
            >
              <option value="all">Alle Status</option>
              {Object.entries(adminStatus).map(([value, label]) => (
                <option value={value} key={value}>
                  {label}
                </option>
              ))}
            </select>
          </div>
          <div className="admin-table-scroll">
            <table className="admin-matches">
              <thead>
                <tr>
                  <th>Match</th>
                  <th>Status</th>
                  <th>Galaxie</th>
                  <th>Systeme</th>
                  <th>Tag</th>
                  <th>Tempo</th>
                  <th>Reiche</th>
                  <th>Online</th>
                </tr>
              </thead>
              <tbody>
                {visible.map((s) => (
                  <tr
                    key={s.code}
                    className={selected === s.code ? 'selected' : ''}
                    onClick={() => select(s.code)}
                  >
                    <td>
                      <button
                        aria-label={`Match ${s.code} öffnen`}
                        aria-current={selected === s.code ? 'true' : undefined}
                        disabled={busy}
                        onClick={(e) => {
                          e.stopPropagation();
                          select(s.code);
                        }}
                      >
                        {s.code}
                        <span>→</span>
                      </button>
                    </td>
                    <td>
                      <span className={`admin-status ${s.status}`}>{adminStatus[s.status]}</span>
                    </td>
                    <td>{s.galaxy ? GALAXY_TYPES[s.galaxy.type].name : '—'}</td>
                    <td>{s.galaxy?.systems.toLocaleString('de-DE') ?? '—'}</td>
                    <td>{s.day?.toLocaleString('de-DE') ?? '—'}</td>
                    <td>{s.speed ? `${s.speed}×` : '—'}</td>
                    <td>{s.players ? `${s.players.length} / ${s.capacity}` : '—'}</td>
                    <td>{s.players?.filter((p) => p.online).length ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {!visible.length && (
            <p className="admin-empty">
              {servers.length
                ? 'Keine Matches für diesen Filter.'
                : 'Keine Matches vorhanden. Einen Sektor im Spiel gründen.'}
            </p>
          )}
          {current ? (
            <AdminMatchView
              key={current.code}
              token={token}
              server={current}
              revision={data!.updatedAt}
              busy={busy}
              act={act}
            />
          ) : (
            <p className="admin-empty">
              {selected
                ? 'Dieses Match ist nicht mehr registriert. Wähle ein anderes Match.'
                : 'Match auswählen, um Karte, Reiche und Aktionen zu öffnen.'}
            </p>
          )}
          <footer className="admin-footer">
            Stand {data && new Date(data.updatedAt).toLocaleTimeString('de-DE')} · Aktualisierung alle 15
            Sekunden · SpacetimeDB
          </footer>
        </>
      )}
    </main>
  );
}
