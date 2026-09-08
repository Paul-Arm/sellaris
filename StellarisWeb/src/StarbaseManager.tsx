import { maxDefense, colonyRepair } from '../shared/colonies';
import { empireModifiers } from '../shared/empireState';
import { useEffect, useRef, useState } from 'react';
import {
  Orbit,
  Shield,
  Rocket,
  X,
  Plus,
  ArrowUpRight,
  Anchor,
  ShoppingBag,
  Hammer,
  Radar,
  Home,
} from 'lucide-react';
import { SHIPS, type GameCommand, type GameView, type StarSystem, type ShipType } from '../shared/game';
import {
  STARBASE_TIERS,
  STARBASE_MODULES,
  hasShipyard,
  shipyardSpeed,
  starbaseLedger,
  type StarbaseModule,
} from '../shared/starbases';
import { economyTotals } from '../shared/economy';
import { BuildSlot, SlotPicker } from './BuildSlots';
import './starbase-manager.css';
const moduleIcons = { shipyard: Rocket, battery: Shield, anchorage: Anchor, trade: ShoppingBag };
const shipIcons = { scout: Radar, colony: Home, corvette: Rocket };
const costLabel = (cost: { energy: number; minerals: number }, days: number) =>
  `${cost.energy} Energie · ${cost.minerals} Mineralien · ${days} T`;
