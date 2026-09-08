import { RESOURCE_IDS, RESOURCE_NAMES, type Resource } from '../shared/resources';
import { useEffect, useState } from 'react';
import { Copy, Crosshair, Download, ExternalLink, Pause, Play, Plus, Trash2 } from 'lucide-react';
import type { AdminAction, AdminEmpire, AdminMatch, AdminServer } from '../shared/admin';
import { AUTHORITIES, CIVICS, ETHICS, ORIGINS, ENVIRONMENTS, TRAITS } from '../shared/empireCatalog';
import { TECHS } from '../shared/game';
import { EmpireFlag } from './EmpireFlag';
import { AdminGalaxyMap } from './AdminGalaxyMap';
const number = (value: number) => Math.floor(value).toLocaleString('de-DE');
const population = (value: number) => value.toLocaleString('de-DE', { maximumFractionDigits: 2 });
const orderNames: Record<string, string> = {
  idle: 'Bereit',
  move: 'Unterwegs',
  scan: 'Erkundung',
  colonize: 'Kolonisierung',
  battle: 'Im Gefecht',
};

export function AdminMatchView({
  token,
  server,
  revision,
  busy,
  act,
}: {
  token: string;
  server: AdminServer;
  revision: string;
  busy: boolean;
  act: (code: string, action: AdminAction) => Promise<boolean>;
}) {
  const [match, setMatch] = useState<AdminMatch | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [empireId, setEmpireId] = useState(0);
  const [systemId, setSystemId] = useState(0);
  const [focus, setFocus] = useState<{ x: number; y: number; serial: number } | null>(null);
  const [tab, setTab] = useState<'empire' | 'colonies' | 'fleets'>('empire');
  const [deleting, setDeleting] = useState(false);
  const [confirmation, setConfirmation] = useState('');
  const [message, setMessage] = useState('');
  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    const timeout = setTimeout(() => controller.abort('timeout'), 15000);
    void (async () => {
      try {
        const response = await fetch(`/api/admin/servers/${server.code}`, {
          headers: { Authorization: `Bearer ${token}` },
          signal: controller.signal,
        });
        const result = await response.json();
        if (!response.ok) throw new Error(result.error || 'Matchdetails nicht verfügbar.');
        if (!controller.signal.aborted) {
          setMatch(result);
          setError('');
        }
      } catch (e) {
        if (controller.signal.reason !== 'cleanup')
          setError(e instanceof Error ? e.message : 'Matchdetails nicht verfügbar.');
      } finally {
        clearTimeout(timeout);
        if (controller.signal.reason !== 'cleanup') setLoading(false);
      }
    })();
    return () => {
      controller.abort('cleanup');
      clearTimeout(timeout);
    };
  }, [token, server.code, revision]);
  const empire = match?.empires.find((e) => e.id === empireId);
  const system = match?.systems.find((s) => s.id === systemId);
  const controllable = server.status === 'paused' || server.status === 'running';
  const blocked = busy || loading || !!error;
  const focusSystem = (id: number) => {
    const s = match?.systems.find((s) => s.id === id);
    if (s) {
      setSystemId(id);
      setFocus({ x: s.x, y: s.y, serial: Date.now() });
    }
  };
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(`${location.origin}/?room=${server.code}`);
      setMessage('Einladungslink kopiert.');
    } catch {
      setMessage(`Einladung: ${location.origin}/?room=${server.code}`);
    }
  };
  const exportMatch = () => {
    if (!match) return;
    const url = URL.createObjectURL(new Blob([JSON.stringify(match, null, 2)], { type: 'application/json' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = `match-${server.code}.json`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  return (
    <section className="admin-match-detail" aria-label={`Matchdetails ${server.code}`}>
      <div className="admin-match-heading">
        <h2>Match {server.code}</h2>
        <span className="admin-muted">{server.database}</span>
        <a href={`/?room=${server.code}`} target="_blank" rel="noreferrer">
          <ExternalLink size={14} /> Im Spiel öffnen
        </a>
      </div>
      <div className="admin-actions">
        <button
          disabled={!controllable || blocked}
          onClick={() =>
            void act(server.code, {
              action: 'clock',
              paused: server.status === 'running',
              speed: server.speed!,
            })
          }
        >
          {server.status === 'running' ? <Pause size={14} /> : <Play size={14} />}
          {server.status === 'running' ? 'Pausieren' : 'Fortsetzen'}
        </button>
        <select
          aria-label={`Tempo für ${server.code}`}
          disabled={!controllable || blocked}
          value={server.speed ?? 1}
          onChange={(e) =>
            void act(server.code, {
              action: 'clock',
              paused: server.status === 'paused',
              speed: Number(e.target.value),
            })
          }
        >
          {[1, 2, 3, 4].map((n) => (
            <option key={n} value={n}>
              {n}× Tempo
            </option>
          ))}
        </select>
        <button
          disabled={!controllable || blocked || (server.players?.length ?? 0) >= (server.capacity ?? 0)}
          onClick={() => void act(server.code, { action: 'add_ai' })}
        >
          <Plus size={14} /> KI hinzufügen
        </button>
        <button onClick={() => void copy()}>
          <Copy size={14} /> Einladung
        </button>
        <button disabled={!match} onClick={exportMatch}>
          <Download size={14} /> Bericht exportieren
        </button>
        <button className="admin-danger" disabled={busy} onClick={() => setDeleting(!deleting)}>
          <Trash2 size={14} /> Match löschen
        </button>
        {busy && <span role="status">Wird gespeichert …</span>}
      </div>
      {message && (
        <p role="status" className="admin-notice">
          {message}
        </p>
      )}
      {deleting && (
        <form
          className="admin-delete"
          onSubmit={(e) => {
            e.preventDefault();
            void act(server.code, { action: 'delete', confirmation });
          }}
        >
          <strong>Match {server.code} mit allen Spielständen dauerhaft löschen</strong>
          <p>Reichs- und Speziesvorlagen bleiben erhalten.</p>
          <label htmlFor="admin-confirm">Raumcode zur Bestätigung</label>
          <input
            id="admin-confirm"
            autoComplete="off"
            value={confirmation}
            onChange={(e) => setConfirmation(e.target.value.toUpperCase())}
          />
          <button className="admin-danger" disabled={confirmation !== server.code || busy}>
            Endgültig löschen
          </button>
          <button type="button" onClick={() => setDeleting(false)} disabled={busy}>
            Abbrechen
          </button>
        </form>
      )}
      {error && (
        <p className="admin-error" role="alert">
          {error}{' '}
          {match
            ? 'Angezeigt wird der letzte geladene Stand.'
            : 'Die Partie kann oben weiterhin ausgewählt und verwaltet werden.'}
        </p>
      )}
      {!match ? (
        <p className="admin-empty">
          {loading ? 'Galaxie und Reiche werden geladen …' : 'Keine Matchdetails verfügbar.'}
        </p>
      ) : (
        <>
          <div className="admin-workspace">
            <div className="admin-map-column">
              <AdminGalaxyMap
                match={match}
                empireId={empireId}
                systemId={systemId}
                focus={focus}
                onSystem={(id) => {
                  setSystemId(id);
                  const owner = match.systems.find((s) => s.id === id)?.ownerId;
                  if (owner) setEmpireId(owner);
                }}
              />
              <div className="admin-system-detail">
                {system ? (
                  <>
                    <strong>{system.name}</strong>
                    <span>{system.planet || system.kind}</span>
                    <span>{match.empires.find((e) => e.id === system.ownerId)?.name ?? 'Unbesetzt'}</span>
                    {system.colonyName && <span>Kolonie: {system.colonyName}</span>}
                    <span>
                      {match.fleets.filter((f) => f.systemId === system.id).length} Flotten im System
                    </span>
                    <button onClick={() => focusSystem(system.id)}>
                      <Crosshair size={14} /> Zentrieren
                    </button>
                  </>
                ) : (
                  <span>Ein System auf der Karte auswählen.</span>
                )}
              </div>
              <div className="admin-empire-list-heading">
                <h3>Reiche ({match.empires.length})</h3>
                <button onClick={() => setEmpireId(0)} disabled={!empireId}>
                  Alle auf der Karte
                </button>
              </div>
              <div className="admin-table-scroll">
                <table className="admin-empire-list">
                  <thead>
                    <tr>
                      <th>Reich</th>
                      <th>Kontrolle</th>
                      <th>Kolonien</th>
                      <th>Schiffe</th>
                      {RESOURCE_IDS.map((id) => (
                        <th key={id}>{RESOURCE_NAMES[id]}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {match.empires.map((e) => (
                      <tr
                        key={e.id}
                        className={empireId === e.id ? 'selected' : ''}
                        onClick={() => setEmpireId(e.id)}
                      >
                        <td>
                          <button aria-label={`Reich ${e.name} auswählen`} onClick={() => setEmpireId(e.id)}>
                            <i style={{ background: e.color }} />
                            {e.name}
                          </button>
                        </td>
                        <td>
                          {e.ai ? 'KI' : e.online ? 'Online' : 'Offline'}
                          {e.host ? ' · Host' : ''}
                        </td>
                        <td>{e.colonies.length}</td>
                        <td>
                          {number(
                            match.fleets
                              .filter((f) => f.empireId === e.id)
                              .reduce((sum, f) => sum + f.ships, 0),
                          )}
                        </td>
                        {RESOURCE_IDS.map((id) => (
                          <td key={id}>{number(e.resources[id])}</td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
            <aside className="admin-inspector" aria-label="Reichsdetails">
              {empire ? (
                <>
                  <div className="admin-empire-heading">
                    <EmpireFlag flag={empire.design.flag} width={42} />
                    <div>
                      <h3>{empire.name}</h3>
                      <span>
                        {empire.ai ? 'KI-Imperium' : 'Mensch'} ·{' '}
                        {empire.online ? 'Online' : empire.ai ? 'Autonom' : 'Offline'}
                        {empire.host ? ' · Host' : ''}
                      </span>
                    </div>
                  </div>
                  <div className="admin-inspector-actions">
                    <button onClick={() => focusSystem(empire.homeId)}>
                      <Crosshair size={14} /> Heimatwelt
                    </button>
                    <button
                      disabled={blocked || !controllable || empire.ai || !empire.online || empire.host}
                      onClick={() => void act(server.code, { action: 'host', empireId: empire.id })}
                    >
                      Als Host einsetzen
                    </button>
                  </div>
                  <div className="admin-tabs" role="tablist" aria-label="Reichsinformationen">
                    {(['empire', 'colonies', 'fleets'] as const).map((t) => (
                      <button
                        id={`admin-tab-${t}`}
                        role="tab"
                        aria-controls="admin-empire-tabpanel"
                        aria-selected={tab === t}
                        key={t}
                        onClick={() => setTab(t)}
                      >
                        {t === 'empire'
                          ? 'Reich'
                          : t === 'colonies'
                            ? `Kolonien (${empire.colonies.length})`
                            : `Flotten (${match.fleets.filter((f) => f.empireId === empire.id).length})`}
                      </button>
                    ))}
                  </div>
                  <div id="admin-empire-tabpanel" role="tabpanel" aria-labelledby={`admin-tab-${tab}`}>
                    {tab === 'empire' ? (
                      <>
                        <dl className="admin-facts">
                          <dt>Regierung</dt>
                          <dd>{AUTHORITIES[empire.design.government.authority].name}</dd>
                          <dt>Staatsoberhaupt</dt>
                          <dd>
                            {empire.design.rulerTitle} {empire.design.rulerName}
                          </dd>
                          <dt>Ursprung</dt>
                          <dd>{ORIGINS[empire.design.origin]?.name ?? empire.design.origin}</dd>
                          <dt>Ethiken</dt>
                          <dd>
                            {empire.design.government.ethics
                              .map((e) => `${e.strength === 2 ? 'Fanatisch ' : ''}${ETHICS[e.id].name}`)
                              .join(', ') || '—'}
                          </dd>
                          <dt>Staatselemente</dt>
                          <dd>
                            {empire.design.government.civics.map((c) => CIVICS[c]?.name ?? c).join(', ') ||
                              '—'}
                          </dd>
                          <dt>Erkundet</dt>
                          <dd>
                            {empire.surveyed} / {match.systems.length} Systeme
                          </dd>
                          <dt>Bevölkerung</dt>
                          <dd>{population(empire.colonies.reduce((n, c) => n + c.population, 0))} Mrd.</dd>
                          <dt>Technologien</dt>
                          <dd>
                            {empire.techs.map((t) => TECHS[t as keyof typeof TECHS]?.name ?? t).join(', ') ||
                              'Keine abgeschlossen'}
                          </dd>
                          <dt>Kriege</dt>
                          <dd>
                            {match.relations
                              .filter((r) => r.state === 'war' && (r.a === empire.id || r.b === empire.id))
                              .map(
                                (r) =>
                                  match.empires.find((e) => e.id === (r.a === empire.id ? r.b : r.a))?.name,
                              )
                              .join(', ') || 'Keine'}
                          </dd>
                        </dl>
                        <h4>Spezies</h4>
                        {empire.species.map((s, i) => (
                          <div className="admin-species" key={i}>
                            <strong>{s.name}</strong>
                            <p>
                              {ENVIRONMENTS[s.environment].name} ·{' '}
                              {s.traits.map((t) => TRAITS[t]?.name ?? t).join(', ') || 'Keine Merkmale'}
                            </p>
                          </div>
                        ))}
                        <ResourceAdjustment
                          key={empire.id}
                          empire={empire}
                          disabled={blocked || !controllable}
                          submit={(resource, amount) =>
                            act(server.code, { action: 'resources', empireId: empire.id, resource, amount })
                          }
                        />
                      </>
                    ) : tab === 'colonies' ? (
                      <>
                        {!empire.colonies.length && <p className="admin-empty">Keine Kolonien.</p>}
                        {empire.colonies.map((c) => (
                          <div className="admin-asset-row" key={c.id}>
                            <button onClick={() => focusSystem(c.id)}>
                              <Crosshair size={14} />
                              {c.name}
                            </button>
                            <span>{population(c.population)} Mrd. Einwohner</span>
                            <small>
                              Produktion / Monat:{' '}
                              {RESOURCE_IDS.map(
                                (id) => `${number(c.monthlyProduction[id])} ${RESOURCE_NAMES[id]}`,
                              ).join(' · ')}
                            </small>
                          </div>
                        ))}
                      </>
                    ) : (
                      <>
                        {!match.fleets.some((f) => f.empireId === empire.id) && (
                          <p className="admin-empty">Keine Flotten.</p>
                        )}
                        {match.fleets
                          .filter((f) => f.empireId === empire.id)
                          .map((f) => (
                            <div className="admin-asset-row" key={f.id}>
                              <button
                                onClick={() => {
                                  setFocus({ x: f.x, y: f.y, serial: Date.now() });
                                  setSystemId(f.systemId);
                                }}
                              >
                                <Crosshair size={14} />
                                {f.name}
                              </button>
                              <span>
                                {f.ships} Schiffe ·{' '}
                                {f.battleId ? 'Im Gefecht' : (orderNames[f.order] ?? f.order)}
                              </span>
                              <small>
                                {match.systems.find((s) => s.id === f.systemId)?.name ?? 'Im Hyperraum'}
                              </small>
                            </div>
                          ))}
                      </>
                    )}
                  </div>
                </>
              ) : (
                <p className="admin-empty">
                  Ein Reich in der Liste oder ein besetztes System auf der Karte auswählen.
                </p>
              )}
            </aside>
          </div>
        </>
      )}
    </section>
  );
}
function ResourceAdjustment({
  empire,
  disabled,
  submit,
}: {
  empire: AdminEmpire;
  disabled: boolean;
  submit: (resource: Resource, amount: number) => Promise<boolean>;
}) {
  const [resource, setResource] = useState<Resource>('energy');
  const [amount, setAmount] = useState('');
  const value = Number(amount);
  const valid =
    Number.isInteger(value) &&
    value !== 0 &&
    Math.abs(value) <= 100000 &&
    empire.resources[resource] + value >= 0;
  return (
    <form
      className="admin-resource-form"
      onSubmit={async (e) => {
        e.preventDefault();
        if (valid && (await submit(resource, value))) setAmount('');
      }}
    >
      <h4>Ressourcen buchen</h4>
      <p>
        Positive Werte gutschreiben, negative Werte abziehen. Die Buchung erscheint im Ereignisprotokoll des
        Reichs.
      </p>
      <label htmlFor="admin-resource">Ressource</label>
      <select
        id="admin-resource"
        value={resource}
        disabled={disabled}
        onChange={(e) => setResource(e.target.value as typeof resource)}
      >
        {RESOURCE_IDS.map((id) => (
          <option key={id} value={id}>
            {RESOURCE_NAMES[id]}
          </option>
        ))}
      </select>
      <label htmlFor="admin-resource-amount">Änderung (−100.000 bis +100.000)</label>
      <input
        id="admin-resource-amount"
        type="number"
        step="1"
        min={Math.max(-100000, -Math.floor(empire.resources[resource]))}
        max="100000"
        required
        value={amount}
        disabled={disabled}
        onChange={(e) => setAmount(e.target.value)}
      />
      <p>
        {number(empire.resources[resource])} → {valid ? number(empire.resources[resource] + value) : '—'}
      </p>
      <button disabled={disabled || !valid}>Buchung anwenden</button>
    </form>
  );
}
