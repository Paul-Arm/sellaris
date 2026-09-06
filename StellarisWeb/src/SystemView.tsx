import { useCallback, useState } from 'react';
import type { Client } from '../backend/client';
import { useSystemObjects } from './useSystemObjects';
import type { StoredBody } from '../shared/systemObjects';
import { TerraformingPanel } from './TerraformingPanel';
import { NavigationPanel, PointInputs } from './NavigationPanel';
import { constructionFleet, type Point3 } from '../shared/navigation';
import { SystemContextMenu } from './SystemContextMenu';
import {
  ArrowLeft,
  ArrowUpRight,
  Check,
  Crosshair,
  Diamond,
  FlaskConical,
  Globe2,
  Hammer,
  Minus,
  Orbit,
  Plus,
  Rocket,
  ScanLine,
  Shield,
  Telescope,
  Layers3,
  Sparkles,
  X,
  Zap,
} from 'lucide-react';
import type { GameCommand, GameView, Resource, StarSystem } from '../shared/game';
import { BODY_NAMES, FACILITIES, facilitySpec, facilityYield, type Facility } from '../shared/celestial';
import { crisisProductionFactor } from '../shared/stories';
import { SystemScene, type SystemTarget } from './SystemSpaceScene';
import './system-view.css';

const icons = { energy: Zap, minerals: Diamond, science: FlaskConical };
const format = (n: number) => n.toLocaleString('de-DE', { maximumFractionDigits: 1 });
function BodyName({ body, client, disabled }: { body: StoredBody; client: Client; disabled: boolean }) {
  const [editing, setEditing] = useState(false),
    [name, setName] = useState(body.name);
  const [busy, setBusy] = useState(false),
    [error, setError] = useState('');
  if (!editing)
    return (
      <button disabled={disabled} onClick={() => setEditing(true)}>
        Umbenennen
      </button>
    );
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        setBusy(true);
        setError('');
        void client.conn.reducers
          .renameBody({ objectId: body.objectId, revision: body.revision, name })
          .then(() => setEditing(false))
          .catch((e) => setError(String(e)))
          .finally(() => setBusy(false));
      }}
    >
      <label>
        Objektname
        <input
          autoFocus
          maxLength={60}
          value={name}
          onChange={(e) => setName(e.target.value)}
          disabled={busy || disabled}
        />
      </label>
      <button type="submit" disabled={busy || disabled || !name.trim()}>
        Speichern
      </button>
      <button type="button" disabled={busy} onClick={() => setEditing(false)}>
        Abbrechen
      </button>
      {error && <p role="alert">{error}</p>}
    </form>
  );
}
function Amounts({ values }: { values: { energy: number; minerals: number; science: number } }) {
  return (
    <span className="site-amounts">
      {(Object.keys(values) as Resource[])
        .filter((r) => values[r] !== 0)
        .map((r) => {
          const Icon = icons[r];
          return (
            <span key={r} title={r === 'energy' ? 'Energie' : r === 'minerals' ? 'Mineralien' : 'Forschung'}>
              <Icon size={12} />
              {format(values[r])}
            </span>
          );
        })}
    </span>
  );
}
export function SystemView({
  game,
  system,
  fleetId,
  command,
  connected,
  onFleet,
  onBack,
  onColony,
  onFleetDetails,
  onCourse,
  onBattle,
  onNavigate,
  client,
}: {
  client: Client | null;
  game: GameView;
  system: StarSystem;
  fleetId: string | null;
  command: (c: GameCommand) => void;
  connected: boolean;
  onFleet: (id: string) => void;
  onBack: () => void;
  onColony: () => void;
  onFleetDetails: () => void;
  onCourse: () => void;
  onBattle?: () => void;
  onNavigate: (id: string) => void;
}) {
  const [selection, setSelection] = useState<{ slot: number; fleet: string | null }>({
    slot: system.kind === 'star' ? 1 : 0,
    fleet: game.fleets.find((f) => f.id === fleetId)?.navigation?.orders.length ? fleetId : null,
  });
  const [context, setContext] = useState<{ target: SystemTarget; x: number; y: number } | null>(null);
  const closeContext = useCallback(() => setContext(null), []);
  const [point, setPoint] = useState<Point3>({ x: 500, y: 80, z: 300 });
  const [picking, setPicking] = useState(false),
    [stationMode, setStationMode] = useState(false);
  const [stationFacility, setStationFacility] = useState<'habitat' | 'research'>('research');
  const [zoom, setZoom] = useState(1),
    [zoomStep, setZoomStep] = useState(0),
    [bloom, setBloom] = useState(true),
    [contours, setContours] = useState(true),
    [reset, setReset] = useState(0),
    [focusSelection, setFocusSelection] = useState(0);
  const objects = useSystemObjects(client, system.id);
  const bodies = objects.bodies || [];
  const body = bodies.find((b) => b.slot === selection.slot) || bodies[0];
  const fleets = game.fleets.filter((f) => f.systemId === system.id && !f.route.length);
  const fleetChoices = game.fleets.filter(
    (f) => f.systemId === system.id || (f.id === fleetId && f.owner === game.me.id),
  );
  const selectedFleet = game.fleets.find((f) => f.id === selection.fleet);
  const builder = constructionFleet(game, system.id, selectedFleet?.id);
  const site = game.sites?.find((s) => s.systemId === system.id && s.bodySlot === body?.slot);
  const own = system.owner === game.me.id,
    surveyed = game.me.surveyed.includes(system.id);
  const ownFleet = fleets.find((f) => f.owner === game.me.id && !f.battleId);
  const scout = fleets.find((f) => f.owner === game.me.id && f.type === 'scout' && !f.task && !f.battleId);
  const colony = fleets.find((f) => f.owner === game.me.id && f.type === 'colony' && !f.task && !f.battleId);
  const allowed = surveyed && (own || (system.kind !== 'star' && !system.owner && !!ownFleet));
  const disabled = !connected || !!game.winner;
  const factor = Math.min(1, ...(game.crises || []).map((c) => crisisProductionFactor(c.phase, c.shielded)));
  const chooseFleet = (id: string) => {
    closeContext();
    onFleet(id);
    setSelection((s) => ({ ...s, fleet: id }));
    setStationMode(false);
    setPicking(false);
  };
  const chooseBody = (slot: number) => {
    closeContext();
    setSelection({ slot, fleet: null });
    setStationMode(false);
    setPicking(false);
  };
  const projectRemaining = site ? Math.max(0, site.finishAt - game.tick) : 0;
  const issueConstruction = (c: GameCommand) => {
    if (c.type === 'site_build' || c.type === 'station_place') {
      if (!builder) return;
      command({ ...c, fleetId: builder.id, append: true });
      chooseFleet(builder.id);
    } else command(c);
  };
  if (!body)
    return (
      <div className="system-view">
        <div className="system-loading" role="status">
          <p>
            {objects.error ||
              (objects.bodies
                ? 'Dieses System enthält keine aktiven Himmelskörper.'
                : 'Systemobjekte werden geladen …')}
          </p>
          <button onClick={onBack}>Zur Galaxie</button>
        </div>
      </div>
    );
  return (
    <div className="system-view">
      <SystemScene
        game={game}
        system={system}
        bodies={bodies}
        placement={picking ? point : undefined}
        previewPoint={stationMode || picking ? point : undefined}
        onPoint={(p) => setPoint({ ...p, y: point.y })}
        onContext={(target, x, y) => setContext({ target, x, y })}
        onMove={(p, append) => {
          closeContext();
          if (
            !disabled &&
            selectedFleet?.owner === game.me.id &&
            selectedFleet.systemId === system.id &&
            !selectedFleet.route.length &&
            !selectedFleet.battleId
          )
            command({ type: 'local_move', fleetId: selectedFleet.id, systemId: system.id, point: p, append });
        }}
        selectedBody={selectedFleet ? -1 : body.slot}
        fleetId={fleetId}
        onBody={chooseBody}
        onFleet={chooseFleet}
        zoomStep={zoomStep}
        onZoom={setZoom}
        bloom={bloom}
        contours={contours}
        onNavigate={onNavigate}
        reset={reset}
        focusSelection={focusSelection}
      />
      {own && surveyed && (
        <button
          className="station-placement-toggle"
          onClick={() => {
            setStationMode((v) => !v);
            setPicking(false);
          }}
        >
          Freie Station platzieren
        </button>
      )}
      {picking && (
        <div className="system-placement">
          Stationsposition wählen · In den Systemraum klicken · Höhe {point.y}
        </div>
      )}
      <div className="system-render-controls" aria-label="Kartendarstellung">
        <span>RAUMZEIT / 3D</span>
        <button
          aria-label="Gravitationskonturen"
          aria-pressed={contours}
          onClick={() => setContours((v) => !v)}
          title="Gravitationskonturen ein- oder ausblenden"
        >
          <Layers3 size={13} /> Konturen
        </button>
        <button
          aria-label="Lichtschein"
          aria-pressed={bloom}
          onClick={() => setBloom((v) => !v)}
          title="Lichtschein ein- oder ausschalten"
        >
          <Sparkles size={13} /> Licht
        </button>
      </div>
      <div className="system-flight-strip" aria-label="Flotten im System">
        <span>
          <Rocket size={13} />
          {fleets.reduce((n, f) => n + (f.shipCount || 1), 0)} SCHIFFE IM SYSTEM
        </span>
        <div>
          {fleetChoices.map((f) => (
            <button
              key={f.id}
              className={selection.fleet === f.id ? 'active' : ''}
              onClick={() => chooseFleet(f.id)}
              onContextMenu={(e) => {
                e.preventDefault();
                setContext({ target: { kind: 'fleet', id: f.id }, x: e.clientX, y: e.clientY });
              }}
            >
              <i style={{ background: game.players.find((p) => p.id === f.owner)?.color }} />
              {f.name}
              <small>{f.shipCount || 1}</small>
            </button>
          ))}
          {!fleets.length && <small>Keine Flotten in Sensorreichweite.</small>}
        </div>
        {onBattle && (
          <button className="system-combat-link" onClick={onBattle}>
            <Shield size={13} />
            Laufendes Gefecht ansehen
            <ArrowUpRight size={13} />
          </button>
        )}
      </div>
      <aside className="body-inspector" aria-label="Systemobjekt verwalten">
        {stationMode ? (
          <section className="navigation-panel" aria-label="Stationsplatzierung">
            <h2>Freie Station</h2>
            <p>
              Feste Position im Systemraum. Die Markierung zeigt den Bauplatz; Bau erst mit „Station
              errichten“.
            </p>
            <PointInputs point={point} setPoint={setPoint} />
            <button aria-pressed={picking} onClick={() => setPicking((v) => !v)}>
              {picking ? 'Zielwahl beenden' : 'Position auf der Karte wählen'}
            </button>
            <label>
              Stationstyp
              <select
                value={stationFacility}
                onChange={(e) => setStationFacility(e.target.value as 'habitat' | 'research')}
              >
                <option value="research">Forschungsstation</option>
                <option value="habitat">Außenposten</option>
              </select>
            </label>
            <p>
              {FACILITIES[stationFacility].cost.energy} Energie · {FACILITIES[stationFacility].cost.minerals}{' '}
              Mineralien · {FACILITIES[stationFacility].days} Tage
            </p>
            <button
              disabled={disabled || !builder}
              onClick={() =>
                issueConstruction({
                  type: 'station_place',
                  systemId: system.id,
                  point,
                  facility: stationFacility,
                })
              }
            >
              Station errichten
            </button>
            <small>
              {builder
                ? `${builder.name} fliegt zuerst zum Bauplatz. Kosten werden bei Baustart fällig.`
                : 'Ein eigenes Schiff im System wird benötigt.'}
            </small>
            <small>
              Abstand zu Körpern, Stationen und Umlaufbahnen erforderlich. Maximal 24 freie Stationen je
              System. Bau, Ausbau und Abbruch erfolgen anschließend am neuen Objekt.
            </small>
            <button
              onClick={() => {
                setStationMode(false);
                setPicking(false);
              }}
            >
              Zurück zur Auswahl
            </button>
          </section>
        ) : selectedFleet ? (
          <>
            <div className="body-hero fleet">
              <Rocket size={54} strokeWidth={0.7} />
              <span>FLOTTENKOMMANDO</span>
            </div>
            <div className="body-title">
              <span className="eyebrow">
                {selectedFleet.owner === game.me.id ? 'EIGENER VERBAND' : 'FREMDER VERBAND'}
              </span>
              <h2>{selectedFleet.name}</h2>
            </div>
            <div className="body-facts">
              <span>
                Schiffe <b>{selectedFleet.shipCount || 1}</b>
              </span>
              <span>
                Hülle <b>{format(selectedFleet.hp)} %</b>
              </span>
            </div>
            <p>
              {selectedFleet.battleId
                ? 'Im Gefecht gebunden.'
                : selectedFleet.task
                  ? selectedFleet.task.type === 'scan' && selectedFleet.navigation
                    ? `Erkundung · ${selectedFleet.navigation.visited.length}/${selectedFleet.navigation.totalBodies} Körper`
                    : `${selectedFleet.task.type === 'scan' ? 'Systemuntersuchung' : 'Kolonisierung'} · ${Math.ceil(selectedFleet.task.remaining)} T`
                  : selectedFleet.navigation?.orders.length
                    ? 'Flugauftrag aktiv.'
                    : selectedFleet.navigation?.phase === 'braking'
                      ? 'Schiff bremst ab.'
                    : 'Bereit im System.'}
            </p>
            {(selectedFleet.shipCount || 1) >
              Math.min(
                120,
                Math.max(1, Math.floor(4096 / fleets.filter((f) => f.type === selectedFleet.type).length)),
              ) && (
              <p className="body-hint">
                Die entfernte Formation stellt {selectedFleet.shipCount} Schiffe vereinfacht dar. Alle Schiffe
                bleiben im Verband enthalten.
              </p>
            )}
            {selectedFleet.owner === game.me.id && (
              <div className="body-main-actions">
                <button
                  className="primary-button"
                  onClick={onCourse}
                  disabled={disabled || !!selectedFleet.battleId}
                >
                  <Rocket size={14} />
                  Kurs auf der Galaxiekarte setzen
                </button>
                <button className="secondary-button" onClick={onFleetDetails}>
                  Verband verwalten
                  <ArrowUpRight size={13} />
                </button>
              </div>
            )}
            {selectedFleet.owner === game.me.id && (
              <NavigationPanel
                key={selectedFleet.id}
                fleet={selectedFleet}
                game={game}
                command={command}
                disabled={disabled}
              />
            )}
          </>
        ) : (
          <>
            <div className={`body-hero ${body.kind} ${body.stellar?.family ?? ''}`}>
              <div className="body-preview" style={{ '--body-color': body.color } as React.CSSProperties} />
              <span>{(body.stellar?.label ?? BODY_NAMES[body.kind]).toUpperCase()}</span>
              <small>OBJEKT {body.slot.toString().padStart(2, '0')}</small>
            </div>
            <div className="body-title">
              <span className="eyebrow">
                {own ? 'EIGENES SYSTEM' : system.owner ? 'FREMDES SYSTEM' : 'UNABHÄNGIGES SYSTEM'} /{' '}
                {surveyed ? 'KARTIERT' : 'UNERFORSCHT'}
              </span>
              <h2>{body.name}</h2>
              {own && !body.main && body.slot !== 0 && client && (
                <BodyName
                  key={`${body.objectId}:${body.revision}`}
                  body={body}
                  client={client}
                  disabled={disabled}
                />
              )}
            </div>
            <p>{body.description}</p>
            {own && body.kind === 'planet' && client && (
              <TerraformingPanel
                key={body.objectId}
                body={body}
                client={client}
                game={game}
                system={system}
                disabled={disabled}
              />
            )}
            <div className="body-facts">
              <span>
                Standort{' '}
                <b>
                  {body.position
                    ? `${Math.round(body.position.x)} / ${Math.round(body.position.y)} / ${Math.round(body.position.z)}`
                    : body.parent !== undefined
                      ? `Mond von ${bodies.find((b) => b.slot === body.parent)?.name}`
                      : body.orbit
                        ? 'Systemorbit'
                        : 'Zentraler Körper'}
                </b>
              </span>
              <span>
                Anlagenplatz <b>{site ? `${FACILITIES[site.facility].name} · ${site.level}/3` : 'Frei'}</b>
              </span>
            </div>
            {body.main && own && (
              <button className="body-colony-link" onClick={onColony}>
                <Globe2 size={18} />
                <span>
                  Hauptkolonie verwalten<small>Bevölkerung, Distrikte & Raumwerft</small>
                </span>
                <ArrowUpRight size={15} />
              </button>
            )}
            {!surveyed && (
              <div className="body-main-actions">
                <p className="body-hint">Eine Systemuntersuchung erschließt alle Bauplätze.</p>
                <button
                  className="primary-button"
                  disabled={disabled || !scout}
                  onClick={() => scout && command({ type: 'scan', fleetId: scout.id })}
                >
                  <ScanLine size={15} />
                  Alle Himmelskörper erkunden
                </button>
                {!scout && <small>Ein freies Forschungsschiff muss vor Ort sein.</small>}
              </div>
            )}
            {body.main && !system.owner && surveyed && (
              <button
                className="secondary-button"
                disabled={disabled || !colony || system.defense > 0}
                onClick={() => colony && command({ type: 'colonize', fleetId: colony.id })}
              >
                <Globe2 size={15} />
                Hauptkolonie gründen · 80 Energie / 80 Mineralien
              </button>
            )}
            <div className="site-heading">
              <Hammer size={14} />
              <h3>{site?.level ? 'Anlage ausbauen' : 'Körper erschließen'}</h3>
            </div>
            <p className="body-hint">
              {builder
                ? `${builder.name} übernimmt den Anflug. Bau und Kostenbuchung starten erst in der Nähe des Körpers.`
                : 'Zum Bauen wird ein eigenes Schiff im System benötigt.'}
            </p>
            {!allowed && (
              <p className="body-hint">
                {!surveyed
                  ? 'Zuerst untersuchen.'
                  : system.kind === 'star'
                    ? 'Für den Anlagenbau muss dieses Sternsystem deinem Reich gehören.'
                    : 'Eine eigene Flotte muss die Außenstation vor Ort errichten.'}
              </p>
            )}
            {site && site.owner !== game.me.id ? (
              <p className="body-hint">
                Diese Anlage gehört{' '}
                {game.players.find((p) => p.id === site.owner)?.name || 'einem anderen Reich'}.
              </p>
            ) : (
              <>
                {site?.building ? (
                  <div className="site-project">
                    <span>
                      <Hammer size={13} />
                      {FACILITIES[site.facility].name} · Stufe {site.level + 1}
                    </span>
                    <progress
                      aria-label="Anlagenbau"
                      max={Math.max(1, site.finishAt - site.startedAt)}
                      value={Math.max(0, game.tick - site.startedAt)}
                    />
                    <div>
                      <strong>{Math.ceil(projectRemaining)} T</strong>
                      <small>{game.paused ? 'Bau pausiert' : 'Im Bau'}</small>
                      <button
                        aria-label="Anlagenbau abbrechen"
                        disabled={disabled}
                        onClick={() => command({ type: 'site_cancel', siteId: site.id })}
                      >
                        <X size={14} />
                      </button>
                    </div>
                    <small>Abbrechen erstattet 50 % der Baukosten.</small>
                  </div>
                ) : (
                  <div className="facility-options">
                    {(Object.keys(FACILITIES) as Facility[])
                      .filter(
                        (id) => FACILITIES[id].kinds.includes(body.kind) && (!site || site.facility === id),
                      )
                      .map((id) => {
                        const def = FACILITIES[id],
                          level = site?.level || 0,
                          spec = facilitySpec(id, level),
                          max = level >= 3;
                        const affordable =
                          game.me.resources.energy >= spec.cost.energy &&
                          game.me.resources.minerals >= spec.cost.minerals;
                        return (
                          <article key={id}>
                            <header>
                              <strong>{def.name}</strong>
                              <small>{max ? 'MAX' : `STUFE ${level + 1}`}</small>
                            </header>
                            <p>{def.description}</p>
                            <div className="facility-yield">
                              <small>Ertrag pro Stufe / 4 Tage</small>
                              <Amounts values={facilityYield(id, 1, factor)} />
                            </div>
                            <button
                              className="secondary-button"
                              disabled={disabled || !allowed || !affordable || max || !builder}
                              onClick={() =>
                                issueConstruction({
                                  type: 'site_build',
                                  systemId: system.id,
                                  bodySlot: body.slot,
                                  facility: id,
                                })
                              }
                            >
                              {max ? (
                                <>
                                  <Check size={13} />
                                  Voll ausgebaut
                                </>
                              ) : (
                                <>
                                  <Hammer size={13} />
                                  <span>{level ? 'Ausbauen' : 'Errichten'}</span>
                                  <Amounts values={spec.cost} />
                                  <small>{spec.days} T</small>
                                </>
                              )}
                            </button>
                          </article>
                        );
                      })}
                  </div>
                )}
                {!!site?.level && (
                  <div className="site-current">
                    <Check size={14} />
                    <span>
                      Aktiver Ertrag · Stufe {site.level}
                      <Amounts
                        values={facilityYield(site.facility, site.level, site.suspended ? 0 : factor)}
                      />
                    </span>
                  </div>
                )}
                <p className="body-hint">
                  Ein Anlagenplatz pro Körper, bis Stufe 3. Außenposten ergänzen die Hauptkolonie und zählen
                  nicht als zusätzliche Siegkolonien. Anlagen unterliegen der Resonanzkrise.
                </p>
              </>
            )}
          </>
        )}
      </aside>
      <nav className="body-dock" aria-label="Himmelskörper">
        <span>
          <Orbit size={14} />
          SYSTEMATLAS <b>{bodies.length}</b>
        </span>
        <div>
          {bodies.map((b) => (
            <button
              key={b.slot}
              aria-pressed={!selectedFleet && body.slot === b.slot}
              onClick={() => chooseBody(b.slot)}
              onContextMenu={(e) => {
                e.preventDefault();
                setContext({ target: { kind: 'body', slot: b.slot }, x: e.clientX, y: e.clientY });
              }}
            >
              <i className={b.kind} style={{ background: b.color }} />
              <span>
                {b.name}
                <small>
                  {b.stellar
                    ? b.stellar.family === 'main' || b.stellar.family === 'giant'
                      ? b.stellar.spectral
                      : b.stellar.label
                    : BODY_NAMES[b.kind]}
                  {game.sites?.some((s) => s.systemId === system.id && s.bodySlot === b.slot)
                    ? ' · Anlage'
                    : ''}
                </small>
              </span>
            </button>
          ))}
        </div>
      </nav>
      {context && (
        <SystemContextMenu
          {...context}
          game={game}
          system={system}
          bodies={bodies}
          fleet={selectedFleet}
          disabled={disabled}
          command={issueConstruction}
          close={closeContext}
          onBody={chooseBody}
          onFleet={chooseFleet}
          onNavigate={onNavigate}
          onColony={onColony}
        />
      )}
      <div className="system-controls">
        <button onClick={onBack}>
          <ArrowLeft size={14} />
          Galaxie
        </button>
        <span>Rechtsklick: Befehle · Umschalt: anhängen · Ziehen: drehen · Rechts ziehen: verschieben</span>
        <button
          aria-label="Auswahl in Nahansicht"
          onClick={() => {
            setFocusSelection((n) => n + 1);
          }}
        >
          <Crosshair size={15} />
        </button>
        <button
          aria-label="Systemansicht zentrieren"
          onClick={() => {
            setReset((n) => n + 1);
          }}
        >
          <Crosshair size={15} />
        </button>
        <button aria-label="Systemansicht herauszoomen" onClick={() => setZoomStep((z) => z - 1)}>
          <Minus size={15} />
        </button>
        <small>{Math.round(zoom * 100)} %</small>
        <button aria-label="Systemansicht hineinzoomen" onClick={() => setZoomStep((z) => z + 1)}>
          <Plus size={15} />
        </button>
      </div>
    </div>
  );
}
