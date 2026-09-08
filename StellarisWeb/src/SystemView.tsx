import { optimizeProduction } from '../shared/compute';
import { BuildSlot, SlotPicker } from './BuildSlots';
import { StarbaseControl } from './StarbaseManager';
import { economyTotals } from '../shared/economy';
import { resourceIcons as icons } from './resource-icons';
import { RESOURCE_NAMES } from '../shared/resources';
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { InventorySelection } from './inventory-model';
import type { Client } from '../backend/client';
import { useSystemObjects } from './useSystemObjects';
import type { StoredBody } from '../shared/systemObjects';
import { TerraformingPanel } from './TerraformingPanel';
import { NavigationPanel, PointInputs } from './NavigationPanel';
import { MegastructurePanel } from './MegastructurePanel';
import { isMegastructure } from '../shared/megastructures';
import { StellarProjectPanel } from './StellarProjectPanel';
import { StellarWeatherPanel } from './StellarWeatherPanel';
import { stellarWeatherFactor } from '../shared/stellarWeather';
import { constructionFleet, type Point3 } from '../shared/navigation';
import { SystemContextMenu } from './SystemContextMenu';
import { colonizableBody } from '../shared/planetColonies';
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
import {
  BODY_NAMES,
  FACILITIES,
  facilitySpec,
  facilityLedger,
  facilityFits,
  type Facility,
} from '../shared/celestial';
import { crisisProductionFactor } from '../shared/crises';
import { SystemScene, type SystemTarget } from './SystemSpaceScene';
import './system-view.css';

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
function Amounts({ values }: { values: import('../shared/resources').Resources }) {
  return (
    <span className="site-amounts">
      {(Object.keys(values) as Resource[])
        .filter((r) => values[r] !== 0)
        .map((r) => {
          const Icon = icons[r];
          return (
            <span key={r} title={RESOURCE_NAMES[r]}>
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
  inventorySelection,
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
  inventorySelection?: InventorySelection | null;
  command: (c: GameCommand) => void;
  connected: boolean;
  onFleet: (id: string) => void;
  onBack: () => void;
  onColony: (objectId?: string) => void;
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
  const [facilityPicker, setFacilityPicker] = useState<string | null>(null);
  const [stationFacility, setStationFacility] = useState<'habitat' | 'research'>('research');
  const [zoom, setZoom] = useState(1),
    [zoomStep, setZoomStep] = useState(0),
    [bloom, setBloom] = useState(true),
    [contours, setContours] = useState(true),
    [reset, setReset] = useState(0),
    [focusSelection, setFocusSelection] = useState(0);
  const objects = useSystemObjects(client, system.id);
  const bodies = objects.bodies || [];
  const appliedInventorySelection = useRef<InventorySelection | null>(null);
  useEffect(() => {
    if (
      !inventorySelection ||
      inventorySelection === appliedInventorySelection.current ||
      inventorySelection.systemId !== system.id
    )
      return;
    const slot = inventorySelection.bodySlot ?? bodies.find((body) => body.main)?.slot;
    if (!inventorySelection.fleetId && slot === undefined) return;
    appliedInventorySelection.current = inventorySelection;
    setSelection((previous) => ({ slot: slot ?? previous.slot, fleet: inventorySelection.fleetId ?? null }));
    setStationMode(false);
    setPicking(false);
    setContext(null);
    setFocusSelection((n) => n + 1);
  }, [inventorySelection, system.id, bodies]);
  const body = bodies.find((b) => b.slot === selection.slot) || bodies[0];
  const planetColony =
    body && game.planetColonies?.find((c) => c.systemId === system.id && c.bodySlot === body.slot);
  const fleets = game.fleets.filter((f) => f.systemId === system.id && !f.route.length);
  const selectedFleet = game.fleets.find((f) => f.id === selection.fleet);
  const builder = constructionFleet(game, system.id, selectedFleet?.id);
  const site = game.sites?.find((s) => s.systemId === system.id && s.bodySlot === body?.slot);
  const own = system.owner === game.me.id,
    surveyed = game.me.surveyed.includes(system.id);
  const ownFleet = fleets.find((f) => f.owner === game.me.id && !f.battleId);
  const scout = fleets.find((f) => f.owner === game.me.id && f.type === 'scout' && !f.task && !f.battleId);
  const colony = fleets.find((f) => f.owner === game.me.id && f.type === 'colony' && !f.task && !f.battleId);
  const allowed = surveyed && own;
  const disabled = !connected || !!game.winner;
  const factor = Math.min(1, ...(game.crises || []).map((c) => crisisProductionFactor(c.phase, c.shielded)));
  const chooseFleet = (id: string) => {
    closeContext();
    onFleet(id);
    setSelection((s) => ({ ...s, fleet: id }));
    setStationMode(false);
    setPicking(false);
  };
  const inspector = useRef<HTMLElement>(null);
  const [projectFocus, setProjectFocus] = useState(0);
  useLayoutEffect(() => {
    if (projectFocus)
      inspector.current?.querySelector('.megastructure-panel')?.scrollIntoView({ block: 'start' });
  }, [projectFocus]);
  const chooseBody = (slot: number, project = false) => {
    closeContext();
    setSelection({ slot, fleet: null });
    if (project) setProjectFocus((n) => n + 1);
    setStationMode(false);
    setPicking(false);
  };
  const projectRemaining = site ? Math.max(0, site.finishAt - game.tick) : 0;
  const issueConstruction = (c: GameCommand) => {
    if (c.type === 'site_build' || c.type === 'station_place' || c.type === 'megastructure_place') {
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
      {picking && (
        <div className="system-placement">
          Stationsposition wählen · In den Systemraum klicken · Höhe {point.y}
        </div>
      )}
      <div className="system-render-controls" aria-label="Kartendarstellung">
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
      <aside ref={inspector} className="body-inspector" aria-label="Systemobjekt verwalten">
        <StarbaseControl key={system.id} game={game} system={system} command={command} disabled={disabled} />
        <div className="inspector-tools">
          {own && surveyed && (
            <button
              aria-pressed={stationMode}
              onClick={() => {
                setStationMode((v) => !v);
                setPicking(false);
              }}
            >
              <Plus size={13} /> Station
            </button>
          )}
          {onBattle && (
            <button onClick={onBattle}>
              <Shield size={13} /> Gefecht
            </button>
          )}
        </div>
        {stationMode ? (
          <section className="navigation-panel" aria-label="Stationsplatzierung">
            <h2>Freie Station</h2>
            <p>Bauplatz wählen</p>
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
                <option value="habitat">Orbitalhabitat</option>
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
                ? `${builder.name} · Zahlung bei Baustart`
                : 'Ein eigenes Schiff im System wird benötigt.'}
            </small>
            <small>Max. 24 Stationen. Bauplatz außerhalb von Körpern und Umlaufbahnen.</small>
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
            <div className="body-title">
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
            {selectedFleet.owner === game.me.id && (
              <div className="body-main-actions">
                <button
                  className="primary-button"
                  onClick={onCourse}
                  disabled={disabled || !!selectedFleet.battleId}
                >
                  <Rocket size={14} />
                  Kurs setzen
                </button>
                <button className="secondary-button" onClick={onFleetDetails}>
                  Verband verwalten
                  <ArrowUpRight size={13} />
                </button>
              </div>
            )}
            {selectedFleet.owner === game.me.id && (
              <NavigationPanel
                bodies={bodies}
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
            <div className="body-title">
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
            <p className="body-type">
              {body.stellar?.label ?? BODY_NAMES[body.kind]} · Objekt {body.slot}
            </p>
            {(body.slot === 0 || body.megastructure === 'dyson') && (
              <StellarWeatherPanel system={system} tick={game.tick} paused={game.paused} />
            )}
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
                      ? `${body.megastructure ? 'Am Zentralkörper' : 'Mond von'} ${bodies.find((b) => b.slot === body.parent)?.name}`
                      : body.orbit
                        ? 'Systemorbit'
                        : 'Zentraler Körper'}
                </b>
              </span>
              <span>
                Anlagenplatz <b>{site ? `${FACILITIES[site.facility].name} · ${site.level}/3` : 'Frei'}</b>
              </span>
            </div>
            {((body.main && system.colony) || planetColony) && own && (
              <button className="body-colony-link" onClick={() => onColony(planetColony?.objectId)}>
                <Globe2 size={18} />
                <span>
                  Kolonie verwalten<small>Bevölkerung & Distrikte</small>
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
            {body.main && own && !system.colony && surveyed && (
              <button
                className="secondary-button"
                disabled={disabled || !colony}
                onClick={() => colony && command({ type: 'colonize', fleetId: colony.id })}
              >
                <Globe2 size={15} />
                Hauptkolonie gründen · 80 Energie / 80 Mineralien
              </button>
            )}
            {own && surveyed && colonizableBody(body) && !planetColony && (
              <button
                className="secondary-button"
                disabled={disabled || !colony}
                onClick={() =>
                  colony &&
                  command({
                    type: 'colonize',
                    fleetId: colony.id,
                    systemId: system.id,
                    bodySlot: body.slot,
                    append: true,
                  })
                }
              >
                <Globe2 size={15} /> Planeten besiedeln · 80 Energie / 80 Mineralien
              </button>
            )}
            <div className="site-heading">
              <Hammer size={14} />
              <h3>{site?.level ? 'Anlage ausbauen' : 'Körper erschließen'}</h3>
            </div>
            <MegastructurePanel
              game={game}
              system={system}
              body={body}
              bodies={bodies}
              command={issueConstruction}
              disabled={disabled}
              onBody={chooseBody}
            />
            <StellarProjectPanel
              game={game}
              system={system}
              body={body}
              bodies={bodies}
              command={command}
              disabled={disabled}
            />
            <p className="body-hint">
              {builder
                ? `${builder.name} · Zahlung nach Anflug bei Baustart`
                : 'Zum Bauen wird ein eigenes Schiff im System benötigt.'}
            </p>
            {!allowed && (
              <p className="body-hint">
                {!surveyed
                  ? 'Zuerst untersuchen.'
                  : 'Für den Anlagenbau muss dieses System deinem Reich gehören.'}
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
                  <>
                    {(Object.keys(FACILITIES) as Facility[]).some(
                      (id) => !isMegastructure(id) && facilityFits(id, body),
                    ) && (
                      <BuildSlot
                        label="ORBITALER ANLAGENPLATZ"
                        name={site ? FACILITIES[site.facility].name : 'Freier Anlagenplatz'}
                        icon={<Orbit />}
                        state={site ? 'occupied' : allowed ? 'empty' : 'locked'}
                        level={site?.level}
                        detail={site ? (site.level >= 3 ? 'Voll ausgebaut' : 'Anlage verwalten') : undefined}
                        onClick={() => setFacilityPicker(body.objectId)}
                      />
                    )}
                    {facilityPicker === body.objectId && (
                      <SlotPicker
                        title={`${body.name} · Anlagenplatz`}
                        subtitle={
                          site ? 'Bestehende Anlage ausbauen.' : 'Wähle die Anlage für diesen Himmelskörper.'
                        }
                        close={() => setFacilityPicker(null)}
                      >
                        {(Object.keys(FACILITIES) as Facility[])
                          .filter(
                            (id) =>
                              !isMegastructure(id) &&
                              facilityFits(id, body) &&
                              (!site || site.facility === id),
                          )
                          .map((id) => {
                            const def = FACILITIES[id],
                              level = site?.level || 0,
                              spec = facilitySpec(id, level),
                              max = level >= 3;
                            const affordable =
                              game.me.resources.energy >= spec.cost.energy &&
                              game.me.resources.minerals >= spec.cost.minerals;
                            const Icon =
                              id === 'research'
                                ? FlaskConical
                                : id === 'mine'
                                  ? Diamond
                                  : id === 'solar'
                                    ? Zap
                                    : Orbit;
                            return (
                              <button
                                className="slot-choice"
                                key={id}
                                disabled={disabled || !allowed || !affordable || max || !builder}
                                onClick={() => {
                                  issueConstruction({
                                    type: 'site_build',
                                    systemId: system.id,
                                    bodySlot: body.slot,
                                    facility: id,
                                  });
                                  setFacilityPicker(null);
                                }}
                              >
                                <Icon />
                                <strong>{def.name}</strong>
                                <small>
                                  {max
                                    ? 'Voll ausgebaut'
                                    : `Stufe ${level + 1} ${level ? 'ausbauen' : 'einsetzen'}`}
                                </small>
                                <small>Ertrag pro Stufe / Monat</small>
                                <Amounts
                                  values={economyTotals(
                                    optimizeProduction(facilityLedger(
                                      id,
                                      1,
                                      game.me.empire.economyModifiers ?? [],
                                      factor,
                                      stellarWeatherFactor(id, system.stellarWeather, game.tick),
                                    ), game.me),
                                  )}
                                />
                                {!max && (
                                  <span className="slot-choice-cost">
                                    {spec.cost.energy} Energie · {spec.cost.minerals} Mineralien · {spec.days}{' '}
                                    T
                                  </span>
                                )}
                                {!builder && (
                                  <small>Ein eigenes freies Schiff im System wird benötigt.</small>
                                )}
                                {!affordable && <small>Rohstoffe fehlen</small>}
                              </button>
                            );
                          })}
                      </SlotPicker>
                    )}
                  </>
                )}
                {!!site?.level && (
                  <div className="site-current">
                    <Check size={14} />
                    <span>
                      Aktiver Ertrag · Stufe {site.level}
                      <Amounts
                        values={
                          site.suspended
                            ? {}
                            : economyTotals(
                                optimizeProduction(facilityLedger(
                                  site.facility,
                                  site.level,
                                  game.me.empire.economyModifiers ?? [],
                                  factor,
                                  stellarWeatherFactor(site.facility, system.stellarWeather, game.tick),
                                ), game.me),
                              )
                        }
                      />
                    </span>
                  </div>
                )}
              </>
            )}
          </>
        )}
      </aside>
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