export function StarbaseControl({
  game,
  system,
  command,
  disabled = false,
}: {
  game: GameView;
  system: StarSystem;
  command: (c: GameCommand) => void;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const base = system.starbase,
    own = base?.owner === game.me.id;
  const surveyed = game.me.surveyed.includes(system.id);
  return (
    <>
      <button
        className="secondary-button wide starbase-entry"
        disabled={disabled || (!surveyed && !own)}
        onClick={() => setOpen(true)}
      >
        <Orbit size={17} />
        <span>
          {own ? STARBASE_TIERS[base.level].name : system.owner ? 'Sternenbasis' : 'Außenposten errichten'}
          <small>
            {base?.project
              ? 'Bauauftrag läuft'
              : own
                ? 'Module, Ausbau & Raumwerft'
                : surveyed
                  ? 'Systembesitz & Infrastruktur'
                  : 'Zuerst System erkunden'}
          </small>
        </span>
        <ArrowUpRight size={15} />
      </button>
      {open && (
        <StarbaseManager
          game={game}
          system={system}
          command={command}
          disabled={disabled}
          close={() => setOpen(false)}
        />
      )}
    </>
  );
}
function StarbaseManager({
  game,
  system,
  command,
  disabled,
  close,
}: {
  game: GameView;
  system: StarSystem;
  command: (c: GameCommand) => void;
  disabled: boolean;
  close: () => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [tab, setTab] = useState<'modules' | 'shipyard'>('modules');
  const [selected, setSelected] = useState<number | null>(null);
  const [picking, setPicking] = useState<number | null>(null);
  const [shipPicker, setShipPicker] = useState(false);
  useEffect(() => {
    const d = dialog.current!;
    d.showModal();
    return () => d.close();
  }, []);
  const base = system.starbase,
    own = base?.owner === game.me.id;
  const level = base?.level ?? system.starbaseLevel ?? 0,
    tier = STARBASE_TIERS[level];
  const project = own ? base.project : null;
  const installed = own ? base.modules.find((m) => m.slot === selected) : undefined;
  const spec = installed && STARBASE_MODULES[installed.type];
  const affordable = (cost: { energy: number; minerals: number }) =>
    game.me.resources.energy >= cost.energy && game.me.resources.minerals >= cost.minerals;
  const canClaim = !system.owner && !base && game.me.surveyed.includes(system.id) && system.defense <= 0;
  const selectSlot = (slot: number) => {
    setSelected(slot);
    if (!base?.modules.some((m) => m.slot === slot) && !project) setPicking(slot);
  };
  return (
    <dialog
      ref={dialog}
      className="starbase-dialog"
      onCancel={close}
      aria-labelledby="starbase-title"
      onKeyDown={(e) => e.stopPropagation()}
    >
      <header className="starbase-header">
        <div>
          <span className="eyebrow">{system.name.toUpperCase()} · SYSTEMKOMMANDO</span>
          <h2 id="starbase-title">{level ? tier.name : 'Außenposten errichten'}</h2>
          <p>
            {own && level
              ? 'System gesichert · Wähle einen Andockplatz, um deine Basis auszustatten.'
              : 'Ein fertiger Außenposten sichert das gesamte System.'}
          </p>
        </div>
        <button className="icon-button" aria-label="Sternenbasis schließen" onClick={close}>
          <X />
        </button>
      </header>
      {own && level > 0 && (
        <div className="starbase-stats">
          <span>
            <Shield size={16} />
            <strong>
              {Math.ceil(system.defense)} / {maxDefense(system)}
            </strong>
            <small>Verteidigung</small>
          </span>
          <span>
            <Anchor size={16} />
            <strong>{colonyRepair(system)}</strong>
            <small>Reparatur / Tag</small>
          </span>
          <span>
            <ShoppingBag size={16} />
            <strong>{economyTotals(starbaseLedger(system)).energy}</strong>
            <small>Energie / Monat</small>
          </span>
          <span>
            <Orbit size={16} />
            <strong>
              {base.modules.length} / {tier.slots}
            </strong>
            <small>Module belegt</small>
          </span>
        </div>
      )}
      <main className="starbase-content">
        {!own && !system.owner && (
          <section className="starbase-claim">
            <div className="starbase-claim-slot">
              <BuildSlot
                label="SYSTEMZENTRUM"
                name="Außenposten"
                icon={<Orbit />}
                state="empty"
                onClick={() => setPicking(0)}
              />
            </div>
            <h3>Hier beginnt dein Territorium</h3>
            <p>Außenposten einsetzen, System sichern und Planeten besiedeln.</p>
            <small>
              {costLabel(STARBASE_TIERS[0].cost, STARBASE_TIERS[0].days)} · 1 Energie Unterhalt / Monat
            </small>
            {!game.me.surveyed.includes(system.id) && <p>Erkunde zuerst alle Himmelskörper.</p>}
            {system.defense > 0 && <p>Besiege zuerst die Systemwächter.</p>}
            {base && <p>Hier wird bereits ein Außenposten errichtet.</p>}
          </section>
        )}
        {own && (
          <>
            <nav className="starbase-tabs" aria-label="Basisbereiche">
              <button aria-pressed={tab === 'modules'} onClick={() => setTab('modules')}>
                <Orbit size={15} />
                Stationsplan
              </button>
              <button aria-pressed={tab === 'shipyard'} onClick={() => setTab('shipyard')}>
                <Rocket size={15} />
                Raumwerft
              </button>
            </nav>
            {tab === 'modules' ? (
              <>
                <div className="starbase-plan" aria-label="Andockplätze der Sternenbasis">
                  <div className="starbase-core" aria-hidden="true">
                    <svg viewBox="0 0 240 300" fill="none">
                      <ellipse cx="120" cy="150" rx="105" ry="118" stroke="#426574" strokeDasharray="3 8" />
                      <path
                        d="M20 60 85 112M220 60 155 112M0 150H78M162 150H240M20 240 85 188M220 240 155 188"
                        stroke="#506d7a"
                        strokeWidth="5"
                      />
                      <path
                        d="m120 48 55 35 22 67-22 67-55 35-55-35-22-67 22-67Z"
                        fill="#152b37"
                        stroke="#78a8aa"
                        strokeWidth="2"
                      />
                      <path
                        d="m120 75 37 23 17 52-17 52-37 23-37-23-17-52 17-52Z"
                        stroke="#476771"
                        strokeWidth="10"
                      />
                      <path d="M120 83v134M64 150h112" stroke="#729f9f" strokeWidth="3" />
                      <path
                        d="m120 113 31 18v38l-31 18-31-18v-38Z"
                        fill="#234850"
                        stroke="#afe6d4"
                        strokeWidth="2"
                      />
                      <circle cx="120" cy="150" r="13" fill="#a7ebdc" />
                      {[83, 217].map((y) => (
                        <path key={y} d={`M101 ${y}h38`} stroke="#c4e9df" strokeWidth="4" />
                      ))}
                    </svg>
                    <strong>{system.name}</strong>
                    <small>
                      {tier.name} · Stufe {level}
                    </small>
                  </div>
                  {Array.from({ length: 6 }, (_, slot) => {
                    const m = base.modules.find((m) => m.slot === slot),
                      pending = project?.kind === 'module' && project.slot === slot;
                    const type = m?.type ?? (pending ? project.module : undefined),
                      Icon = type ? moduleIcons[type] : Plus;
                    const locked = slot >= tier.slots;
                    return (
                      <div
                        className="starbase-port"
                        key={slot}
                        style={{ gridColumn: slot % 2 ? 3 : 1, gridRow: Math.floor(slot / 2) + 1 }}
                      >
                        <BuildSlot
                          label={`SLOT ${String(slot + 1).padStart(2, '0')}`}
                          name={
                            locked
                              ? slot < 2
                                ? 'Sternenhafen'
                                : slot < 4
                                  ? 'Sternenfestung'
                                  : 'Zitadelle'
                              : type
                                ? STARBASE_MODULES[type].name
                                : 'Freier Andockplatz'
                          }
                          state={locked ? 'locked' : pending ? 'building' : m ? 'occupied' : 'empty'}
                          icon={<Icon />}
                          level={m?.level}
                          selected={selected === slot}
                          detail={
                            locked
                              ? 'Durch Ausbau freischalten'
                              : pending
                                ? `${Math.max(0, Math.ceil(project.finishAt - game.tick))} T · ${game.paused ? 'Pausiert' : 'Im Bau'}`
                                : m
                                  ? 'Modul verwalten'
                                  : project
                                    ? 'Bauauftrag läuft'
                                    : undefined
                          }
                          onClick={() => selectSlot(slot)}
                        />
                      </div>
                    );
                  })}
                </div>
                {installed && spec && (
                  <section className="starbase-module-detail" aria-label="Gewähltes Modul">
                    <div>
                      <span className="eyebrow">
                        SLOT {installed.slot + 1} · STUFE {installed.level} / 3
                      </span>
                      <h3>{spec.name}</h3>
                      <p>{spec.description}</p>
                      <small>{spec.upkeep * installed.level} Energie Unterhalt / Monat</small>
                    </div>
                    <div className="starbase-module-actions">
                      <button
                        disabled={
                          disabled ||
                          !!project ||
                          installed.level >= 3 ||
                          !affordable({
                            energy: spec.cost.energy * (installed.level + 1),
                            minerals: spec.cost.minerals * (installed.level + 1),
                          })
                        }
                        onClick={() =>
                          command({
                            type: 'starbase_module',
                            systemId: system.id,
                            revision: base.revision,
                            slot: installed.slot,
                            module: installed.type,
                          })
                        }
                      >
                        {installed.level >= 3 ? 'Maximal ausgebaut' : 'Modul ausbauen'}
                      </button>
                      {installed.level < 3 && (
                        <small>
                          {costLabel(
                            {
                              energy: spec.cost.energy * (installed.level + 1),
                              minerals: spec.cost.minerals * (installed.level + 1),
                            },
                            spec.days * (installed.level + 1),
                          )}
                        </small>
                      )}
                      <button
                        disabled={
                          disabled ||
                          !!project ||
                          (installed.type === 'shipyard' &&
                            game.me.queue.some((q) => q.systemId === system.id))
                        }
                        onClick={() =>
                          command({
                            type: 'starbase_remove',
                            systemId: system.id,
                            revision: base.revision,
                            slot: installed.slot,
                          })
                        }
                      >
                        Modul entfernen
                      </button>
                      <small>Keine Erstattung beim Entfernen</small>
                    </div>
                  </section>
                )}
              </>
            ) : (
              <section className="starbase-shipyard">
                <h3>
                  Fertigungsaufträge <small>{game.me.queue.length} / 5</small>
                </h3>
                <p>
                  {hasShipyard(system)
                    ? 'Wähle einen freien Auftragsslot und setze ein Schiff ein. Dein Reich baut die Aufträge nacheinander.'
                    : 'Belege zuerst einen Andockplatz mit einer Raumwerft.'}
                </p>
                <div className="starbase-queue-slots">
                  {Array.from({ length: 5 }, (_, i) => {
                    const q = game.me.queue[i],
                      Icon = q ? shipIcons[q.type] : Plus;
                    return (
                      <BuildSlot
                        key={i}
                        label={`AUFTRAG ${i + 1}`}
                        name={q ? SHIPS[q.type].name : 'Schiff einsetzen'}
                        state={q ? 'building' : hasShipyard(system) ? 'empty' : 'locked'}
                        icon={<Icon />}
                        detail={
                          q
                            ? `${game.systems.find((s) => s.id === q.systemId)?.name ?? 'Andere Basis'} · ${Math.ceil(q.remaining / Math.max(0.1, 1 + empireModifiers(game.me.empire).construction))} T`
                            : undefined
                        }
                        onClick={() => {
                          if (!q) setShipPicker(true);
                        }}
                      />
                    );
                  })}
                </div>
              </section>
            )}
            {project ? (
              <section className="starbase-project" role="status">
                <div>
                  <h3>
                    <Hammer size={16} />{' '}
                    {project.kind === 'upgrade'
                      ? STARBASE_TIERS[level + 1].name
                      : STARBASE_MODULES[project.module!].name}{' '}
                    im Bau
                  </h3>
                  <strong>{Math.max(0, Math.ceil(project.finishAt - game.tick))} T</strong>
                </div>
                <progress
                  aria-label="Basisbaufortschritt"
                  max={project.finishAt - project.startedAt}
                  value={Math.max(0, game.tick - project.startedAt)}
                />
                <div>
                  <small>{game.paused ? 'Spiel pausiert' : 'Bau läuft'} · Abbruch erstattet 50 %.</small>
                  <button
                    disabled={disabled}
                    onClick={() =>
                      command({ type: 'starbase_cancel', systemId: system.id, revision: base.revision })
                    }
                  >
                    Bau abbrechen
                  </button>
                </div>
              </section>
            ) : (
              level < 4 && (
                <section className="starbase-upgrade">
                  <div>
                    <span className="eyebrow">NÄCHSTE AUSBAUSTUFE</span>
                    <h3>{STARBASE_TIERS[level + 1].name}</h3>
                    <small>
                      {STARBASE_TIERS[level + 1].slots} Modulplätze · {costLabel(tier.cost, tier.days)}
                    </small>
                  </div>
                  <button
                    className="primary-button"
                    disabled={disabled || !affordable(tier.cost)}
                    onClick={() =>
                      command({ type: 'starbase_upgrade', systemId: system.id, revision: base.revision })
                    }
                  >
                    <ArrowUpRight size={15} />
                    Basis ausbauen
                  </button>
                </section>
              )
            )}
          </>
        )}
        {!own && system.owner && <p>Die Module und Bauaufträge fremder Sternenbasen sind privat.</p>}
      </main>
      {picking !== null && (
        <SlotPicker
          title={own ? `Andockplatz ${picking + 1} bestücken` : 'Außenposten einsetzen'}
          subtitle={
            own
              ? 'Wähle die Aufgabe dieses Platzes. Jedes Modul lässt sich später ausbauen.'
              : 'Nach Bauabschluss gehört dieses System deinem Reich.'
          }
          close={() => setPicking(null)}
        >
          {own ? (
            (Object.keys(STARBASE_MODULES) as StarbaseModule[]).map((id) => {
              const d = STARBASE_MODULES[id],
                Icon = moduleIcons[id];
              return (
                <button
                  className="slot-choice"
                  key={id}
                  disabled={
                    disabled ||
                    !!project ||
                    base.modules.some((m) => m.slot === picking) ||
                    !affordable(d.cost)
                  }
                  onClick={() => {
                    command({
                      type: 'starbase_module',
                      systemId: system.id,
                      revision: base.revision,
                      slot: picking,
                      module: id,
                    });
                    setPicking(null);
                  }}
                >
                  <Icon />
                  <strong>{d.name}</strong>
                  <small>{d.description}</small>
                  <span className="slot-choice-cost">{costLabel(d.cost, d.days)}</span>
                  <small>{d.upkeep} Energie Unterhalt / Monat</small>
                  {!affordable(d.cost) && <small>Rohstoffe fehlen</small>}
                </button>
              );
            })
          ) : (
            <button
              className="slot-choice"
              disabled={disabled || !canClaim || !affordable(STARBASE_TIERS[0].cost)}
              onClick={() => {
                command({ type: 'starbase_build', systemId: system.id });
                setPicking(null);
              }}
            >
              <Orbit />
              <strong>Außenposten bauen</strong>
              <small>40 Verteidigung · 1 Energie Unterhalt</small>
              <span className="slot-choice-cost">
                {costLabel(STARBASE_TIERS[0].cost, STARBASE_TIERS[0].days)}
              </span>
            </button>
          )}
        </SlotPicker>
      )}
      {shipPicker && (
        <SlotPicker
          title="Schiff in Auftrag geben"
          subtitle={`${system.name} · Nächster freier Fertigungsauftrag`}
          close={() => setShipPicker(false)}
        >
          {(Object.keys(SHIPS) as ShipType[]).map((id) => {
            const d = SHIPS[id],
              Icon = shipIcons[id];
            return (
              <button
                className="slot-choice"
                key={id}
                disabled={
                  disabled ||
                  !hasShipyard(system) ||
                  game.me.queue.length >= 5 ||
                  !affordable(d.cost as { energy: number; minerals: number })
                }
                onClick={() => {
                  command({ type: 'build', ship: id, systemId: system.id });
                  setShipPicker(false);
                }}
              >
                <Icon />
                <strong>{d.name}</strong>
                <span className="slot-choice-cost">
                  {costLabel(
                    d.cost as { energy: number; minerals: number },
                    Math.ceil(
                      d.time /
                        shipyardSpeed(system) /
                        Math.max(0.1, 1 + empireModifiers(game.me.empire).construction),
                    ),
                  )}
                </span>
              </button>
            );
          })}
        </SlotPicker>
      )}
    </dialog>
  );
}
