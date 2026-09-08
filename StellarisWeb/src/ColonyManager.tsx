import { RESOURCE_NAMES } from '../shared/resources';
import { BuildSlot, SlotPicker } from './BuildSlots';
import { ColonyTree } from './ColonyTree';
import { useState } from 'react';
import {
  ArrowUp,
  Check,
  Cpu,
  Diamond,
  Factory,
  FlaskConical,
  Globe2,
  Hammer,
  Home,
  Leaf,
  Pause,
  Play,
  Plus,
  Shield,
  Trash2,
  Users,
  X,
  Zap,
} from 'lucide-react';
import type { GameCommand, GameView, StarSystem } from '../shared/game';
import { empireModifiers } from '../shared/empireState';
import {
  BUILDINGS,
  FEATURES,
  FOCUSES,
  colonyEconomy,
  colonyGrowthPerMinute,
  colonyProduction,
  districtCapacity,
  districtSpec,
  occupiedDistricts,
  type BuildingId,
  type ColonyCommand,
  type ColonyFocus,
} from '../shared/colonies';
import { PlanetSurface } from './PlanetSurface';
import './planet-manager.css';
import { ownedColonyWorlds } from '../shared/planetColonies';

const icons = {
  habitat: Home,
  biosphere: Leaf,
  reactor: Zap,
  foundry: Factory,
  laboratory: FlaskConical,
  datacenter: Cpu,
  bastion: Shield,
};
const focusIcons = { balanced: Globe2, energy: Zap, minerals: Diamond, data: FlaskConical };
const fmt = (n: number) => n.toLocaleString('de-DE', { maximumFractionDigits: 1 });
const signed = (n: number) => `${n >= 0 ? '+' : '−'}${fmt(Math.abs(n))}`;
const types = Object.keys(BUILDINGS) as BuildingId[];

type Props = {
  game: GameView;
  selected: string;
  onSelect: (id: string) => void;
  command: (command: GameCommand) => void;
  connected: boolean;
};
export function ColonyManager(props: Props) {
  const worlds = ownedColonyWorlds(props.game);
  const system = worlds.find((s) => s.worldId === props.selected) || worlds[0];
  if (!system)
    return (
      <div className="colony-empty">
        <Globe2 size={36} />
        <h2 id="dialog-title">Noch keine Kolonie</h2>
        <p>Sichere ein untersuchtes System mit einem Außenposten und entsende dann ein Kolonieschiff.</p>
      </div>
    );
  return (
    <div className="planet-manager">
      <ColonyTree
        key={`${props.game.code}:${props.game.me.id}`}
        game={props.game}
        selected={system.worldId}
        onSelect={(colony) => props.onSelect(colony.id)}
      />
      <ColonyWorkspace key={system.worldId} {...props} system={system} />
    </div>
  );
}

