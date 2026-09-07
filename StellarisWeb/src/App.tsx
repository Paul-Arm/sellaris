import { EmpireSidebar } from './EmpireSidebar';
import { ResearchAtlas } from './ResearchAtlas';
import type { ColonyEntry, InventorySelection } from './inventory-model';
import { DetailList } from './DetailList';
import { gameIndices } from './game-indices';
import { lazy, Suspense, useEffect, useRef, useState, type ReactNode } from 'react';
import {
  Activity,
  ArrowRight,
  ArrowUpRight,
  Atom,
  Check,
  ChevronDown,
  ChevronRight,
  CircleHelp,
  Compass,
  Copy,
  Cpu,
  Crosshair,
  Diamond,
  Ellipsis,
  Flag,
  FlaskConical,
  Globe2,
  Handshake,
  Hexagon,
  LoaderCircle,
  Maximize2,
  Network,
  Orbit,
  Pause,
  Play,
  Plus,
  Radio,
  Rocket,
  ScanLine,
  Send,
  Sparkles,
  Telescope,
  Users,
  Wifi,
  WifiOff,
  X,
  Zap,
} from 'lucide-react';
import { GalaxyMap } from './GalaxyMap';
import { GalaxySetup } from './GalaxySetup';
import { DEFAULT_GALAXY_SETTINGS } from '../shared/galaxySettings';
import { LabScene } from './LabScene';
import { BattleOverview } from './BattleOverview';
import { NativeFleetPanel } from './NativeFleetPanel';
import { DiplomacyPanel } from './DiplomacyPanel';
import { StoriesPanel } from './StoriesPanel';
import './backend-lab.css';
import './native-game.css';
import { useGame } from './useGame';
import { ColonyManager } from './ColonyManager';
import { ownedColonyWorlds } from '../shared/planetColonies';
import { EmpireLibrary } from './EmpireLibrary';
import { LiveEmpire } from './LiveEmpire';
import { EmpireFlag } from './EmpireFlag';
import { flagForEmpire } from '../shared/flags';
import { empireModifiers } from '../shared/empireState';
import { relationBetween } from '../shared/diplomacy';
import { baseIncome, colonyProduction } from '../shared/colonies';
import { facilityYield } from '../shared/celestial';
import { stellarWeatherFactor } from '../shared/stellarWeather';
import {
  income,
  SHIPS,
  TECHS,
  WIN_SYSTEMS,
  type Fleet,
  type GameCommand,
  type GameView,
  type Resource,
  type ShipType,
  type StarSystem,
  type TechId,
} from '../shared/game';

const SystemView = lazy(() => import('./SystemView').then((m) => ({ default: m.SystemView })));
type Modal =
  | 'multiplayer'
  | 'research'
  | 'empire'
  | 'help'
  | 'colony'
  | 'library'
  | 'fleet'
  | 'diplomacy'
  | 'stories'
  | null;
