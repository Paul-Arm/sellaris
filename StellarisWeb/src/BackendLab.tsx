import { useEffect, useRef, useState } from 'react';
import { ArrowLeft, Activity, Radio, Orbit, Cpu, Network, Crosshair, RefreshCw } from 'lucide-react';
import { connect, join, subscribe, GALAXY_QUERIES, type Client } from '../backend/client';
import { BattleDetailSubscription } from '../backend/detail-subscriptions';
import { BattleOverview } from './BattleOverview';
import { gameTimeAt, progressAt } from '../backend/domain';
import { LabScene, type FrameStats } from './LabScene';
import './backend-lab.css';

declare global {
  interface Window {
    __singularityLab?: {
      frames: FrameStats | null;
      database: string;
      systems: number;
      fleets: number;
      ships: number;
      participants: number;
      receivedBytes: number;
      decodedBytes: number;
      compressedFrames: number;
      peakPendingBytes: number;
      viewport: string;
    };
  }
}
const number = (n: number) => Math.floor(n).toLocaleString('de-DE');

export function BackendLab() {
  const params = new URLSearchParams(location.search);
  const [database, setDatabase] = useState(params.get('database') || 'singularity-foundation');
  const [empireId, setEmpireId] = useState(Number(params.get('empire') || 1));
  const [client, setClient] = useState<Client | null>(null);
  const [status, setStatus] = useState('Bereit zum Verbinden');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [focusBusy, setFocusBusy] = useState(false);
  const details = useRef<BattleDetailSubscription | null>(null),
    focusGeneration = useRef(0);
  const [mode, setMode] = useState<'galaxy' | 'battle'>('galaxy');
  const [fleetId, setFleetId] = useState(0),
    [battleId, setBattleId] = useState(0);
  const [stats, setStats] = useState<FrameStats | null>(null);
  const [version, refresh] = useState(0);
  const alive = useRef(true),
    connection = useRef<Client | null>(null),
    generation = useRef(0);
  const previousTraffic = useRef({ time: performance.now(), bytes: 0 }),
    [rate, setRate] = useState(0);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
      generation.current++;
      focusGeneration.current++;
      details.current?.dispose();
      connection.current?.conn.disconnect();
    };
  }, []);
  useEffect(() => {
    if (!client) return;
    const interval = setInterval(() => {
      refresh((v) => v + 1);
      const time = performance.now(),
        old = previousTraffic.current;
      setRate((((client.traffic.receivedBytes - old.bytes) / Math.max(1, time - old.time)) * 1000) / 1024);
      previousTraffic.current = { time, bytes: client.traffic.receivedBytes };
    }, 500);
    return () => clearInterval(interval);
  }, [client]);
  async function attach() {
    const current = ++generation.current;
    setBusy(true);
    setError('');
    setStatus('Verbindung wird aufgebaut …');
    focusGeneration.current++;
    details.current?.dispose();
    details.current = null;
    setFocusBusy(false);
    connection.current?.conn.disconnect();
    connection.current = null;
    setClient(null);
    const key = `singularity.lab:${database}`;
    try {
      const token = sessionStorage.getItem(key) || undefined;
      const next = await connect(database, {
        uri: import.meta.env.VITE_SPACETIME_URI || 'ws://127.0.0.1:3100',
        token,
        onDisconnect: () => {
          if (alive.current && current === generation.current)
            setStatus('Verbindung getrennt · Wiederverbinden möglich');
        },
      });
      if (!alive.current || current !== generation.current) {
        next.conn.disconnect();
        return;
      }
      sessionStorage.setItem(key, next.token);
      connection.current = next;
      if (token) {
        // Never restore a stale detailed battle subscription when reconnecting to the galaxy.
        await subscribe(next.conn, GALAXY_QUERIES);
        const existing = [...next.conn.db.myEmpire.iter()][0];
        if (!existing) await next.conn.reducers.joinEmpire({ empireId });
        else setEmpireId(existing.id);
      } else {
        await join(next, empireId);
      }
      await next.conn.reducers.setFocus({ fleetId: 0, battleId: 0 });
      if (!alive.current || current !== generation.current) {
        next.conn.disconnect();
        return;
      }
      previousTraffic.current = { time: performance.now(), bytes: next.traffic.receivedBytes };
      details.current = new BattleDetailSubscription(next);
      setClient(next);
      setStatus('Synchronisiert · Live-Simulation');
      setMode('galaxy');
      setFleetId(0);
      setBattleId(0);
    } catch (e) {
      if (alive.current) {
        setError(String(e));
        setStatus('Verbindung nicht hergestellt');
        connection.current?.conn.disconnect();
      }
    } finally {
      if (alive.current) setBusy(false);
    }
  }
  async function focus(nextFleet: number, nextBattle: number, nextMode = mode) {
    const scope = details.current;
    if (!client || !scope) return;
    const request = ++focusGeneration.current;
    setFocusBusy(true);
    try {
      await scope.focus(nextMode === 'battle' ? nextFleet : 0, nextMode === 'battle' ? nextBattle : 0);
      if (!alive.current || request !== focusGeneration.current) return;
      setFleetId(nextFleet);
      setBattleId(nextBattle);
      setMode(nextMode);
      setStats(null);
      setError('');
    } catch (e) {
      if (alive.current && request === focusGeneration.current) setError(String(e));
    } finally {
      if (alive.current && request === focusGeneration.current) setFocusBusy(false);
    }
  }
  const world = client?.conn.db.scenario.id.find(1);
  const me = client ? [...client.conn.db.myEmpire.iter()][0] : undefined;
  const fleets = client ? [...client.conn.db.galaxyFleets.iter()] : [];
  const ownFleets = fleets.filter((f) => f.empireId === me?.id).sort((a, b) => a.id - b.id);
  const battles = client
    ? [...client.conn.db.visibleBattleSummaries.iter()].sort(
        (a, b) => Number(b.state === 'active') - Number(a.state === 'active') || a.id - b.id,
      )
    : [];
  const ships = client ? [...client.conn.db.fleetShips.iter()] : [];
  const participants = client ? Number(client.conn.db.battleRoster.count()) : 0;
  const anchor = client?.conn.db.clock.id.find(1);
  const at = anchor ? gameTimeAt(anchor, Date.now() / 1000) : 0;
  const jobs = client ? [...client.conn.db.myJobs.iter()].filter((j) => j.status === 'active') : [];
  useEffect(() => {
    window.__singularityLab = {
      frames: stats,
      database,
      systems: world?.systems ?? 0,
      fleets: fleets.length,
      ships: ships.length,
      participants,
      receivedBytes: client?.traffic.receivedBytes ?? 0,
      decodedBytes: client?.traffic.decodedBytes ?? 0,
      compressedFrames: client?.traffic.compressedFrames ?? 0,
      peakPendingBytes: client?.traffic.peakPendingBytes ?? 0,
      viewport: `${innerWidth}×${innerHeight} @${devicePixelRatio}`,
    };
  }, [stats, database, world, fleets.length, ships.length, participants, client, version]);
  return (
    <main className="backend-lab">
      <header className="lab-header">
        <a href="/" className="lab-back">
          <ArrowLeft size={16} /> Zum Spiel
        </a>
        <div className="lab-wordmark">
          SINGULARITY <span>BACKEND LAB</span>
        </div>
        <span className="lab-version">SPACETIMEDB 2.10</span>
      </header>
      <section className="lab-intro">
        <div>
          <div className="lab-eyebrow">SIMULATION / ARCHITEKTURPROBE</div>
          <h1>Eine Galaxie. Ein Zustand.</h1>
          <p>Flotten, Wirtschaft und Gefechte auf einem autoritativen Server.</p>
        </div>
        <span className={`lab-connection ${client ? 'online' : ''}`}>
          <Radio size={15} />
          {status}
        </span>
      </section>
      <form
        className="lab-connect"
        onSubmit={(e) => {
          e.preventDefault();
          void attach();
        }}
      >
        <label>
          DATENBANK
          <input
            value={database}
            onChange={(e) => setDatabase(e.target.value)}
            pattern="[a-z0-9-]+"
            required
          />
        </label>
        <label>
          IMPERIUM
          <input
            type="number"
            min="1"
            max={world?.empires ?? 25}
            value={empireId}
            onChange={(e) => setEmpireId(Number(e.target.value))}
            required
          />
        </label>
        <button disabled={busy}>
          <RefreshCw size={15} />
          {busy ? 'Synchronisiere …' : client ? 'Wiederverbinden' : 'Verbinden'}
        </button>
        <span>Eigene Laborsitzung · laufende Gefechte bleiben erhalten</span>
      </form>
      {error && (
        <div className="lab-error" role="alert">
          {error}
        </div>
      )}
      <div className="lab-metrics">
        <div>
          <Orbit size={17} />
          <span>STERNENSYSTEME</span>
          <strong>{world ? number(world.systems) : '—'}</strong>
          <small>{world?.empires ?? '—'} Imperien</small>
        </div>
        <div>
          <Cpu size={17} />
          <span>SCHIFFE IM TEST</span>
          <strong>{world ? number(world.seededShips) : '—'}</strong>
          <small>{world ? number(world.empires * world.fleetsPerEmpire) : '—'} ursprüngliche Flotten</small>
        </div>
        <div>
          <Activity size={17} />
          <span>DARSTELLUNG</span>
          <strong>{stats ? `${Math.round(stats.fps)} FPS` : '—'}</strong>
          <small>
            {stats
              ? `${stats.drawCalls} Draw Calls · ${stats.frameP95Ms.toFixed(1)} ms p95`
              : 'Three.js · Instancing'}
          </small>
        </div>
        <div>
          <Network size={17} />
          <span>DATENEMPFANG</span>
          <strong>{client ? `${rate.toFixed(1)} KiB/s` : '—'}</strong>
          <small>Kompakte Updates · Gzip</small>
        </div>
      </div>
      <div className="lab-workspace">
        <section className="lab-map-panel">
          <div className="lab-map-toolbar">
            <div>
              <button
                disabled={focusBusy}
                className={mode === 'galaxy' ? 'selected' : ''}
                onClick={() => void focus(fleetId, 0, 'galaxy')}
              >
                <Orbit size={15} /> Galaxie
              </button>
              <button
                disabled={focusBusy || !battles.some((b) => b.state === 'active')}
                className={mode === 'battle' ? 'selected' : ''}
                onClick={() => {
                  const b = battles.find((b) => b.state === 'active');
                  if (b) void focus(ownFleets.find((f) => f.battleId === b.id)?.id || 0, b.id, 'battle');
                }}
              >
                <Crosshair size={15} /> Gefecht
              </button>
              {client && me?.id === 1 && anchor && (
                <button
                  onClick={() => {
                    void client.conn.reducers
                      .setClock({ paused: !anchor.paused, speed: anchor.speed })
                      .catch((e) => setError(String(e)));
                  }}
                >
                  {anchor.paused ? 'Fortsetzen' : 'Pause'}
                </button>
              )}
            </div>
            <span>{anchor?.paused ? 'PAUSIERT' : `${at.toFixed(1)} s SPIELZEIT`}</span>
          </div>
          {client ? (
            <LabScene client={client} mode={mode} battleId={battleId} onStats={setStats} />
          ) : (
            <div className="lab-empty">
              <Orbit size={64} strokeWidth={0.7} />
              <h2>Die nächste Größenordnung.</h2>
              <p>
                Verbinde dich mit dem lokalen Testsektor,
                <br />
                um Galaxie und Gefechte live zu prüfen.
              </p>
            </div>
          )}
          <div className="lab-map-footer">
            <span>
              {mode === 'galaxy'
                ? `${fleets.length} sichtbare Flotten · ${ships.length} geladene Schiffsdaten`
                : `${participants} einzelne Kampfteilnehmer`}
            </span>
            <span>ZIEHEN · VERSCHIEBEN &nbsp; / &nbsp; SCROLLEN · ZOOM</span>
          </div>
        </section>
        <aside className="lab-detail">
          <div className="lab-detail-title">
            IMPERIUM {me ? String(me.id).padStart(2, '0') : '—'}
            <span>{me?.ai ? 'AUTOPILOT' : 'KONTROLLE'}</span>
          </div>
          {me && (
            <>
              <div className="lab-economy">
                <span>
                  Energie<strong>{number(me.energy)}</strong>
                </span>
                <span>
                  Mineralien<strong>{number(me.minerals)}</strong>
                </span>
                <span>
                  Forschung<strong>{number(me.science)}</strong>
                </span>
              </div>
              <button
                className="lab-auto"
                onClick={() => {
                  void client!.conn.reducers
                    .setAutomation({ enabled: !me.ai })
                    .catch((e) => setError(String(e)));
                }}
              >
                {me.ai ? 'Autopilot ausschalten' : 'Autopilot einschalten'}
              </button>
            </>
          )}
          <BattleOverview
            battles={battles}
            ownerId={me?.id}
            selectedId={battleId}
            disabled={focusBusy}
            onOpen={(id) => void focus(ownFleets.find((f) => f.battleId === id)?.id || 0, id, 'battle')}
          />
          <div className="lab-section-label">
            FLOTTEN <span>{ownFleets.length}</span>
          </div>
          <div className="lab-fleet-list">
            {ownFleets.map((f) => (
              <button
                key={f.id}
                disabled={focusBusy}
                className={fleetId === f.id ? 'selected' : ''}
                onClick={() =>
                  void focus(
                    f.id,
                    mode === 'battle' ? f.battleId : 0,
                    mode === 'battle' && !f.battleId ? 'galaxy' : mode,
                  )
                }
              >
                <span className="lab-fleet-mark">▴</span>
                <span>
                  {f.name}
                  <small>
                    {f.battleId
                      ? `Gefecht ${f.battleId}`
                      : f.systemId
                        ? `System ${f.systemId}`
                        : 'Im Hyperraum'}
                  </small>
                </span>
                <strong>{f.shipCount}</strong>
              </button>
            ))}
          </div>
          {!!ships.length && (
            <div className="lab-ship-detail">
              <div className="lab-section-label">
                SCHIFFSDETAILS <span>{ships.length}</span>
              </div>
              {ships.slice(0, 3).map((s) => (
                <div key={s.id}>
                  <span>
                    {s.name}
                    <small>
                      {s.design} · {s.weapons.length} Waffen · {s.abilities.length} Fähigkeiten
                    </small>
                  </span>
                  <strong>
                    {Math.round(s.hull)}
                    <small>HÜLLE</small>
                  </strong>
                </div>
              ))}
              {ships.length > 3 && <small>+ {ships.length - 3} weitere Schiffe im Flottenabonnement</small>}
            </div>
          )}
          <div className="lab-section-label">
            LAUFENDE PROJEKTE <span>{jobs.length}</span>
          </div>
          <div className="lab-jobs">
            {jobs.slice(0, 4).map((j) => (
              <div key={j.id}>
                <span>
                  {j.kind === 'research' ? 'Extraktionsforschung' : 'Schiffskonstruktion'}
                  <small>{Math.floor((progressAt(j, at) / j.workTotal) * 100)} %</small>
                </span>
                <progress value={progressAt(j, at)} max={j.workTotal} />
              </div>
            ))}
            {!jobs.length && <p>Keine laufenden Aufträge</p>}
          </div>
        </aside>
      </div>
      <footer className="lab-notes">
        <span>
          <i /> Private Tabellen · serverseitige Sichtbarkeit · atomare Snapshots
        </span>
        <span>Lastprototyp · vereinfachte Gefechtsregeln · getrennt vom Spielsektor</span>
      </footer>
    </main>
  );
}