function ColonyWorkspace({
  game,
  system,
  command,
  connected,
}: Props & { system: StarSystem & { bodySlot?: number } }) {
  const c = system.colony!,
    [sectorId, setSectorId] = useState(0),
    [tab, setTab] = useState<'surface' | 'population'>('surface'),
    [selectedSlot, setSelectedSlot] = useState<number | null>(null),
    [picking, setPicking] = useState<number | null>(null),
    [demolish, setDemolish] = useState<number | null>(null);
  const sector = c.sectors.find((s) => s.id === sectorId) || c.sectors[0],
    e = colonyEconomy(c, system.planet, game.me),
    output = colonyProduction(system, game.me),
    project = c.construction;
  const geometry = JSON.stringify(c.sectors.map(({ id, x, y, z }) => ({ id, x, y, z })));
  const order = (details: Omit<ColonyCommand, 'systemId' | 'revision'>) =>
    command({
      ...details,
      systemId: system.id,
      bodySlot: system.bodySlot,
      revision: c.revision,
    } as ColonyCommand);
  const build = (building: BuildingId) =>
    command({
      type: 'colony_build',
      building,
      slot: picking!,
      sectorId: sector.id,
      systemId: system.id,
      bodySlot: system.bodySlot,
      revision: c.revision,
    });
  const afford = (building: BuildingId, level = 1) => {
    const spec = districtSpec(building, level);
    return game.me.resources.energy >= spec.cost.energy && game.me.resources.minerals >= spec.cost.minerals;
  };
  const select = (id: number) => {
    setSectorId(id);
    setSelectedSlot(null);
    setPicking(null);
    setDemolish(null);
    setTab('surface');
  };
  const growth = colonyGrowthPerMinute(c, system.planet, game.me);
  const growthReason =
    e.housing <= c.population
      ? 'Wohnraum fehlt'
      : e.supplyCapacity <= c.population || e.supply + 0.001 < e.demand
        ? 'Versorgung ausbauen'
        : 'Wachstum aktiv';
  return (
    <>
      <header className="pm-header">
        <div>
          <span className="pm-kicker">{system.name.toUpperCase()} / PLANETARE VERWALTUNG</span>
          <h2 id="dialog-title">
            {system.colonyName || (system.name === 'Sol' ? 'Terra' : `${system.name} Prime`)}
          </h2>
          <p>
            {system.planet} <span>·</span> {c.sectors.length} Sektoren
          </p>
        </div>
        <div className="pm-yields" title="Nettoertrag pro Monat, einschließlich orbitaler Förderung">
          <span className="pm-energy">
            <Zap />
            {signed(output.energy)}
          </span>
          <span className="pm-minerals">
            <Diamond />
            {signed(output.minerals)}
          </span>
          <span className="pm-data">
            <FlaskConical />
            {signed(output.data)}
          </span>
          <small>pro Monat</small>
        </div>
      </header>
      {!connected && (
        <div className="pm-notice" role="status">
          Verbindung unterbrochen · Bauaufträge sind vorübergehend gesperrt.
        </div>
      )}
      <div className="pm-body">
        <section className="pm-main" aria-label="Planetenübersicht">
          <div className="pm-tabs" role="tablist" aria-label="Planetenansicht">
            <button role="tab" aria-selected={tab === 'surface'} onClick={() => setTab('surface')}>
              <Globe2 size={14} />
              Oberfläche
            </button>
            <button role="tab" aria-selected={tab === 'population'} onClick={() => setTab('population')}>
              <Users size={14} />
              Bevölkerung
            </button>
          </div>
          <div className="pm-vitals">
            <span title="Gesamtbevölkerung">
              <Users />
              {fmt(c.population)} <small>Pops</small>
            </span>
            <span title="Belegter / verfügbarer Wohnraum">
              <Home />
              {fmt(c.population)} / {e.housing}
            </span>
            <span className={e.supply + 0.001 < e.demand ? 'pm-warning' : ''} title="Versorgte Pops / Bedarf">
              <Leaf />
              {fmt(e.supply)} / {fmt(e.demand)}
            </span>
          </div>
          {tab === 'surface' ? (
            <div className="pm-map">
              <div className="pm-contours" aria-hidden="true" />
              <div className="pm-orb">
                <PlanetSurface geometry={geometry} planet={system.planet} selected={sector.id} />
                {c.sectors.map((s) => {
                  const rows = e.districts.filter((d) => d.sectorId === s.id),
                    jobs = rows.reduce((n, d) => n + d.jobs, 0),
                    workers = rows.reduce((n, d) => n + d.employed, 0),
                    Icon = s.districts.length ? icons[s.districts[0].building] : Plus;
                  return (
                    <button
                      key={s.id}
                      className={`pm-marker ${s.districts.length ? '' : 'vacant'} ${s.id === sector.id ? 'selected' : ''} ${project?.sectorId === s.id ? 'building' : ''}`}
                      style={{ left: `${50 + s.x * 50}%`, top: `${50 + s.y * 50}%` }}
                      aria-pressed={s.id === sector.id}
                      aria-label={`${s.name}, ${FEATURES[s.feature].name}, ${fmt(workers)} von ${jobs} Jobs besetzt`}
                      onClick={() => select(s.id)}
                    >
                      <Icon size={17} />
                      <span className="pm-marker-name">{s.name}</span>
                      <small>
                        {project?.sectorId === s.id ? <Hammer size={10} /> : null}
                        {jobs ? `${fmt(workers)} / ${jobs}` : `${s.slots - s.districts.length} frei`}
                      </small>
                    </button>
                  );
                })}
              </div>
              <div className="pm-map-caption">
                <span>ADMINISTRATIVE PROJEKTION</span>
                <span>
                  {occupiedDistricts(c)} / {districtCapacity(c)} Bauplätze
                </span>
              </div>
            </div>
          ) : (
            <div className="pm-population" role="tabpanel">
              <div className="pm-pop-summary">
                <div>
                  <strong>{fmt(e.employed)}</strong>
                  <span>beschäftigt / {e.jobs} Jobs</span>
                </div>
                <div>
                  <strong>{fmt(e.unemployed)}</strong>
                  <span>ohne Arbeitsplatz</span>
                </div>
                <div>
                  <strong>{signed(growth)}</strong>
                  <span>Pops / 60 Spieltage</span>
                </div>
              </div>
              <p className={growth ? 'pm-muted' : 'pm-warning'}>
                {growthReason} · {fmt(e.supplyCapacity)} Pops maximal versorgbar
              </p>
              <div className="pm-species">
                {c.populations?.map((g) => (
                  <div key={g.speciesId}>
                    <Users size={15} />
                    <span>
                      {game.me.empire?.species.find((s) => s.id === g.speciesId)?.name || 'Bevölkerung'}
                    </span>
                    <b>{fmt(g.population)}</b>
                  </div>
                ))}
              </div>
              <h3>Arbeitsplätze</h3>
              {types
                .filter((b) => BUILDINGS[b].jobs)
                .map((b) => {
                  const rows = e.districts.filter((r) => r.building === b),
                    jobs = rows.reduce((n, r) => n + r.jobs, 0),
                    workers = rows.reduce((n, r) => n + r.employed, 0),
                    Icon = icons[b];
                  return (
                    <div className="pm-job" key={b}>
                      <Icon size={16} />
                      <span>{BUILDINGS[b].name}</span>
                      <meter
                        min={0}
                        max={Math.max(1, jobs)}
                        value={workers}
                        aria-label={`${BUILDINGS[b].name}: besetzte Jobs`}
                      />
                      <b>
                        {fmt(workers)} / {jobs}
                      </b>
                    </div>
                  );
                })}
              <p className="pm-muted">
                Pops wachsen stufenlos. Versorgung und Wachposten werden zuerst besetzt; dein Schwerpunkt
                verteilt die übrigen Arbeitskräfte.
              </p>
            </div>
          )}
          <div className="pm-focus">
            <span>ARBEITSPRIORITÄT</span>
            <div>
              {(Object.keys(FOCUSES) as ColonyFocus[]).map((f) => {
                const Icon = focusIcons[f];
                return (
                  <button
                    key={f}
                    title={FOCUSES[f].description}
                    aria-pressed={c.focus === f}
                    disabled={!connected}
                    onClick={() =>
                      command({
                        type: 'colony_focus',
                        focus: f,
                        systemId: system.id,
                        bodySlot: system.bodySlot,
                        revision: c.revision,
                      })
                    }
                  >
                    <Icon size={14} />
                    {FOCUSES[f].name}
                  </button>
                );
              })}
            </div>
          </div>
        </section>
        <aside className="pm-inspector" aria-label="Sektor verwalten">
          <div className="pm-sector-heading">
            <span className="pm-kicker">SEKTOR {String(sector.id + 1).padStart(2, '0')}</span>
            <h3>{sector.name}</h3>
            <div className="pm-feature">
              <Diamond size={14} />
              <span>
                {FEATURES[sector.feature].name}
                <small>{FEATURES[sector.feature].description}</small>
              </span>
            </div>
          </div>
          <div className="pm-section-title">
            <h4>Bauplätze</h4>
            <span>
              {sector.districts.length} / {sector.slots}
            </span>
          </div>
          <div className="pm-slot-grid">
            {Array.from({ length: sector.slots }, (_, slot) => {
              const d = sector.districts.find((d) => d.slot === slot);
              const pending = project?.sectorId === sector.id && project.slot === slot;
              const building = d?.building ?? (pending ? project.building : undefined);
              const Icon = building ? icons[building] : Plus;
              return (
                <BuildSlot
                  key={slot}
                  label={`BAUPLATZ ${slot + 1}`}
                  name={building ? BUILDINGS[building].name : 'Freier Bauplatz'}
                  icon={<Icon />}
                  state={pending ? 'building' : d ? 'occupied' : 'empty'}
                  selected={selectedSlot === slot}
                  level={d?.level}
                  detail={
                    pending
                      ? `${Math.ceil(project.remaining / Math.max(0.1, 1 + empireModifiers(game.me.empire).construction))} T · ${game.paused ? 'Pausiert' : 'Im Bau'}`
                      : d
                        ? d.enabled
                          ? 'Distrikt verwalten'
                          : 'Stillgelegt'
                        : project
                          ? 'Bauauftrag läuft'
                          : undefined
                  }
                  onClick={() => {
                    setSelectedSlot(slot);
                    setDemolish(null);
                    if (!d && !project) setPicking(slot);
                  }}
                />
              );
            })}
          </div>
          <div className="pm-districts">
            {sector.districts
              .filter((d) => d.slot === selectedSlot)
              .map((d) => {
                const spec = BUILDINGS[d.building],
                  Icon = icons[d.building],
                  row = e.districts.find((r) => r.id === d.id)!,
                  cost = districtSpec(d.building, d.level + 1),
                  busy = project?.districtId === d.id;
                return (
                  <article key={d.id} className={`pm-district ${d.enabled ? '' : 'disabled'}`}>
                    <div className="pm-district-title">
                      <Icon size={17} />
                      <strong>{spec.name}</strong>
                      <span>{'ⅠⅡⅢ'[d.level - 1]}</span>
                    </div>
                    <div className="pm-district-output">
                      <span>
                        {spec.housing ? `${row.housing} Wohnraum` : `${fmt(row.employed)} / ${row.jobs} Jobs`}
                      </span>
                      <span>
                        {spec.resource
                          ? `${signed(row.output[spec.resource])} ${RESOURCE_NAMES[spec.resource]}`
                          : spec.supply
                            ? `${fmt(row.supply)} versorgt`
                            : spec.housing
                              ? ''
                              : d.building === 'datacenter'
                                ? `${fmt(row.compute)} Compute / Monat`
                                : `${fmt(row.defense)} Schilde`}
                      </span>
                    </div>
                    {row.workers.length > 0 && (
                      <div className="pm-job-species">
                        {row.workers.map((worker) => (
                          <small key={worker.speciesId}>
                            {worker.name}: {fmt(worker.employed)} Jobs
                          </small>
                        ))}
                      </div>
                    )}
                    <div className="pm-district-actions">
                      <button
                        disabled={!connected || !!project || d.level >= 3 || !afford(d.building, d.level + 1)}
                        title={`Stufe ${d.level + 1}: ${cost.cost.energy} Energie, ${cost.cost.minerals} Mineralien`}
                        onClick={() =>
                          command({
                            type: 'colony_upgrade',
                            districtId: d.id,
                            systemId: system.id,
                            bodySlot: system.bodySlot,
                            revision: c.revision,
                          })
                        }
                      >
                        <ArrowUp size={12} />
                        {d.level >= 3 ? 'Maximum' : `Ausbau · ${cost.cost.minerals} ◇`}
                      </button>
                      <button
                        disabled={!connected || busy}
                        aria-label={`${spec.name} ${d.enabled ? 'pausieren' : 'aktivieren'}`}
                        title={d.enabled ? 'Stilllegen: keine Produktion, kein Unterhalt' : 'Aktivieren'}
                        onClick={() =>
                          command({
                            type: 'colony_toggle',
                            districtId: d.id,
                            enabled: !d.enabled,
                            systemId: system.id,
                            bodySlot: system.bodySlot,
                            revision: c.revision,
                          })
                        }
                      >
                        {d.enabled ? <Pause size={12} /> : <Play size={12} />}
                      </button>
                      <button
                        disabled={!connected || busy}
                        aria-label={`${spec.name} abreißen`}
                        onClick={() => setDemolish(d.id)}
                      >
                        <Trash2 size={12} />
                      </button>
                    </div>
                    {demolish === d.id && (
                      <div className="pm-confirm">
                        <span>Ohne Erstattung abreißen?</span>
                        <button
                          disabled={!connected}
                          aria-label="Abriss bestätigen"
                          onClick={() => {
                            command({
                              type: 'colony_demolish',
                              districtId: d.id,
                              systemId: system.id,
                              bodySlot: system.bodySlot,
                              revision: c.revision,
                            });
                            setDemolish(null);
                          }}
                        >
                          <Check size={14} />
                        </button>
                        <button aria-label="Abriss verwerfen" onClick={() => setDemolish(null)}>
                          <X size={14} />
                        </button>
                      </div>
                    )}
                  </article>
                );
              })}
          </div>
          {selectedSlot === null && (
            <p className="pm-muted">
              Wähle einen Bauplatz. Freie Plätze kannst du mit einem Distrikt belegen.
            </p>
          )}
          {picking !== null && (
            <SlotPicker
              title={`${sector.name} · Bauplatz ${picking + 1}`}
              subtitle="Wähle den Distrikt für diesen Standort."
              close={() => setPicking(null)}
            >
              {types.map((b) => {
                const s = BUILDINGS[b],
                  Icon = icons[b],
                  match = FEATURES[sector.feature].building === b;
                return (
                  <button
                    key={b}
                    className="slot-choice"
                    disabled={
                      !connected ||
                      !!project ||
                      sector.districts.some((d) => d.slot === picking) ||
                      !afford(b)
                    }
                    onClick={() => {
                      build(b);
                      setPicking(null);
                    }}
                  >
                    <Icon />
                    <strong>{s.name}</strong>
                    {match && <em>Standortbonus</em>}
                    <small>{s.description}</small>
                    <span className="slot-choice-cost">
                      {s.cost.energy} Energie · {s.cost.minerals} Mineralien ·{' '}
                      {Math.ceil(s.time / Math.max(0.1, 1 + empireModifiers(game.me.empire).construction))} T
                    </span>
                    <small>
                      {s.housing
                        ? `+${s.housing + (sector.feature === 'sheltered' ? 2 : 0)} Wohnraum`
                        : `${s.jobs} Jobs`}{' '}
                      · {s.upkeep} Energie Unterhalt
                    </small>
                    {!afford(b) && <small>Rohstoffe fehlen</small>}
                  </button>
                );
              })}
            </SlotPicker>
          )}
        </aside>
      </div>
      <footer className="pm-footer">
        {project ? (
          <>
            <Hammer size={16} />
            <div>
              <strong>
                {BUILDINGS[project.building].name} · Stufe {project.level}
              </strong>
              <button className="pm-project-location" onClick={() => select(project.sectorId)}>
                {c.sectors.find((s) => s.id === project.sectorId)?.name}
              </button>
            </div>
            <progress
              value={project.total - project.remaining}
              max={project.total}
              aria-label="Baufortschritt"
            />
            <span>
              {game.paused
                ? 'Pausiert'
                : `${Math.ceil(project.remaining / Math.max(0.1, 1 + empireModifiers(game.me.empire).construction))} Tage`}
            </span>
            <button
              disabled={!connected}
              onClick={() => order({ type: 'colony_cancel' })}
              title="Bau abbrechen · 50 % der Baukosten zurück"
            >
              <X size={14} />
              Abbrechen
            </button>
          </>
        ) : (
          <>
            <Check size={15} />
            <span>Kein Bauauftrag</span>
            <small>Wähle einen Sektor, um deine Kolonie auszubauen.</small>
          </>
        )}
      </footer>
    </>
  );
}