const ignoreSceneStats = () => {};
const fmt = (n: number) => Math.floor(n).toLocaleString('de-DE');
const rateFmt = (n: number) => n.toLocaleString('de-DE', { maximumFractionDigits: 1 });
const resourceIcons = { energy: Zap, minerals: Diamond, data: FlaskConical };
const resourceNames = { energy: 'Energie', minerals: 'Mineralien', data: 'Daten' };
function shipIcon(type: ShipType) {
  return type === 'scout' ? Telescope : type === 'colony' ? Globe2 : Rocket;
}
function fleetStatus(f: Fleet, game: GameView) {
  if (f.battleId) return `Gefecht ${f.battleId} · ${f.shipCount ?? 1} Schiffe`;
  if (f.task?.blocked) return 'Feindkontakt · Auftrag wartet';
  if (f.navigation?.motion.paused) return 'Feindkontakt · Flug wartet';
  if (f.route.length) return `Unterwegs nach ${game.systems.find((s) => s.id === f.route.at(-1))?.name}`;
  if (f.task)
    return f.task.type === 'scan' && f.navigation
      ? `Erkundung · ${f.navigation.visited.length}/${f.navigation.totalBodies} Körper`
      : `${f.task.type === 'scan' ? 'Untersuchung' : 'Kolonisierung'} · ${Math.ceil(f.task.remaining)} T`;
  if (f.navigation?.orders.length)
    return `Systemflug · ${f.navigation.orders.length} ${f.navigation.orders.length === 1 ? 'Auftrag' : 'Aufträge'}`;
  return game.systems.find((s) => s.id === f.systemId)?.name || 'Bereit';
}
export function App() {
  const net = useGame();
  const game = net.state;
  const [selected, setSelected] = useState('s0');
  const [selectedColony, setSelectedColony] = useState<string | null>(null);
  const [inventorySelection, setInventorySelection] = useState<InventorySelection | null>(null);
  const [inventorySection, setInventorySection] = useState<'colonies' | 'ships'>('colonies');
  const [fleetId, setFleetId] = useState<string | null>(null);
  const [mode, setMode] = useState<'galaxy' | 'system'>('galaxy');
  const [tacticalBattle, setTacticalBattle] = useState(0);
  const [modal, setModal] = useState<Modal>('library');
  const [moving, setMoving] = useState(false);
  const [focus, setFocus] = useState(0);
  const [toast, setToast] = useState('');
  const [showLog, setShowLog] = useState(false);
  const [templateId, setTemplateId] = useState('');
  const [galaxySettings, setGalaxySettings] = useState(DEFAULT_GALAXY_SETTINGS);
  const [roomCode, setRoomCode] = useState(net.invite);
  const [joining, setJoining] = useState(false);
  const [leftOpen, setLeftOpen] = useState(false);
  const previousPlayer = useRef('');
  function selectInventoryColony(colony: ColonyEntry) {
    setSelected(colony.systemId); setSelectedColony(colony.id); setMoving(false); setTacticalBattle(0);
    setInventorySelection({ systemId: colony.systemId, bodySlot: colony.world.bodySlot });
  }
  function selectInventoryFleet(fleet: Fleet) {
    setFleetId(fleet.id); setSelected(fleet.systemId); setMoving(false); setTacticalBattle(0);
    setInventorySelection({ systemId: fleet.systemId, fleetId: fleet.id });
  }
  const selectedTemplate = net.library?.empires.find((e) => e.id === templateId) || net.library?.empires[0];
  useEffect(() => {
    if (!game || previousPlayer.current === game.me.id) return;
    previousPlayer.current = game.me.id;
    setSelected(game.me.home);
    setFleetId(game.fleets.find((f) => f.owner === game.me.id && f.type === 'scout')?.id || null);
    setJoining(false);
    setModal(null);
    setMoving(false);
  }, [game]);
  useEffect(() => {
    if (net.error) setJoining(false);
  }, [net.error]);
  useEffect(() => {
    if (net.invite) {
      setRoomCode(net.invite);
      setModal('multiplayer');
    }
  }, [net.invite]);
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(''), 4000);
    return () => clearTimeout(t);
  }, [toast]);
  useEffect(() => {
    const key = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement).matches('input,textarea,select')) return;
      if (e.key === 'Escape') {
        setModal(null);
        setMoving(false);
        setShowLog(false);
      }
      if (e.code === 'Space' && !modal && game && game.hostId === game.me.id) {
        e.preventDefault();
        net.command({ type: 'pause' });
      }
      if (e.key.toLowerCase() === 'f' && !modal) setFocus((n) => n + 1);
    };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  }, [modal, game?.hostId, game?.me.id, net.command]);
  const fleet = game?.fleets.find((f) => f.id === fleetId && f.owner === game.me.id);
  const system = game?.systems.find((s) => s.id === selected);
  const nativeSystemId = net.nativeClient
    ? [...net.nativeClient.conn.db.gameAtlas.iter()].find((s) => s.externalId === selected)?.id
    : undefined;
  const activeBattle = net.battles.find((b) => b.systemId === nativeSystemId && b.state === 'active');
  const showTactics =
    !!net.nativeClient && mode === 'system' && !!activeBattle && tacticalBattle === activeBattle.id;
  useEffect(() => {
    const open = modal === 'fleet' || (mode === 'system' && !modal);
    const selectedFleet = modal === 'fleet' ? fleet?.nativeId || 0 : 0;
    void net.focusDetails(open ? selectedFleet : 0, open && showTactics ? activeBattle?.id || 0 : 0);
  }, [
    net.nativeClient,
    net.focusDetails,
    mode,
    modal,
    selected,
    fleet?.nativeId,
    fleet?.systemId,
    activeBattle?.id,
    showTactics,
  ]);
  function send(command: GameCommand) {
    net.command(command);
  }
  function move(id: string) {
    if (!fleet) {
      setToast('Wähle zuerst links eine eigene Flotte aus.');
      return;
    }
    send({ type: 'move', fleetId: fleet.id, systemId: id });
    setMoving(false);
  }
  function select(id: string) {
    if (moving) move(id);
    setSelected(id);
  }
  async function copyInvite() {
    if (!game) return;
    const url = `${location.origin}${location.pathname}?room=${game.code}`;
    try {
      await navigator.clipboard.writeText(url);
      setToast('Einladungslink kopiert.');
    } catch {
      setToast('Kopiere den Raumcode oder die Adresse aus der Adresszeile.');
    }
  }
  const ownFleets = game?.fleets.filter((f) => f.owner === game.me.id) || [];
  const colonies = game?.systems.filter((s) => s.owner === game.me.id) || [];
  const rates = game ? income(game, game.me) : { energy: 0, minerals: 0, data: 0 };
  const date = new Date(Date.UTC(2200, 0, 1 + Math.floor(game?.tick || 0)))
    .toISOString()
    .slice(0, 10)
    .replaceAll('-', '.');
  return (
    <div className={`app-shell ${game?.backend === 'spacetimedb' ? 'native-game' : ''}`}>
      <aside className="rail">
        <button
          className="brand-symbol"
          onClick={() => {
            setMode('galaxy');
            setSelected(game?.me.home || 's0');
            setFocus((n) => n + 1);
          }}
          aria-label="Zur Heimatwelt"
        >
          <Orbit size={31} strokeWidth={1.3} />
        </button>
        <div className="rail-rule" />
        <nav aria-label="Hauptnavigation">
          <button
            title="Serververwaltung"
            aria-label="Serververwaltung"
            onClick={() => window.open('/admin', '_blank', 'noopener')}
          >
            <Network size={20} />
          </button>
          <button
            className={modal === 'library' ? 'active' : ''}
            title="Reiche und Spezies"
            aria-label="Reiche und Spezies"
            onClick={() => setModal('library')}
          >
            <Flag size={21} />
          </button>
          <button
            className={!modal ? 'active' : ''}
            title="Galaxiekarte"
            aria-label="Galaxiekarte"
            onClick={() => {
              setModal(null);
              setMode('galaxy');
            }}
          >
            <Network size={21} />
          </button>
          <button
            className={modal === 'empire' ? 'active' : ''}
            title="Reichsübersicht"
            aria-label="Reichsübersicht"
            onClick={() => setModal(game ? 'empire' : 'library')}
          >
            <Hexagon size={21} />
          </button>
          <button
            className={modal === 'colony' ? 'active' : ''}
            title="Kolonien verwalten"
            aria-label="Kolonien verwalten"
            onClick={() => {
              if (game && system?.owner !== game.me.id) setSelected(game.me.home);
              setModal('colony');
            }}
          >
            <Globe2 size={21} />
          </button>
          <button
            title="Flotten"
            aria-label="Flotten"
            onClick={() => {
              if (game) { setInventorySection('ships'); setLeftOpen(true); setModal(null); }
            }}
          >
            <Rocket size={21} />
          </button>
          <button
            className={modal === 'research' ? 'active' : ''}
            title="Forschung"
            aria-label="Forschung"
            onClick={() => setModal('research')}
          >
            <Atom size={22} />
            {!!game?.me.research.projects.length && <i className="rail-dot" />}
          </button>
          <button
            className={modal === 'diplomacy' ? 'active' : ''}
            title="Diplomatie"
            aria-label="Diplomatie"
            disabled={!game}
            onClick={() => setModal('diplomacy')}
          >
            <Handshake size={21} />
            {game?.offers?.some((o) => o.empireB === game.me.id && o.status === 'pending') && (
              <i className="rail-dot green" />
            )}
          </button>
          <button
            className={modal === 'stories' ? 'active' : ''}
            title="Lagezentrum"
            aria-label="Lagezentrum"
            disabled={!game}
            onClick={() => setModal('stories')}
          >
            <Radio size={21} />
            {game?.decisions?.some((d) => d.phase === 'pending') && <i className="rail-dot green" />}
          </button>
        </nav>
        <div className="rail-bottom">
          <button title="Multiplayer" aria-label="Multiplayer" onClick={() => setModal('multiplayer')}>
            <Users size={20} />
            <i className="rail-dot green" />
          </button>
          <button title="Spielanleitung" aria-label="Spielanleitung" onClick={() => setModal('help')}>
            <CircleHelp size={20} />
          </button>
          <button
            title="Designhangar"
            aria-label="Designhangar"
            onClick={() => window.open('/models', '_blank', 'noopener')}
          >
            <Rocket size={20} />
          </button>
          <span className="version">α 0.2</span>
        </div>
      </aside>
      <header className="topbar">
        <div className="resources">
          {(['energy', 'minerals', 'data'] as Resource[]).map((r) => {
            const Icon = resourceIcons[r];
            return (
              <button
                className={`resource ${r}`}
                key={r}
                title={`${resourceNames[r]} · +${rates[r].toLocaleString('de-DE', { maximumFractionDigits: 2 })} pro 4 Spieltage`}
                onClick={() => setModal('empire')}
                aria-label={`${resourceNames[r]}: Wirtschaftsübersicht öffnen`}
              >
                <Icon size={17} strokeWidth={1.6} />
                <div>
                  <strong>{fmt(game?.me.resources[r] || 0)}</strong>
                  <span>+{rateFmt(rates[r])}</span>
                </div>
              </button>
            );
          })}
          <button className="resource compute" title="Verfügbare Rechenleistung pro Spieltag" aria-label="Compute: Forschungslandkarte öffnen" onClick={() => setModal('research')}>
            <Cpu size={17} /><strong>{fmt(game?.me.compute || 0)}</strong><span>Compute</span>
          </button>
          <div
            className="resource fleet-resource"
            title={`${ownFleets.reduce((n, f) => n + (f.shipCount ?? 1), 0)} eigene Schiffe in ${ownFleets.length} Flotten`}
          >
            <Rocket size={17} />
            <strong>{ownFleets.length}</strong>
            <span>Flotten</span>
          </div>
        </div>
        {game && (
          <div className="time-control">
            <div>
              <span className="eyebrow">STERNZEIT</span>
              <strong>{date}</strong>
            </div>
            <button
              className="icon-button"
              onClick={() => send({ type: 'pause' })}
              disabled={game.hostId !== game.me.id || !!game.winner}
              aria-label={game.paused ? 'Simulation fortsetzen' : 'Simulation pausieren'}
              title={game.hostId === game.me.id ? 'Pause · Leertaste' : 'Zeitsteuerung durch den Host'}
            >
              {game.paused ? <Play size={15} /> : <Pause size={15} />}
            </button>
            <button
              className="speed-button"
              disabled={game.hostId !== game.me.id || !!game.winner}
              onClick={() => send({ type: 'speed', value: (game.speed % 3) + 1 })}
            >
              {game.speed}×<ChevronRight size={11} />
            </button>
          </div>
        )}
      </header>
      <main className={`command-deck ${mode === 'system' ? 'system-deck' : ''}`}>
        {game && system ? (
          <>
            {showTactics ? (
              <div className="native-battle-map">
                <LabScene
                  client={net.nativeClient!}
                  mode="battle"
                  battleId={activeBattle!.id}
                  onStats={ignoreSceneStats}
                />
                <button className="secondary-button native-back-map" onClick={() => setTacticalBattle(0)}>
                  <Orbit size={14} /> Zum System
                </button>
              </div>
            ) : mode === 'system' ? (
              <Suspense fallback={<div className="system-loading">Systemansicht wird geladen …</div>}>
                <SystemView
                  client={net.nativeClient}
                  key={system.id}
                  game={game}
                  system={system}
                  fleetId={fleetId}
                  inventorySelection={inventorySelection}
                  command={send}
                  connected={net.connected}
                  onFleet={setFleetId}
                  onNavigate={(id) => {
                    setSelected(id);
                    setTacticalBattle(0);
                  }}
                  onBack={() => {
                    setMode('galaxy');
                    setTacticalBattle(0);
                  }}
                  onColony={(id) => {
                    setSelectedColony(id || selected);
                    setModal('colony');
                  }}
                  onFleetDetails={() => setModal('fleet')}
                  onCourse={() => {
                    setMode('galaxy');
                    setMoving(true);
                  }}
                  onBattle={activeBattle ? () => setTacticalBattle(activeBattle.id) : undefined}
                />
              </Suspense>
            ) : (
              <GalaxyMap
                game={game}
                selected={selected}
                fleetId={fleetId}
                onSelect={select}
                onFleet={setFleetId}
                onMove={move}
                mode={mode}
                setMode={setMode}
                moving={moving}
                focus={focus}
              />
            )}
            {mode === 'system' && (
              <div className="map-heading">
                <h1>{system.name}</h1>
              </div>
            )}
            {game.paused && (
              <div className="paused-label">
                <Pause size={12} /> SIMULATION PAUSIERT
              </div>
            )}
            <EmpireSidebar game={game} open={leftOpen} selectedColony={selectedColony || selected} selectedFleet={fleetId}
                onColony={selectInventoryColony}
                onFleet={selectInventoryFleet}
                onOpenColony={(colony) => { setSelected(colony.systemId); setSelectedColony(colony.id); setModal('colony'); }}
                onOpenFleet={(fleet) => { setFleetId(fleet.id); setModal('fleet'); }}
                section={inventorySection} onSection={setInventorySection}
                onStories={() => setModal('stories')} onLog={() => setShowLog(!showLog)} />
            {mode === 'galaxy' && (
              <aside className="right-panel">
                <SystemPanel
                  game={game}
                  system={system}
                  fleet={fleet}
                  send={send}
                  onMode={() => setMode(mode === 'galaxy' ? 'system' : 'galaxy')}
                  onFleet={setFleetId}
                  onMove={() => move(system.id)}
                  onColony={() => {
                    setSelectedColony(selected);
                    setModal('colony');
                  }}
                />
                <div className="sector-card">
                  <svg viewBox="0 0 250 108" aria-label="Sektorminimap">
                    {game.links.map(([a, b]) => {
                      const x = gameIndices(game).systems.get(a)!,
                        y = gameIndices(game).systems.get(b)!;
                      return (
                        <line
                          key={a + b}
                          x1={x.x / 7}
                          y1={x.y / 11}
                          x2={y.x / 7}
                          y2={y.y / 11}
                          stroke="#747997"
                          strokeOpacity=".2"
                          strokeWidth=".6"
                        />
                      );
                    })}
                    {game.systems.map((s) => (
                      <circle
                        key={s.id}
                        cx={s.x / 7}
                        cy={s.y / 11}
                        r={s.id === selected ? 3 : s.owner ? 2 : 1}
                        fill={
                          s.id === selected
                            ? '#d7d0ff'
                            : s.owner
                              ? game.players.find((p) => p.id === s.owner)?.color
                              : '#566176'
                        }
                      />
                    ))}
                  </svg>
                  <div className="map-legend">
                    <span>
                      <i className="legend-dot purple" />
                      Dein Imperium
                    </span>
                    <span>
                      <i className="legend-dot" />
                      Unabhängig
                    </span>
                  </div>
                </div>
              </aside>
            )}
            {net.nativeClient && net.battles.length > 0 && mode === 'galaxy' && (
              <div className="native-battle-summary">
                <BattleOverview
                  battles={net.battles}
                  systemNames={new Map([...net.nativeClient.conn.db.star.iter()].map((s) => [s.id, s.name]))}
                  empireNames={
                    new Map([...net.nativeClient.conn.db.empireSummary.iter()].map((p) => [p.id, p.name]))
                  }
                  ownerId={[...net.nativeClient.conn.db.myEmpire.iter()][0]?.id}
                  selectedId={showTactics ? activeBattle!.id : 0}
                  disabled={false}
                  onOpen={(id) => {
                    const b = net.battles.find((b) => b.id === id)!;
                    const s = net.nativeClient!.conn.db.gameAtlas.id.find(b.systemId);
                    if (s) {
                      setSelected(s.externalId);
                      setMode('system');
                      setTacticalBattle(id);
                      setModal(null);
                    }
                  }}
                />
              </div>
            )}
            {fleet && mode === 'galaxy' && (
              <div className={`fleet-command ${moving ? 'choosing' : ''}`}>
                <span className="fleet-command-icon">
                  <Rocket size={19} />
                </span>
                <div>
                  <span className="eyebrow">{moving ? 'ZIELSYSTEM AUSWÄHLEN' : 'AUSGEWÄHLTE FLOTTE'}</span>
                  <strong>{fleet.name}</strong>
                </div>
                <span className="command-divider" />
                <div className="fleet-hull">
                  <span>Hülle</span>
                  <strong>{Math.ceil(fleet.hp)}%</strong>
                </div>
                <button
                  className={moving ? 'secondary-button' : 'primary-button'}
                  disabled={fleet.route.length > 0 || !!fleet.task || !!fleet.battleId || !!game.winner}
                  onClick={() => {
                    setMode('galaxy');
                    setMoving(!moving);
                  }}
                >
                  {moving ? <X size={14} /> : <Send size={14} />} {moving ? 'Abbrechen' : 'Kurs setzen'}
                </button>
                {net.nativeClient && (
                  <button className="secondary-button" onClick={() => setModal('fleet')}>
                    Verband verwalten
                  </button>
                )}
              </div>
            )}
            {moving && (
              <div className="move-hint">
                <Crosshair size={14} /> Wähle ein Ziel auf der Karte <kbd>ESC</kbd>
              </div>
            )}
            {showLog && (
              <div className="log-panel floating-panel">
                <div className="modal-heading">
                  <div>
                    <span className="eyebrow">SUBRAUMFUNK</span>
                    <h2>Ereignisprotokoll</h2>
                  </div>
                  <button
                    className="icon-button"
                    onClick={() => setShowLog(false)}
                    aria-label="Ereignisprotokoll schließen"
                  >
                    <X size={18} />
                  </button>
                </div>
                {game.log.map((l) => (
                  <div className={`full-log ${l.tone}`} key={l.id}>
                    <span>{Math.floor(l.tick).toString().padStart(4, '0')}</span>
                    <p>{l.text}</p>
                  </div>
                ))}
              </div>
            )}
            {!game.winner && colonies.length === 0 && !ownFleets.some((f) => f.type === 'colony') && (
              <div className="victory-banner defeat-banner" role="status">
                <Activity size={24} />
                <div>
                  <strong>Unsere letzte Welt ist gefallen.</strong>
                  <span>Ohne Kolonie oder Kolonieschiff kann dein Imperium nicht zurückkehren.</span>
                </div>
                <button className="secondary-button" onClick={() => setModal('multiplayer')}>
                  Neue Expedition
                  <ArrowRight size={15} />
                </button>
              </div>
            )}
            {game.winner && (
              <div className="victory-banner">
                <Sparkles size={24} />
                <div>
                  <strong>{game.players.find((p) => p.id === game.winner)?.name} gewinnt den Sektor</strong>
                  <span>Acht Welten. Eine neue Zivilisation.</span>
                </div>
                <button className="primary-button" onClick={() => setModal('multiplayer')}>
                  Neue Expedition <ArrowRight size={15} />
                </button>
              </div>
            )}
          </>
        ) : (
          <div className="connecting-screen">
            <Orbit size={70} strokeWidth={0.7} />
            <h1>{net.connected ? 'Ein neuer Horizont wartet.' : 'Verbindung zum Sternennetz'}</h1>
            <p>
              {net.invite
                ? 'Tritt dem Sektor bei und gründe dein Imperium.'
                : net.connected
                  ? 'Entwirf dein Reich und beginne eine neue Expedition.'
                  : 'Die Verbindung wird hergestellt …'}
            </p>
            {net.invite ? (
              <button className="primary-button" onClick={() => setModal('multiplayer')}>
                Sektor beitreten <ArrowRight size={16} />
              </button>
            ) : net.connected ? (
              <button className="primary-button" onClick={() => setModal('library')}>
                Reiche und Spezies <ArrowRight size={16} />
              </button>
            ) : (
              <LoaderCircle className="spin" size={22} />
            )}
          </div>
        )}
      </main>
      <footer className="statusbar">
        <div>
          <span className={`status-dot ${net.connected ? '' : 'offline'}`} />
          {net.connected ? 'SERVER VERBUNDEN' : 'VERBINDUNG WIRD HERGESTELLT'}
          <span className="footer-divider" />
          {net.connected ? <Wifi size={11} /> : <WifiOff size={11} />} {net.latency || '—'} ms
        </div>
      </footer>
      {(toast || net.error) && (
        <div className={`toast ${net.error ? 'error' : ''}`} role={net.error ? 'alert' : 'status'}>
          {net.error ? <Activity size={17} /> : <Check size={17} />}
          <span>{net.error || toast}</span>
          <button
            className="icon-button"
            aria-label="Meldung schließen"
            onClick={() => {
              setToast('');
              net.setError('');
            }}
          >
            <X size={14} />
          </button>
        </div>
      )}
      {modal && (
        <Dialog onClose={() => setModal(null)}>
          {modal === 'library' && (
            <EmpireLibrary
              library={net.library}
              connected={net.connected}
              mutate={net.mutateLibrary}
              onUse={(id) => {
                setTemplateId(id);
                setModal('multiplayer');
              }}
            />
          )}
          {modal === 'stories' && game && (
            <StoriesPanel
              game={game}
              command={net.command}
              connected={net.connected}
              onFocus={(id) => {
                setSelected(id);
                setFocus((n) => n + 1);
                setMode('galaxy');
                setModal(null);
              }}
            />
          )}
          {modal === 'diplomacy' && game && (
            <DiplomacyPanel game={game} command={net.command} connected={net.connected} />
          )}
          {modal === 'colony' && game && (
            <ColonyManager
              game={game}
              selected={selectedColony || selected}
              onSelect={setSelectedColony}
              command={send}
              connected={net.connected}
            />
          )}
          {modal === 'fleet' &&
            game &&
            net.nativeClient &&
            (fleet ? (
              <NativeFleetPanel client={net.nativeClient} game={game} fleet={fleet} onError={net.setError} />
            ) : (
              <>
                <h2 id="dialog-title">Verband aufgelöst</h2>
                <p>Wähle eine andere Flotte.</p>
              </>
            ))}
          {modal === 'multiplayer' && (
            <>
              <ModalTitle
                eyebrow="GEMEINSAM INS UNBEKANNTE"
                title="Dein Sektor. Eure Geschichte."
                icon={<Users size={24} />}
              />
              <p className="modal-intro">
                Bis zu 25 Imperien. Wähle die Gestalt deiner Galaxie oder tritt einem bestehenden Sektor bei.
              </p>
              {game && (
                <div className="room-display">
                  <div>
                    <span className="eyebrow">AKTUELLER RAUMCODE</span>
                    <strong>{game.code}</strong>
                  </div>
                  <button className="secondary-button" onClick={copyInvite}>
                    <Copy size={14} />
                    Einladung kopieren
                  </button>
                </div>
              )}
              {game && (
                <div className="player-list">
                  {game.players.map((p) => (
                    <div key={p.id}>
                      <span className="player-avatar" style={{ color: p.color, background: p.color + '12' }}>
                        <EmpireFlag flag={p.flag ?? flagForEmpire(p)} width={32} />
                      </span>
                      <strong>
                        {p.name}
                        {p.id === game.me.id && <small>DU</small>}
                        {p.ai && <small>KI</small>}
                      </strong>
                      <span className={`status-dot ${p.online || p.ai ? '' : 'offline'}`} />
                      <span>{p.ai ? 'Autonom' : p.online ? 'Online' : 'Offline'}</span>
                    </div>
                  ))}
                </div>
              )}
              {game && (
                <div className="ai-lobby-card">
                  <div>
                    <Cpu size={22} />
                    <span>
                      <strong>Ein Rivale zwischen den Sternen</strong>
                      <small>
                        Erkundet, kolonisiert und baut Flotten. Nutzt dieselben Ressourcen und Spielregeln.
                      </small>
                    </span>
                  </div>
                  <button
                    className="secondary-button"
                    disabled={
                      game.hostId !== game.me.id ||
                      game.players.length >= (game.capacity || 4) ||
                      !!game.winner
                    }
                    onClick={() => send({ type: 'add_ai' })}
                  >
                    <Plus size={14} /> KI-Imperium hinzufügen
                  </button>
                  <p>
                    {game.hostId !== game.me.id
                      ? 'Nur der Host kann einen KI-Gegner hinzufügen.'
                      : game.players.length >= (game.capacity || 4)
                        ? 'Alle Imperiumsplätze sind belegt.'
                        : 'Belegt einen Spielerplatz. Offensiven gegen andere Imperien beginnen frühestens nach 150 Spieltagen.'}
                  </p>
                </div>
              )}
              <div className="form-divider" />
              <label className="archive-field" htmlFor="empire-template">
                <span>REICHSVORLAGE FÜR DEINE EXPEDITION</span>
                <select
                  id="empire-template"
                  value={selectedTemplate?.id || ''}
                  onChange={(e) => setTemplateId(e.target.value)}
                >
                  {!net.library?.empires.length && (
                    <option value="">Zuerst eine Reichsvorlage erstellen</option>
                  )}
                  {net.library?.empires.map((empire) => (
                    <option key={empire.id} value={empire.id}>
                      {empire.name} · Revision {empire.revision}
                    </option>
                  ))}
                </select>
              </label>
              <button type="button" className="secondary-button" onClick={() => setModal('library')}>
                <Flag size={14} />
                Reiche und Spezies bearbeiten
              </button>
              <p className="fine-print">
                Deine Vorlage wird beim Beitritt kopiert. Regierung, Bevölkerung und Spezies entwickeln sich
                anschließend in dieser Partie weiter.
              </p>
              <label className="field-label" htmlFor="room-code">
                EINEM SEKTOR BEITRETEN
              </label>
              <form
                className="join-form"
                onSubmit={(e) => {
                  e.preventDefault();
                  setJoining(true);
                  if (selectedTemplate) net.join(selectedTemplate.id, roomCode);
                }}
              >
                <input
                  id="room-code"
                  maxLength={6}
                  value={roomCode}
                  onChange={(e) => setRoomCode(e.target.value.toUpperCase())}
                  placeholder="6-stelliger Raumcode"
                  pattern="[A-Fa-f0-9]{6}"
                  required
                />
                <button
                  className="primary-button"
                  disabled={
                    !net.connected ||
                    joining ||
                    roomCode.length !== 6 ||
                    roomCode === game?.code ||
                    !selectedTemplate
                  }
                >
                  {joining ? <LoaderCircle className="spin" size={14} /> : <ArrowRight size={14} />}Beitreten
                </button>
              </form>
              <GalaxySetup value={galaxySettings} onChange={setGalaxySettings} disabled={joining} />
              <button
                className="new-sector-button"
                disabled={!net.connected || joining || !selectedTemplate}
                onClick={() => {
                  setJoining(true);
                  if (selectedTemplate) net.create(selectedTemplate.id, galaxySettings);
                }}
              >
                <Plus size={15} /> Neuen Sektor erstellen
              </button>
              <p className="fine-print">
                Der Host steuert Pause und Tempo. Leere Sektoren pausieren automatisch. Über die Serveradresse
                können weitere Geräte beitreten.
              </p>
            </>
          )}
          {modal === 'research' && game && (<ResearchAtlas game={game} command={send} connected={net.connected} />)}
          {modal === 'empire' && game && (
            <>
              <ModalTitle
                eyebrow="DEIN PLATZ IN DER GALAXIE"
                title={game.me.name}
                icon={<Orbit size={25} />}
              />
              {game.me.empire && (
                <LiveEmpire key={`${game.me.id}-${game.me.empire.revision}`} game={game} command={send} />
              )}
              <div className="empire-stats">
                <div>
                  <strong>{colonies.length}</strong>
                  <span>Kolonien</span>
                </div>
                <div>
                  <strong>{ownFleets.length}</strong>
                  <span>Schiffe</span>
                </div>
                <div>
                  <strong>{game.me.surveyed.length}</strong>
                  <span>Untersuchte Systeme</span>
                </div>
                <div>
                  <strong>{game.me.techs.length}/3</strong>
                  <span>Technologien</span>
                </div>
              </div>
              <h3 className="modal-subtitle">
                Produktion pro Zyklus <span>4 Spieltage</span>
              </h3>
              <div className="economy-table">
                <div className="economy-base">
                  <strong>Reichsgrundversorgung</strong>
                  {(['energy', 'minerals', 'data'] as Resource[]).map((r) => {
                    const Icon = resourceIcons[r];
                    return (
                      <span key={r}>
                        <Icon size={13} />+{rateFmt(baseIncome(game.me)[r])}
                      </span>
                    );
                  })}
                </div>
                {ownedColonyWorlds(game).map((s) => (
                  <div key={s.worldId}>
                    <strong>
                      <button
                        className="economy-colony-link"
                        onClick={() => {
                          setSelected(s.id);
                          setSelectedColony(s.worldId);
                          setModal('colony');
                        }}
                      >
                        {s.colonyName || s.name}
                        <ArrowUpRight size={12} />
                      </button>
                    </strong>
                    {(['energy', 'minerals', 'data'] as Resource[]).map((r) => {
                      const Icon = resourceIcons[r];
                      return (
                        <span key={r}>
                          <Icon size={13} />+{rateFmt(colonyProduction(s, game.me)[r])}
                        </span>
                      );
                    })}
                  </div>
                ))}
                {!!game.sites?.some((s) => s.owner === game.me.id && s.level > 0) && (
                  <div className="economy-base">
                    <strong>Systemanlagen</strong>
                    {(['energy', 'minerals', 'data'] as Resource[]).map((r) => {
                      const Icon = resourceIcons[r];
                      return (
                        <span key={r}>
                          <Icon size={13} />+{rateFmt(game.me.installationIncome?.[r] || 0)}
                        </span>
                      );
                    })}
                  </div>
                )}
                <div className="economy-total">
                  <strong>Gesamtertrag</strong>
                  {(['energy', 'minerals', 'data'] as Resource[]).map((r) => {
                    const Icon = resourceIcons[r];
                    return (
                      <span key={r}>
                        <Icon size={13} />+{rateFmt(rates[r])}
                      </span>
                    );
                  })}
                </div>
              </div>
              <p className="fine-print">
                Inklusive Bergbaustationen, Kolonieausbauten, Produktionsschwerpunkten und Technologien.
                Klicke auf eine Kolonie, um sie zu verwalten.
              </p>
              <h3 className="modal-subtitle">Imperien im Sektor</h3>
              <div className="leaderboard">
                {[...game.players]
                  .sort((a, b) => b.colonies - a.colonies)
                  .map((p, i) => (
                    <div key={p.id}>
                      <span>0{i + 1}</span>
                      <strong style={{ color: p.color }}>
                        <EmpireFlag flag={p.flag ?? flagForEmpire(p)} width={24} />
                        {p.name}
                        {p.ai && <span className="ai-tag">KI</span>}
                      </strong>
                      <span>
                        {p.colonies} / {WIN_SYSTEMS} Systeme
                      </span>
                    </div>
                  ))}
              </div>
            </>
          )}
          {modal === 'help' && (
            <>
              <ModalTitle
                eyebrow="WILLKOMMEN, KOMMANDANT"
                title="Die Sterne warten auf dich."
                icon={<Compass size={25} />}
              />
              <p className="modal-intro">
                Baue dein Imperium aus und kontrolliere als Erster acht Systeme. Du startest mit einer Kolonie
                und drei Schiffen.
              </p>
              <div className="guide-steps">
                {[
                  [
                    '01',
                    'Entdecke',
                    'Wähle ISS Horizon links aus. Klicke auf „Kurs setzen“ und dann auf Alpha Centauri. Nach der Ankunft: „System untersuchen“.',
                  ],
                  [
                    '02',
                    'Expandierte Grenzen',
                    'Schicke ISS Genesis in das untersuchte System. „Kolonie gründen“ kostet 80 Energie + 80 Mineralien und verbraucht das Kolonieschiff.',
                  ],
                  [
                    '03',
                    'Eine blühende Zivilisation',
                    'Öffne „Kolonie verwalten“. Baue Reaktoren, Industrie, Labore und Schildbastionen. Ein Schwerpunkt erhöht den gewählten Ertrag um 40 % und senkt die anderen um 15 %.',
                  ],
                  [
                    '04',
                    'Behaupte dich',
                    'Korvetten kämpfen gegen Wächter und Reiche, denen du in der Diplomatie den Krieg erklärt hast. Frieden beendet gemeinsame Gefechte; Handelsangebote tauschen Rohstoffe.',
                  ],
                ].map(([n, t, d]) => (
                  <div key={n}>
                    <span>{n}</span>
                    <div>
                      <h3>{t}</h3>
                      <p>{d}</p>
                    </div>
                  </div>
                ))}
              </div>
              <div className="keyboard-guide">
                <span>
                  <kbd>Scroll</kbd> Zoom
                </span>
                <span>
                  <kbd>F</kbd> Auswahl zentrieren
                </span>
                <span>
                  <kbd>Space</kbd> Pause als Host
                </span>
                <span>
                  <kbd>ESC</kbd> Abbrechen
                </span>
              </div>
              <p className="fine-print">
                Die Sternenkarte ist bekannt. Systemerträge werden durch Untersuchung sichtbar; fremde Schiffe
                nur bei eigenen Kolonien oder Flotten. Anomalien liefern zusätzliche Daten. Im
                Multiplayer-Dialog kann der Host KI-Imperien hinzufügen. Eigene Kolonien reparieren Schiffe,
                solange keine Feinde im System sind.
              </p>
            </>
          )}
        </Dialog>
      )}
    </div>
  );
}
function SystemPanel({
  game,
  system: s,
  fleet,
  send,
  onMode,
  onFleet,
  onMove,
  onColony,
}: {
  game: GameView;
  system: StarSystem;
  fleet?: Fleet;
  send: (c: GameCommand) => void;
  onMode: () => void;
  onFleet: (id: string) => void;
  onMove: () => void;
  onColony: () => void;
}) {
  const surveyed = game.me.surveyed.includes(s.id),
    own = s.owner === game.me.id;
  const atSystem = fleet?.systemId === s.id && !fleet.route.length && !fleet.task;
  const here = game.fleets.filter((f) => f.owner === game.me.id && f.systemId === s.id && !f.route.length);
  const [yardOpen, setYardOpen] = useState(false);
  useEffect(() => setYardOpen(false), [s.id]);
  const selectedTask = fleet?.systemId === s.id ? fleet.task : null;
  const production = own ? colonyProduction(s, game.me) : s.resources;
  if (own)
    for (const site of game.sites || []) {
      if (site.systemId !== s.id || site.owner !== game.me.id || site.suspended) continue;
      const rate = facilityYield(
        site.facility,
        site.level,
        (s.productionFactor ?? 1) * stellarWeatherFactor(site.facility, s.stellarWeather, game.tick),
      );
      production.energy += rate.energy;
      production.minerals += rate.minerals;
      production.data += rate.data;
    }
  return (
    <div className="system-panel">
      <div className="system-panel-top">
        <span className="eyebrow">SYSTEM</span>
        <button className="icon-button" onClick={onMode} aria-label="Systemansicht umschalten">
          <Maximize2 size={13} />
        </button>
      </div>
      <div className="system-title">
        <div className="system-sun" style={{ '--sun-color': s.color } as React.CSSProperties} />
        <div>
          <h2>{s.name}</h2>
          <span>{s.kind === 'star' ? `${s.class} · ${s.planet}` : s.class}</span>
        </div>
      </div>
      <div className="system-badges">
        <span className={own ? 'badge purple' : 'badge'}>
          {own ? <Flag size={10} /> : <Hexagon size={10} />}{' '}
          {own ? 'EIGEN' : s.owner ? 'FREMD' : 'UNABHÄNGIG'}
        </span>
        <span className={`survey-status ${surveyed ? 'surveyed' : ''}`}>
          {surveyed ? <Check size={10} /> : <ScanLine size={10} />} {surveyed ? 'Untersucht' : 'Untersuchen'}
        </span>
      </div>
      <div className="system-facts">
        <div>
          <span>{s.kind === 'star' ? 'Welttyp' : 'Phänomen'}</span>
          <strong>{s.planet}</strong>
        </div>
        <div>
          <span>{s.kind === 'star' ? 'Status' : 'Forschungswert'}</span>
          <strong className={own ? 'mint' : ''}>
            {own
              ? 'Kolonie etabliert'
              : s.defense > 0 && !s.owner
                ? 'Wächterpräsenz'
                : s.kind !== 'star'
                  ? s.studied
                    ? 'Untersucht'
                    : '+90 Daten'
                  : surveyed
                    ? 'Zur Kolonisierung bereit'
                    : 'Unbekanntes System'}
          </strong>
        </div>
        {s.defense > 0 && (
          <div>
            <span>Verteidigung</span>
            <strong>{Math.ceil(s.defense)}</strong>
          </div>
        )}
      </div>
      <div className="system-production">
        <span className="eyebrow">{own ? 'SYSTEMPRODUKTION' : 'RESSOURCENVORKOMMEN'}</span>
        <div>
          {(['energy', 'minerals', 'data'] as Resource[]).map((r) => {
            const Icon = resourceIcons[r];
            return (
              <span key={r} className={r}>
                <Icon size={15} />
                <strong>{surveyed || own ? `+${rateFmt(production[r])}` : '?'}</strong>
              </span>
            );
          })}
        </div>
      </div>
      {s.anomaly && !s.studied && (
        <div className="anomaly-note">
          <Sparkles size={15} />
          <div>
            <strong>Anomalie</strong>
            <span>Forschungsschiff zur Untersuchung benötigt</span>
          </div>
        </div>
      )}
      <div className="system-actions">
        {selectedTask && (
          <div className="task-progress">
            <span>
              {selectedTask.blocked
                ? 'Feindkontakt · Auftrag wartet'
                : selectedTask.type === 'scan'
                  ? 'System wird untersucht'
                  : 'Kolonie wird gegründet'}{' '}
              <b>{Math.ceil(selectedTask.remaining)} T</b>
            </span>
            <Progress value={() => 1 - selectedTask.remaining / selectedTask.total} />
          </div>
        )}
        {fleet && fleet.systemId !== s.id && (
          <button
            className="primary-button wide"
            disabled={!!fleet.route.length || !!fleet.task || !!game.winner}
            onClick={onMove}
          >
            <Send size={14} /> Flotte hierher entsenden <ArrowRight size={14} />
          </button>
        )}
        {!surveyed && (
          <button
            className="primary-button wide"
            disabled={
              !atSystem ||
              fleet?.type !== 'scout' ||
              (s.defense > 0 &&
                s.owner !== game.me.id &&
                (!s.owner || relationBetween(game.relations || [], game.me.id, s.owner)?.state === 'war')) ||
              !!game.winner
            }
            onClick={() => send({ type: 'scan', fleetId: fleet!.id })}
          >
            <ScanLine size={15} /> Alle Himmelskörper erkunden
          </button>
        )}
        {!own && !s.owner && s.kind === 'star' && (
          <button
            className="secondary-button wide"
            disabled={
              !atSystem ||
              fleet?.type !== 'colony' ||
              !surveyed ||
              s.defense > 0 ||
              game.me.resources.energy < 80 ||
              game.me.resources.minerals < 80 ||
              !!game.winner
            }
            onClick={() => send({ type: 'colonize', fleetId: fleet!.id })}
          >
            <Flag size={14} /> Kolonie gründen{' '}
            <span>
              80 <Zap size={10} /> 80 <Diamond size={10} />
            </span>
          </button>
        )}
        {!own && (!fleet || !atSystem) && !selectedTask && (
          <p className="action-hint">
            {fleet?.route.length
              ? 'Deine Flotte ist unterwegs.'
              : !surveyed
                ? 'Schicke ein Forschungsschiff in dieses System.'
                : s.kind === 'star'
                  ? 'Ein Kolonieschiff kann hier eine neue Welt gründen.'
                  : 'Schicke ein Forschungsschiff zur Anomalie.'}
          </p>
        )}
        {own && (
          <>
            <button className="primary-button wide colony-manage-button" onClick={onColony}>
              <Globe2 size={14} />
              Kolonie verwalten
              <span>
                <ArrowUpRight size={14} />
              </span>
            </button>
            {s.colony?.construction && (
              <div className="colony-mini-project">
                <span>Planetarer Ausbau läuft</span>
                <strong>
                  {Math.ceil(
                    s.colony.construction.remaining /
                      Math.max(0.1, 1 + empireModifiers(game.me.empire).construction),
                  )}{' '}
                  s
                </strong>
                <Progress
                  value={() => 1 - s.colony!.construction!.remaining / s.colony!.construction!.total}
                />
              </div>
            )}
            <button className="primary-button wide" onClick={() => setYardOpen(!yardOpen)}>
              <Rocket size={14} /> Raumwerft{' '}
              <span>{yardOpen ? <ChevronDown size={14} /> : <Plus size={14} />}</span>
            </button>
            {yardOpen && (
              <div className="shipyard">
                {(Object.keys(SHIPS) as ShipType[]).map((type) => {
                  const ship = SHIPS[type];
                  const Icon = shipIcon(type);
                  return (
                    <button
                      key={type}
                      disabled={
                        game.me.resources.energy < ship.cost.energy ||
                        game.me.resources.minerals < ship.cost.minerals ||
                        game.me.queue.length >= 5 ||
                        !!game.winner
                      }
                      onClick={() => send({ type: 'build', ship: type, systemId: s.id })}
                    >
                      <Icon size={16} />
                      <div>
                        <strong>{ship.name}</strong>
                        <span>
                          {ship.cost.energy} Energie · {ship.cost.minerals} Mineralien ·{' '}
                          {Math.ceil(
                            ship.time / Math.max(0.1, 1 + empireModifiers(game.me.empire).construction),
                          )}{' '}
                          s
                        </span>
                      </div>
                      <Plus size={14} />
                    </button>
                  );
                })}
              </div>
            )}
            <button className="secondary-button wide" onClick={onMode}>
              <Diamond size={14} /> Bergbau im System verwalten
              <span>
                <ArrowUpRight size={14} />
              </span>
            </button>
          </>
        )}
      </div>
      {game.me.queue.length > 0 && own && (
        <div className="build-queue">
          <div className="section-label">
            <span>BAUWARTESCHLANGE</span>
            <span>{game.me.queue.length}</span>
          </div>
          {game.me.queue.map((q, i) => (
            <div key={i}>
              <span>{SHIPS[q.type].name}</span>
              <strong>
                {i === 0
                  ? `${Math.ceil(q.remaining / Math.max(0.1, 1 + empireModifiers(game.me.empire).construction))} T`
                  : 'Wartet'}
              </strong>
              {i === 0 && <Progress value={() => 1 - q.remaining / q.total} />}
            </div>
          ))}
        </div>
      )}
      {here.length > 0 && (
        <DetailList
          className="local-fleets"
          label="Flotten vor Ort"
          items={here}
          getKey={(f) => f.id}
          getName={(f) => f.name}
          selectedKey={fleet?.id}
        >
          {(f) => {
            const Icon = shipIcon(f.type);
            return (
              <button
                key={f.id}
                className={fleet?.id === f.id ? 'active' : ''}
                aria-pressed={fleet?.id === f.id}
                title={f.name}
                onClick={() => onFleet(f.id)}
              >
                <Icon size={13} />
                <span>{f.name}</span>
                <ChevronRight size={12} />
              </button>
            );
          }}
        </DetailList>
      )}
      <button className="system-view-link" onClick={onMode}>
        Systemansicht öffnen <ArrowUpRight size={13} />
      </button>
    </div>
  );
}
function Progress({ value }: { value: number | (() => number) }) {
  const root = useRef<HTMLDivElement>(null),
    latest = useRef(value);
  latest.current = value;
  const percent = () =>
    Math.min(1, Math.max(0, typeof latest.current === 'function' ? latest.current() : latest.current)) * 100;
  useEffect(() => {
    if (typeof value !== 'function') return;
    let frame = 0,
      last = 0;
    const update = (now: number) => {
      frame = requestAnimationFrame(update);
      if (document.hidden || now - last < 50 || !root.current) return;
      last = now;
      const amount = percent();
      (root.current.firstElementChild as HTMLElement).style.width = `${amount}%`;
      root.current.setAttribute('aria-valuenow', String(Math.round(amount)));
    };
    frame = requestAnimationFrame(update);
    return () => cancelAnimationFrame(frame);
  }, [typeof value]);
  return (
    <div
      ref={root}
      className="progress"
      role="progressbar"
      aria-valuenow={Math.round(percent())}
      aria-valuemin={0}
      aria-valuemax={100}
    >
      <span style={{ width: `${percent()}%` }} />
    </div>
  );
}
function ModalTitle({ eyebrow, title, icon }: { eyebrow: string; title: string; icon: ReactNode }) {
  return (
    <div className="modal-title">
      <span className="modal-icon">{icon}</span>
      <span className="eyebrow">{eyebrow}</span>
      <h2 id="dialog-title">{title}</h2>
    </div>
  );
}
function Dialog({ children, onClose }: { children: ReactNode; onClose: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const before = document.activeElement as HTMLElement;
    ref.current?.focus();
    return () => before?.focus();
  }, []);
  return (
    <div
      className="modal-backdrop"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        ref={ref}
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="dialog-title"
        tabIndex={-1}
        onKeyDown={(e) => {
          if (e.key !== 'Tab') return;
          const elements = ref.current!.querySelectorAll<HTMLElement>(
            'button:not(:disabled),input:not(:disabled),select:not(:disabled),textarea:not(:disabled),a[href],[tabindex="0"]',
          );
          const first = elements[0],
            last = elements[elements.length - 1];
          if (e.shiftKey && (document.activeElement === first || document.activeElement === ref.current)) {
            e.preventDefault();
            last?.focus();
          } else if (!e.shiftKey && document.activeElement === last) {
            e.preventDefault();
            first?.focus();
          }
        }}
      >
        <button className="modal-close icon-button" onClick={onClose} aria-label="Dialog schließen">
          <X size={19} />
        </button>
        {children}
      </div>
    </div>
  );
}
