import type { GameState, Player, Resources, StarSystem } from './game';
import { RESOURCE_IDS } from './resources';
import { economyLine } from './economy';

export const STARBASE_TIERS = [
  { name: 'Bauplatz', slots: 0, defense: 0, upkeep: 0, cost: { energy: 100, minerals: 150 }, days: 24 },
  { name: 'Außenposten', slots: 0, defense: 40, upkeep: 1, cost: { energy: 200, minerals: 300 }, days: 40 },
  { name: 'Sternenhafen', slots: 2, defense: 100, upkeep: 3, cost: { energy: 400, minerals: 600 }, days: 60 },
  {
    name: 'Sternenfestung',
    slots: 4,
    defense: 220,
    upkeep: 6,
    cost: { energy: 800, minerals: 1000 },
    days: 90,
  },
  { name: 'Zitadelle', slots: 6, defense: 400, upkeep: 10, cost: { energy: 0, minerals: 0 }, days: 0 },
] as const;
export const STARBASE_MODULES = {
  shipyard: {
    name: 'Raumwerft',
    description: 'Schiffsbau; jede zusätzliche Werftstufe erhöht das Bautempo um 25 %.',
    cost: { energy: 100, minerals: 160 },
    days: 24,
    defense: 0,
    repair: 1,
    upkeep: 2,
    income: 0,
  },
  battery: {
    name: 'Geschützbatterie',
    description: '+80 Systemverteidigung je Modulstufe.',
    cost: { energy: 80, minerals: 140 },
    days: 20,
    defense: 80,
    repair: 0,
    upkeep: 1,
    income: 0,
  },
  anchorage: {
    name: 'Versorgungsdock',
    description: '+2 Hüllenreparatur pro Tag und Modulstufe.',
    cost: { energy: 100, minerals: 100 },
    days: 20,
    defense: 0,
    repair: 2,
    upkeep: 1,
    income: 0,
  },
  trade: {
    name: 'Handelszentrum',
    description: '+8 Energie pro Monat und Modulstufe.',
    cost: { energy: 140, minerals: 120 },
    days: 28,
    defense: 0,
    repair: 0,
    upkeep: 2,
    income: 8,
  },
} as const;
export type StarbaseModule = keyof typeof STARBASE_MODULES;
export interface Starbase {
  owner: string;
  level: number;
  revision: number;
  modules: { slot: number; type: StarbaseModule; level: number }[];
  project: {
    kind: 'upgrade' | 'module';
    module?: StarbaseModule;
    slot?: number;
    startedAt: number;
    finishAt: number;
    paid: Resources;
  } | null;
}
export type StarbaseCommand =
  | { type: 'starbase_build'; systemId: string }
  | { type: 'starbase_upgrade' | 'starbase_cancel'; systemId: string; revision: number }
  | { type: 'starbase_module'; systemId: string; revision: number; slot: number; module: StarbaseModule }
  | { type: 'starbase_remove'; systemId: string; revision: number; slot: number };
