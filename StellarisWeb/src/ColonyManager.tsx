import {
  ArrowRight,
  Check,
  CircleHelp,
  Factory,
  FlaskConical,
  Globe2,
  Hammer,
  Shield,
  Users,
  X,
  Zap,
  Diamond,
} from 'lucide-react';
import type { GameCommand, GameView, Resource } from '../shared/game';
import { populationGrowth, empireModifiers } from '../shared/empireState';
import { environmentForPlanet } from '../shared/empires';
import {
  BUILDINGS,
  FOCUSES,
  colonyProduction,
  districtCapacity,
  maxDefense,
  occupiedDistricts,
  upgradeSpec,
  type BuildingId,
  type ColonyFocus,
} from '../shared/colonies';

const buildingIcons = { reactor: Zap, foundry: Factory, laboratory: FlaskConical, bastion: Shield };
const focusIcons = { balanced: Globe2, energy: Zap, minerals: Factory, science: FlaskConical };
const number = (n: number) => n.toLocaleString('de-DE', { maximumFractionDigits: 1 });

export function ColonyManager({
  game,
  selected,
  onSelect,
  command,
}: {
  game: GameView;
  selected: string;
  onSelect: (id: string) => void;
  command: (command: GameCommand) => void;
}) {
  const colonies = game.systems.filter((s) => s.owner === game.me.id);
  const system = colonies.find((s) => s.id === selected) || colonies[0];
  const colony = system?.colony;
  if (!system || !colony)
    return (
      <div className="colony-empty">
        <Globe2 size={36} />
        <h2 id="dialog-title">Eine Welt für dein Imperium</h2>
        <p>Untersuche ein System und entsende ein Kolonieschiff, um eine neue Kolonie zu gründen.</p>
      </div>
    );
  const production = colonyProduction(system, game.me);
  const growthPerMinute =
    0.25 *
    (colony.populations?.reduce(
      (sum, group) =>
        sum +
        (group.population / Math.max(0.01, colony.population)) *
          populationGrowth(game.me.empire, group.speciesId, environmentForPlanet(system.planet)),
      0,
    ) ?? 1);
  const capacity = districtCapacity(colony),
    used = occupiedDistricts(colony);
  const project = colony.construction;
  return (
    <div className="colony-console">
      <header className="colony-console-header">
        <span className="eyebrow">PLANETARE VERWALTUNG</span>
        <h2 id="dialog-title">Welten, die Zukunft schaffen.</h2>
        <p>Eine Kolonie. Tausend Möglichkeiten.</p>
      </header>
      <div className="colony-switcher" role="tablist" aria-label="Kolonie auswählen">
        {colonies.map((s) => (
          <button key={s.id} role="tab" aria-selected={s.id === system.id} onClick={() => onSelect(s.id)}>
            <Globe2 size={14} />
            {s.name === 'Sol' ? 'Terra' : s.name}
            {s.id === game.me.home && <span>HAUPTWELT</span>}
          </button>
        ))}
      </div>
      <div className="colony-workspace">
        <aside className="colony-profile">
          <div className="colony-portrait">
            <div className="portrait-orbit" />
            <div className="portrait-orbit second" />
            <div
              className={`planet-sphere colony-world world-${system.planet === 'Wüstenwelt' ? 'desert' : system.planet === 'Ozeanwelt' ? 'ocean' : 'temperate'}`}
            >
              <div className="planet-clouds" />
            </div>
            <span className="portrait-coordinate">
              {system.x} : {system.y} · ORION
            </span>
            <span className="planet-cross">+</span>
          </div>
          <span className="eyebrow">
            {system.id === game.me.home ? 'SITZ DEINER ZIVILISATION' : 'EINE NEUE HEIMAT'}
          </span>
          <h3>{system.colonyName || (system.name === 'Sol' ? 'Terra' : `${system.name} Prime`)}</h3>
          <p className="colony-world-type">
            {system.planet} <span>·</span> {system.name}
          </p>
          <div className="colony-population">
            <Users size={17} />
            <div>
              <span>BEVÖLKERUNG</span>
              <strong>
                {number(colony.population)} <small>Mrd.</small>
              </strong>
            </div>
            <span className="growth">
              {colony.population < 12
                ? `+${growthPerMinute.toLocaleString('de-DE', { maximumFractionDigits: 2 })} / Spielmin.`
                : 'Maximum'}
            </span>
          </div>
          <div className="population-track">
            <i style={{ width: `${(colony.population / 12) * 100}%` }} />
          </div>
          {colony.populations?.map((group) => (
            <div className="colony-stat" key={group.speciesId}>
              <span>
                {game.me.empire?.species.find((s) => s.id === group.speciesId)?.name || 'Bevölkerung'}
              </span>
              <strong>{number(group.population)}</strong>
            </div>
          ))}
          <div className="colony-stat">
            <span>
              <Shield size={13} />
              Planetare Verteidigung
            </span>
            <strong>
              {Math.ceil(system.defense)} / {maxDefense(system)}
            </strong>
          </div>
          <div className="colony-stat">
            <span>
              <Factory size={13} />
              Distrikte
            </span>
            <strong>
              {used}
              {project ? ' +1' : ''} / {capacity}
            </strong>
          </div>
          <div className="district-slots" aria-label={`${used} von ${capacity} Distrikten belegt`}>
            {Array.from({ length: capacity }, (_, i) => (
              <i key={i} className={i < used ? 'filled' : i === used && project ? 'building' : ''} />
            ))}
          </div>
          <p className="colony-tip">
            <CircleHelp size={12} />
            <span>Je zwei Milliarden Einwohner schaffen einen zusätzlichen Distrikt. Maximum: zehn.</span>
          </p>
          <div className="repair-notice">
            <Check size={13} />
            <span>
              Eigene Schiffe reparieren hier im Frieden{' '}
              <strong>{number(1.5 + colony.buildings.bastion)} Hülle / s.</strong>
            </span>
          </div>
        </aside>
        <section className="colony-development">
          <div className="development-heading">
            <span className="eyebrow">LOKALE PRODUKTION</span>
            <span>pro 4 Spielsekunden</span>
          </div>
          <div className="production-cards">
            {(['energy', 'minerals', 'science'] as Resource[]).map((r, i) => {
              const Icon = [Zap, Diamond, FlaskConical][i];
              return (
                <div key={r} className={r}>
                  <Icon size={18} />
                  <span>{['ENERGIE', 'MINERALIEN', 'FORSCHUNG'][i]}</span>
                  <strong>+{number(production[r])}</strong>
                </div>
              );
            })}
          </div>
          <div className="focus-heading">
            <span className="eyebrow">PRODUKTIONSSCHWERPUNKT</span>
            <span className="focus-active">{FOCUSES[colony.focus].name}</span>
          </div>
          <div className="focus-options" role="group" aria-label="Produktionsschwerpunkt">
            {(Object.keys(FOCUSES) as ColonyFocus[]).map((id) => {
              const Icon = focusIcons[id];
              return (
                <button
                  key={id}
                  aria-pressed={colony.focus === id}
                  disabled={!!game.winner}
                  onClick={() => command({ type: 'colony_focus', systemId: system.id, focus: id })}
                >
                  <Icon size={13} />
                  {FOCUSES[id].name}
                </button>
              );
            })}
          </div>
          <p className="focus-description">{FOCUSES[colony.focus].description}</p>
          {project ? (
            <div className="colony-project">
              <div className="project-icon">
                <Hammer size={19} />
              </div>
              <div>
                <span className="eyebrow">PLANETARER BAUAUFTRAG</span>
                <strong>
                  {BUILDINGS[project.building].name}{' '}
                  <span>Stufe {colony.buildings[project.building] + 1}</span>
                </strong>
                <div
                  className="project-progress"
                  role="progressbar"
                  aria-label="Kolonieausbau"
                  aria-valuenow={Math.round((1 - project.remaining / project.total) * 100)}
                  aria-valuemin={0}
                  aria-valuemax={100}
                >
                  <i style={{ width: `${(1 - project.remaining / project.total) * 100}%` }} />
                </div>
              </div>
              <span className="project-time">
                {Math.ceil(
                  project.remaining / Math.max(0.1, 1 + empireModifiers(game.me.empire).construction),
                )}
                <small>s</small>
              </span>
              <button
                className="icon-button"
                aria-label="Kolonieausbau abbrechen"
                title="Abbrechen: 50 % der Baukosten werden erstattet."
                onClick={() => command({ type: 'colony_cancel', systemId: system.id })}
              >
                <X size={15} />
              </button>
            </div>
          ) : (
            <div className="construction-idle">
              <Hammer size={14} />
              <span>Baudrohnen bereit. Wähle deinen nächsten Ausbau.</span>
            </div>
          )}
          <div className="development-heading">
            <span className="eyebrow">INFRASTRUKTUR</span>
            <span>{capacity - used - (project ? 1 : 0)} freie Distrikte</span>
          </div>
          <div className="building-grid">
            {(Object.keys(BUILDINGS) as BuildingId[]).map((id) => {
              const spec = BUILDINGS[id],
                Icon = buildingIcons[id],
                level = colony.buildings[id],
                upgrade = upgradeSpec(colony, id);
              const max = level >= spec.maxLevel,
                active = project?.building === id;
              const affordable =
                game.me.resources.energy >= upgrade.cost.energy &&
                game.me.resources.minerals >= upgrade.cost.minerals;
              const reason = game.winner
                ? 'Partie beendet'
                : max
                  ? 'Vollständig ausgebaut'
                  : project
                    ? 'Ein Ausbau läuft bereits'
                    : used >= capacity
                      ? 'Keine freien Distrikte'
                      : !affordable
                        ? 'Ressourcen fehlen'
                        : null;
              return (
                <article key={id} className={`building-card ${active ? 'under-construction' : ''}`}>
                  <div className="building-card-header">
                    <span className={`building-symbol ${id}`}>
                      <Icon size={20} />
                    </span>
                    <div>
                      <span className="eyebrow">{spec.field}</span>
                      <h4>{spec.name}</h4>
                    </div>
                    <div className="building-levels" aria-label={`Stufe ${level} von 3`}>
                      {[1, 2, 3].map((n) => (
                        <i
                          key={n}
                          className={n <= level ? 'built' : active && n === level + 1 ? 'pending' : ''}
                        />
                      ))}
                    </div>
                  </div>
                  <p>{spec.description}</p>
                  <div className="building-cost">
                    {!max && (
                      <>
                        <span>
                          <Zap size={11} />
                          {upgrade.cost.energy}
                        </span>
                        <span>
                          <Diamond size={11} />
                          {upgrade.cost.minerals}
                        </span>
                        <span>
                          {Math.ceil(
                            upgrade.time / Math.max(0.1, 1 + empireModifiers(game.me.empire).construction),
                          )}{' '}
                          s
                        </span>
                      </>
                    )}
                    {max && (
                      <span>
                        <Check size={12} />
                        Maximale Ausbaustufe
                      </span>
                    )}
                  </div>
                  <button
                    className={max ? 'building-complete' : 'secondary-button'}
                    disabled={!!reason}
                    title={reason || `${spec.name} auf Stufe ${level + 1} ausbauen`}
                    aria-label={`${spec.name} ausbauen`}
                    onClick={() => command({ type: 'colony_upgrade', systemId: system.id, building: id })}
                  >
                    {max ? (
                      <>
                        <Check size={13} />
                        Vollständig ausgebaut
                      </>
                    ) : active ? (
                      <>
                        <Hammer size={13} />
                        Im Bau
                      </>
                    ) : (
                      <>
                        {level === 0 ? 'Errichten' : `Auf Stufe ${level + 1} ausbauen`}
                        <ArrowRight size={13} />
                      </>
                    )}
                  </button>
                </article>
              );
            })}
          </div>
          <p className="colony-footnote">
            Die Erträge berücksichtigen Bergbau, Schwerpunkt und Technologien. Pro Kolonie kann ein Ausbau
            laufen; Raumwerften arbeiten unabhängig.
          </p>
        </section>
      </div>
    </div>
  );
}