export function createStarbase(owner: string, home = false): Starbase {
  return {
    owner,
    level: home ? 2 : 0,
    revision: 1,
    modules: home ? [{ slot: 0, type: 'shipyard', level: 1 }] : [],
    project: null,
  };
}
export function starbaseDefense(base?: Starbase | null) {
  return base
    ? STARBASE_TIERS[base.level].defense +
        base.modules.reduce((n, m) => n + STARBASE_MODULES[m.type].defense * m.level, 0)
    : 0;
}
export function starbaseRepair(base?: Starbase | null) {
  return base?.level
    ? 1 + base.modules.reduce((n, m) => n + STARBASE_MODULES[m.type].repair * m.level, 0)
    : 0;
}
export function shipyardSpeed(system: StarSystem) {
  const levels = system.starbase?.modules.reduce((n, m) => n + (m.type === 'shipyard' ? m.level : 0), 0) ?? 0;
  return 1 + Math.max(0, levels - 1) * 0.25;
}
export function hasShipyard(system: StarSystem) {
  return !!system.starbase?.level && system.starbase.modules.some((m) => m.type === 'shipyard');
}
export function starbaseLedger(system: StarSystem) {
  const b = system.starbase;
  if (!b?.level) return [];
  const upkeep =
    STARBASE_TIERS[b.level].upkeep +
    b.modules.reduce((n, m) => n + STARBASE_MODULES[m.type].upkeep * m.level, 0);
  const income = b.modules.reduce((n, m) => n + STARBASE_MODULES[m.type].income * m.level, 0);
  return [
    economyLine(
      `base:${system.id}:upkeep`,
      `${system.name} · Basisunterhalt`,
      upkeep,
      [],
      { category: 'installations', resource: 'energy' },
      true,
    ),
    economyLine(`base:${system.id}:trade`, `${system.name} · Handelszentrum`, income, [], {
      category: 'installations',
      resource: 'energy',
    }),
  ].map((line) => ({ ...line, systemId: system.id }));
}
export function applyStarbaseCommand(game: GameState, player: Player, cmd: StarbaseCommand) {
  if (
    !['starbase_build', 'starbase_upgrade', 'starbase_cancel', 'starbase_module', 'starbase_remove'].includes(
      cmd.type,
    )
  )
    throw new Error('Unbekannter Sternenbasisbefehl.');
  const s = game.systems.find((s) => s.id === cmd.systemId);
  if (!s) throw new Error('System nicht gefunden.');
  let b = s.starbase;
  if (cmd.type === 'starbase_build') {
    if (s.owner || b) throw new Error('Dieses System ist bereits beansprucht oder im Bau.');
    if (!player.surveyed.includes(s.id)) throw new Error('Untersuche zuerst alle Himmelskörper.');
    if (s.defense > 0) throw new Error('Besiege zuerst die Systemwächter.');
    b = createStarbase(player.id);
    b.revision = (s.starbaseRevision ?? 0) + 1;
  } else {
    if (!b || b.owner !== player.id || (b.level > 0 && s.owner !== player.id))
      throw new Error('Keine eigene Sternenbasis.');
    if (!Number.isSafeInteger(cmd.revision) || cmd.revision !== b.revision)
      throw new Error('Sternenbasis wurde inzwischen verändert.');
  }
  if (cmd.type === 'starbase_cancel') {
    if (!b.project) throw new Error('Kein laufender Basisbau.');
    for (const r of RESOURCE_IDS)
      player.resources[r] = (player.resources[r] ?? 0) + (b.project.paid[r] ?? 0) / 2;
    b.project = null;
    b.revision++;
    s.starbaseRevision = b.revision;
    if (!b.level) s.starbase = null;
    return;
  }
  if (b.project) throw new Error('Die Sternenbasis hat bereits einen Bauauftrag.');
  if (cmd.type === 'starbase_remove') {
    const installed = b.modules.find((m) => m.slot === cmd.slot);
    if (!Number.isSafeInteger(cmd.slot) || !installed) throw new Error('Ungültiger Modulplatz.');
    if (installed.type === 'shipyard' && player.queue.some((q) => q.systemId === s.id))
      throw new Error('Die Werft hat noch Schiffsbauaufträge.');
    b.modules = b.modules.filter((m) => m.slot !== cmd.slot);
    b.revision++;
    s.starbaseRevision = b.revision;
    return;
  }
  let spec: { cost: { energy: number; minerals: number }; days: number } = STARBASE_TIERS[b.level];
  let project: Starbase['project'] = null;
  if (cmd.type === 'starbase_module') {
    if (
      !Object.hasOwn(STARBASE_MODULES, cmd.module) ||
      !Number.isSafeInteger(cmd.slot) ||
      cmd.slot < 0 ||
      cmd.slot >= STARBASE_TIERS[b.level].slots
    )
      throw new Error('Ungültiger oder gesperrter Modulplatz.');
    const old = b.modules.find((m) => m.slot === cmd.slot);
    if (old && (old.type !== cmd.module || old.level >= 3))
      throw new Error('Modul bereits belegt oder maximal ausgebaut.');
    const def = STARBASE_MODULES[cmd.module],
      multiplier = 1 + (old?.level ?? 0);
    spec = {
      cost: { energy: def.cost.energy * multiplier, minerals: def.cost.minerals * multiplier },
      days: def.days * multiplier,
    };
    project = {
      kind: 'module',
      module: cmd.module,
      slot: cmd.slot,
      startedAt: game.tick,
      finishAt: game.tick + spec.days,
      paid: spec.cost,
    };
  } else {
    if (b.level >= 4) throw new Error('Maximale Basisstufe erreicht.');
    project = { kind: 'upgrade', startedAt: game.tick, finishAt: game.tick + spec.days, paid: spec.cost };
  }
  if (player.resources.energy < spec.cost.energy || player.resources.minerals < spec.cost.minerals)
    throw new Error('Nicht genug Energie oder Mineralien.');
  player.resources.energy -= spec.cost.energy;
  player.resources.minerals -= spec.cost.minerals;
  b.project = project;
  b.revision++;
  s.starbaseRevision = b.revision;
  s.starbase = b;
}
export function completeStarbase(system: StarSystem, at: number) {
  const b = system.starbase,
    project = b?.project;
  if (!b || !project || project.finishAt > at) return false;
  if ((b.level && system.owner !== b.owner) || (!b.level && system.owner)) {
    system.starbase = null;
    return false;
  }
  const before = starbaseDefense(b);
  if (project.kind === 'upgrade') b.level++;
  else if (project.module !== undefined && project.slot !== undefined) {
    const old = b.modules.find((m) => m.slot === project.slot);
    if (old) old.level++;
    else b.modules.push({ slot: project.slot, type: project.module, level: 1 });
  }
  system.owner = b.owner;
  system.defense += starbaseDefense(b) - before;
  b.project = null;
  b.revision++;
  system.starbaseRevision = b.revision;
  return true;
}
