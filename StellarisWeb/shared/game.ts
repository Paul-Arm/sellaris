import {
  applyStarbaseCommand,
  completeStarbase,
  createStarbase,
  hasShipyard,
  shipyardSpeed,
  type StarbaseCommand,
} from './starbases';
import { empireLedger, empireCompute } from './empireEconomy';
import { economyTotals } from './economy';
import {
  BUILDINGS,
  baseIncome,
  createColony,
  assertColonies,
  maxDefense,
  colonyRepair,
  applyColonyCommand,
  completeColonyConstruction,
  growColony,
  planColonyDevelopment,
  COLONY_COMMANDS,
  type Colony,
  type ColonyCommand,
} from './colonies';

import { ORIGINS, ENVIRONMENTS } from './empireCatalog';
import {
  TECHS,
  applyResearch,
  advanceResearch,
  newResearch,
  type TechId,
  type ResearchProgram,
} from './research';
import { colonyEconomy } from './planetaryEconomy';
import { defaultFlag, type FlagDesign } from './flags';
import {
  newEmpire,
  newSpecies,
  environmentForPlanet,
  snapshotTemplate,
  starterLibrary,
  type TemplateSnapshot,
  type Government,
  type SpeciesDesign,
} from './empires';
import {
  instantiateEmpire,
  empireModifiers,
  populationGrowth,
  planReform,
  planShipSet,
  planSpeciesModification,
  REFORM_COST,
  MODIFICATION_COST,
  type EmpireState,
} from './empireState';

export const VERSION = 6;
export const WORLD = { width: 1600, height: 1050 };
export const WIN_SYSTEMS = 8;
export const COLORS = ['#9c91ff', '#58d9cf', '#f3b36b', '#ed7d9a'];
import { RESOURCE_IDS, resourceAmounts, type Resource, type Resources } from './resources';
import { monthsDue, ECONOMY_MONTH_DAYS } from './economy';
export type { Resource, Resources } from './resources';
export type ShipType = 'scout' | 'colony' | 'corvette';
export type { TechId } from './research';
export const SHIPS: Record<ShipType, { name: string; cost: Resources; time: number; power: number }> = {
  scout: { name: 'Forschungsschiff', cost: { energy: 60, minerals: 80, data: 0 }, time: 12, power: 10 },
  colony: { name: 'Kolonieschiff', cost: { energy: 100, minerals: 150, data: 0 }, time: 20, power: 12 },
  corvette: { name: 'Korvette', cost: { energy: 60, minerals: 100, data: 0 }, time: 15, power: 65 },
};
export { TECHS } from './research';
export interface StarSystem {
  starbase?: import('./starbases').Starbase | null;
  starbaseLevel?: number;
  starbaseRevision?: number;
  stellarWeather?: import('./stellarWeather').StellarWeather;
  planetDefense?: number;
  productionFactor?: number;
  id: string;
  name: string;
  x: number;
  y: number;
  color: string;
  kind: 'star' | 'rift' | 'blackhole';
  class: string;
  planet: string;
  owner: string | null;
  resources: Resources;
  defense: number;
  mined: boolean;
  anomaly: boolean;
  studied: boolean;
  colony?: Colony | null;
  colonyName?: string;
}
export interface Fleet {
  navigation?: import('./navigation').FleetNavigation;
  journey?: import('../backend/domain').Journey;
  nativeId?: number;
  shipCount?: number;
  battleId?: number;
  id: string;
  owner: string;
  name: string;
  type: ShipType;
  systemId: string;
  route: string[];
  progress: number;
  duration: number;
  hp: number;
  task: { type: 'scan' | 'colonize'; remaining: number; total: number; blocked?: boolean } | null;
}
export interface Player {
  productionFactor?: number;
  id: string;
  name: string;
  color: string;
  resources: Resources;
  home: string;
  discovered: string[];
  surveyed: string[];
  techs: TechId[];
  research: ResearchProgram;
  compute?: number;
  queue: { type: ShipType; systemId: string; remaining: number; total: number }[];
  online: boolean;
  ai?: { startedAt: number; nextDecision: number };
  empire: EmpireState;
}
export interface LogEntry {
  id: number;
  tick: number;
  text: string;
  tone: 'info' | 'success' | 'warning';
  playerId?: string;
}
export interface GameState {
  version: number;
  code: string;
  tick: number;
  speed: number;
  paused: boolean;
  hostId: string;
  systems: StarSystem[];
  links: [string, string][];
  fleets: Fleet[];
  players: Player[];
  log: LogEntry[];
  nextId: number;
  winner: string | null;
}
export type GameCommand =
  | StarbaseCommand
  | import('./stellarProjects').StellarCommand
  | import('./diplomacy').DiplomacyCommand
  | import('./events/types').SituationCommand
  | import('./crises').CrisisCommand
  | import('./celestial').SiteCommand
  | { type: 'move'; fleetId: string; systemId: string; append?: boolean }
  | { type: 'scan' | 'colonize'; fleetId: string; bodySlot?: number; systemId?: string; append?: boolean }
  | {
      type: 'local_move';
      fleetId: string;
      systemId: string;
      point: import('./navigation').Point3;
      append?: boolean;
    }
  | { type: 'fleet_stop'; fleetId: string }
  | { type: 'fleet_remove_order'; fleetId: string; index: number }
  | { type: 'build'; ship: ShipType; systemId: string }
  | { type: 'mine'; systemId: string }
  | import('./research').ResearchCommand
  | ColonyCommand
  | { type: 'empire_reform'; government: Government; revision: number }
  | { type: 'empire_ship_set'; shipSet: import('./shipSets').ShipSet; revision: number }
  | { type: 'species_modify'; sourceId: string; design: SpeciesDesign; colonyIds: string[]; revision: number }
  | { type: 'add_ai' }
  | { type: 'pause' }
  | { type: 'speed'; value: number };
export interface PublicPlayer {
  id: string;
  name: string;
  color: string;
  online: boolean;
  colonies: number;
  ai?: boolean;
  flag: FlagDesign;
  shipSet: import('./shipSets').ShipSet;
}
export interface GameView extends Omit<GameState, 'players'> {
  planetColonies?: import('./planetColonies').PlanetColony[];
  /** Client-only monotonic timeline. Never used for authoritative game decisions. */
  displayClock?: { now(at?: number): number; readonly paused: boolean; readonly speed: number };
  sites?: import('./celestial').BodySite[];
  stellarProjects?: import('./stellarProjects').StellarProject[];
  situations?: import('./events/types').Situation[];
  crises?: import('./crises').CrisisView[];
  relations?: import('./diplomacy').Relation[];
  offers?: import('./diplomacy').TreatyOffer[];
  capacity?: number;
  backend?: 'spacetimedb';
  players: PublicPlayer[];
  me: Player;
}

const catalog: [string, number, number, string, string][] = [
  ['Sol', 460, 570, '#fff1b8', 'G2 V'],
  ['Alpha Centauri', 630, 470, '#ffd8a1', 'G2 V'],
  ['Sirius', 410, 350, '#bddaff', 'A1 V'],
  ['Procyon', 690, 690, '#fceab8', 'F5 IV'],
  ['Tau Ceti', 250, 660, '#ffd19a', 'G8 V'],
  ['Epsilon Eridani', 200, 445, '#f6bb88', 'K2 V'],
  ['Altair', 860, 460, '#cfdeff', 'A7 V'],
  ['Vega', 815, 270, '#c3d8ff', 'A0 V'],
  ['Arcturus', 625, 220, '#ffb77f', 'K1 III'],
  ['Deneb', 1020, 280, '#d7e7ff', 'A2 Ia'],
  ['Kepler-186', 1020, 570, '#ffc092', 'M1 V'],
  ['TRAPPIST-1', 900, 780, '#ef977d', 'M8 V'],
  ['Rigel', 1200, 440, '#acd4ff', 'B8 Ia'],
  ['Antares', 1220, 680, '#f47e74', 'M1 Ib'],
  ['Fomalhaut', 680, 885, '#d6e4ff', 'A3 V'],
  ['Luyten', 440, 825, '#ed9d77', 'M3 V'],
  ['Barnards Stern', 185, 865, '#f39584', 'M4 V'],
  ['Ross 128', 160, 230, '#efa689', 'M4 V'],
  ['Capella', 375, 135, '#ffe0a0', 'G8 III'],
  ['Alnilam', 820, 100, '#a7c8ff', 'B0 Ia'],
  ['Polaris', 1120, 110, '#fae3ac', 'F7 Ib'],
  ['Bellatrix', 1380, 230, '#a6c7ff', 'B2 III'],
  ['Betelgeuse', 1420, 540, '#ffae88', 'M2 Iab'],
  ['Aldebaran', 1360, 835, '#f4b078', 'K5 III'],
  ['Spica', 1110, 930, '#a4caff', 'B1 V'],
  ['Achernar', 1490, 990, '#b0d9ff', 'B6 V'],
  ['Lacaille', 90, 1020, '#ffc5a1', 'M0 V'],
  ['Nashira', 500, 1010, '#ffd79d', 'G9 III'],
];
const edges: [number, number][] = [
  [0, 1],
  [0, 2],
  [0, 4],
  [0, 15],
  [1, 2],
  [1, 3],
  [1, 6],
  [2, 5],
  [2, 8],
  [2, 18],
  [3, 6],
  [3, 11],
  [3, 14],
  [4, 5],
  [4, 15],
  [4, 16],
  [5, 17],
  [6, 7],
  [6, 10],
  [7, 8],
  [7, 9],
  [7, 19],
  [8, 18],
  [9, 12],
  [9, 20],
  [9, 21],
  [10, 11],
  [10, 12],
  [10, 13],
  [11, 14],
  [11, 24],
  [12, 13],
  [12, 21],
  [12, 22],
  [13, 22],
  [13, 23],
  [14, 15],
  [14, 27],
  [15, 16],
  [15, 27],
  [16, 26],
  [17, 18],
  [18, 19],
  [19, 20],
  [20, 21],
  [21, 22],
  [22, 23],
  [23, 24],
  [23, 25],
  [24, 25],
  [26, 27],
];

export function createGame(code: string): GameState {
  const systems: StarSystem[] = catalog.map(([name, x, y, color, starClass], i) => ({
    id: `s${i}`,
    name,
    x,
    y,
    color,
    kind: 'star',
    class: starClass,
    planet: ['Kontinentalwelt', 'Ozeanwelt', 'Wüstenwelt', 'Alpine Welt', 'Savannenwelt'][i % 5],
    owner: null,
    resources: { energy: 3 + (i % 5), minerals: 2 + ((i * 3) % 5), data: 1 + (i % 3) },
    defense: [10, 13, 22, 24].includes(i) ? 85 : 0,
    mined: false,
    anomaly: [1, 7, 11, 18, 21].includes(i),
    studied: false,
  }));
  systems.push(
    {
      id: 'rift',
      name: 'Der goldene Riss',
      x: 1020,
      y: 410,
      color: '#ffbc68',
      kind: 'rift',
      class: 'Raumzeit-Anomalie',
      planet: 'Nicht kolonisierbar',
      owner: null,
      resources: { energy: 0, minerals: 0, data: 0 },
      defense: 0,
      mined: false,
      anomaly: true,
      studied: false,
    },
    {
      id: 'void',
      name: 'Erebus',
      x: 570,
      y: 750,
      color: '#b2a0ff',
      kind: 'blackhole',
      class: 'Schwarzes Loch',
      planet: 'Nicht kolonisierbar',
      owner: null,
      resources: { energy: 0, minerals: 0, data: 0 },
      defense: 0,
      mined: false,
      anomaly: true,
      studied: false,
    },
  );
  return {
    version: VERSION,
    code,
    tick: 0,
    speed: 1,
    paused: false,
    hostId: '',
    systems,
    links: [
      ...edges.map(([a, b]) => [`s${a}`, `s${b}`] as [string, string]),
      ['s6', 'rift'],
      ['s10', 'rift'],
      ['s0', 'void'],
      ['s3', 'void'],
    ],
    fleets: [],
    players: [],
    log: [],
    nextId: 1,
    winner: null,
  };
}
export function log(game: GameState, text: string, tone: LogEntry['tone'] = 'info', playerId?: string) {
  game.log.unshift({ id: game.nextId++, tick: game.tick, text, tone, playerId });
  game.log = game.log.slice(0, 80);
}
export function neighbors(game: Pick<GameState, 'links'>, id: string): string[] {
  return game.links.filter((l) => l.includes(id)).map((l) => (l[0] === id ? l[1] : l[0]));
}
export function reveal(game: GameState, player: Player, id: string) {
  player.discovered = [...new Set([...player.discovered, id, ...neighbors(game, id)])];
}
export function addPlayer(game: GameState, id: string, name: string, template?: TemplateSnapshot): Player {
  if (game.players.length >= 4) throw new Error('Dieser Sektor ist voll (maximal 4 Spieler).');
  const homes = ['s0', 's22', 's20', 's16'];
  const home = homes.find((h) => !game.systems.find((s) => s.id === h)!.owner);
  if (!home) throw new Error('Kein freies Startsystem. Bitte einen neuen Sektor erstellen.');
  if (!template) {
    const species = newSpecies(`species-${id}`);
    template = {
      species,
      empire: {
        ...newEmpire(`empire-${id}`, species.id),
        name: name.trim().slice(0, 24) || 'Kommandant',
        color: COLORS[game.players.length],
        flag: defaultFlag(COLORS[game.players.length]),
      },
    };
  }
  const empire = instantiateEmpire(template, id, game.tick);
  const player: Player = {
    id,
    name: empire.design.name,
    empire,
    home,
    color: empire.design.color,
    resources: { energy: 420, minerals: 360, data: 130, unity: 0 },
    discovered: [],
    surveyed: [home],
    techs: [],
    research: newResearch(),
    queue: [],
    online: true,
  };
  game.players.push(player);
  if (!game.hostId) game.hostId = id;
  const system = game.systems.find((s) => s.id === home)!;
  system.owner = id;
  system.starbase = createStarbase(id, true);
  system.defense = 100;
  system.planet = ENVIRONMENTS[empire.species[0].environment].name;
  system.colony = createColony(true, `${game.code}:${system.id}:1`, system.planet);
  system.colony.populations = [{ speciesId: empire.primarySpeciesId, population: system.colony.population }];
  {
    const origin = ORIGINS[empire.design.origin];
    for (const key of Object.keys(origin.resources) as Resource[])
      player.resources[key] = (player.resources[key] ?? 0) + resourceAmounts(origin.resources)[key];
    system.colony.population += origin.population;
    system.colony.populations[0].population = system.colony.population;
    system.name = empire.design.systemName;
    system.colonyName = empire.design.homeworldName;
    system.planet = ENVIRONMENTS[empire.species[0].environment].name;
  }
  reveal(game, player, home);
  // Navigation charts are public; surveys and economic intelligence remain private.
  player.discovered = game.systems.map((s) => s.id);
  for (const [type, fleetName] of [
    ['scout', 'ISS Horizon'],
    ['colony', 'ISS Genesis'],
    ['corvette', '1. Expeditionsflotte'],
  ] as const) {
    game.fleets.push({
      id: `f${game.nextId++}`,
      name: empire.design.shipPrefix ? fleetName.replace('ISS', empire.design.shipPrefix) : fleetName,
      owner: id,
      type,
      systemId: home,
      route: [],
      progress: 0,
      duration: 0,
      hp: 100,
      task: null,
    });
  }
  log(game, `${player.name} hat den Sektor betreten.`, 'success');
  log(game, 'Ein unbekanntes Signal erreicht uns aus Alpha Centauri.', 'info', id);
  return player;
}
export function income(game: Parameters<typeof empireLedger>[0], player: Player): Resources {
  return economyTotals(empireLedger(game, player));
}
export function pathfind(game: Pick<GameState, 'links'>, from: string, to: string): string[] | null {
  if (from === to) return [];
  const queue: string[][] = [[from]];
  const visited = new Set([from]);
  for (let i = 0; i < queue.length; i++) {
    const path = queue[i];
    for (const next of neighbors(game, path.at(-1)!)) {
      if (visited.has(next)) continue;
      if (next === to) return [...path.slice(1), next];
      visited.add(next);
      queue.push([...path, next]);
    }
  }
  return null;
}
function spend(player: Player, cost: Resources) {
  if ((Object.keys(cost) as Resource[]).some((r) => player.resources[r] < cost[r]))
    throw new Error('Nicht genügend Ressourcen.');
  for (const r of Object.keys(cost) as Resource[]) player.resources[r] -= cost[r];
}
function startLeg(game: GameState, fleet: Fleet, player: Player) {
  const a = game.systems.find((s) => s.id === fleet.systemId)!;
  const b = game.systems.find((s) => s.id === fleet.route[0])!;
  fleet.progress = 0;
  fleet.duration =
    Math.hypot(a.x - b.x, a.y - b.y) /
    ((player.techs.includes('propulsion') ? 29.7 : 22) *
      Math.max(0.1, 1 + empireModifiers(player.empire).speed));
}
export function command(game: GameState, playerId: string, cmd: GameCommand) {
  assertColonies(game);
  const player = game.players.find((p) => p.id === playerId);
  if (!player) throw new Error('Spieler nicht gefunden.');
  if (game.winner) throw new Error('Diese Partie ist beendet. Erstelle einen neuen Sektor.');
  if (!cmd || typeof cmd !== 'object') throw new Error('Ungültiger Befehl.');
  if (cmd.type === 'empire_ship_set') {
    player.empire = planShipSet(player.empire!, cmd.shipSet, game.tick, cmd.revision);
    return;
  }
  if (cmd.type === 'empire_reform') {
    const next = planReform(player.empire!, cmd.government, game.tick, cmd.revision);
    spend(player, REFORM_COST);
    player.empire = next;
    log(game, 'Die Regierungsreform ist in Kraft getreten.', 'success', player.id);
    return;
  }
  if (cmd.type === 'species_modify') {
    if (!player.techs.includes('extraction'))
      throw new Error('Erforsche zuerst Quantenextraktion, um Speziesmodifikation freizuschalten.');
    if (
      !Array.isArray(cmd.colonyIds) ||
      !cmd.colonyIds.length ||
      cmd.colonyIds.length > game.systems.length ||
      new Set(cmd.colonyIds).size !== cmd.colonyIds.length
    )
      throw new Error('Wähle eigene Kolonien ohne doppelte Einträge.');
    const selected = cmd.colonyIds.map((id) => game.systems.find((s) => s.id === id));
    if (
      selected.some(
        (s) =>
          !s ||
          s.owner !== playerId ||
          !s.colony?.populations?.some((g) => g.speciesId === cmd.sourceId && g.population > 0),
      )
    )
      throw new Error('Die Ausgangsspezies muss in jeder gewählten eigenen Kolonie leben.');
    const result = planSpeciesModification(player.empire!, cmd.sourceId, cmd.design, game.tick, cmd.revision);
    spend(player, MODIFICATION_COST);
    player.empire = result.empire;
    for (const system of selected)
      for (const group of system!.colony!.populations!)
        if (group.speciesId === cmd.sourceId) group.speciesId = result.speciesId;
    log(game, 'Die Speziesmodifikation wurde in den gewählten Kolonien abgeschlossen.', 'success', player.id);
    return;
  }
  if (cmd.type === 'add_ai') {
    if (game.hostId !== playerId) throw new Error('Nur der Host kann KI-Imperien hinzufügen.');
    addAI(game);
    return;
  }
  if ((COLONY_COMMANDS as readonly string[]).includes(cmd.type)) {
    const action = cmd as ColonyCommand;
    const system = game.systems.find((s) => s.id === action.systemId);
    if (!system) throw new Error('Dafür brauchst du eine eigene Kolonie.');
    applyColonyCommand(system, player, action);
    if (action.type === 'colony_build' || action.type === 'colony_upgrade')
      log(
        game,
        BUILDINGS[system.colony!.construction!.building].name + ' in ' + system.name + ' in Bau.',
        'info',
        playerId,
      );
    if (action.type === 'colony_cancel')
      log(game, 'Bau abgebrochen. 50 % der Kosten erstattet.', 'info', playerId);
    return;
  }
  if (cmd.type === 'pause' || cmd.type === 'speed') {
    if (playerId !== game.hostId) throw new Error('Nur der Host kann die Spielzeit ändern.');
    if (cmd.type === 'pause') game.paused = !game.paused;
    else {
      if (![1, 2, 3].includes(cmd.value)) throw new Error('Ungültige Geschwindigkeit.');
      game.speed = cmd.value;
    }
    return;
  }
  if (cmd.type === 'research' || cmd.type === 'research_weight' || cmd.type === 'compute_allocation') {
    applyResearch(player, cmd);
    return;
  }
  if (cmd.type.startsWith('starbase_')) {
    applyStarbaseCommand(game, player, cmd as StarbaseCommand);
    const s = game.systems.find((s) => s.id === (cmd as StarbaseCommand).systemId)!;
    s.defense = Math.min(s.defense, maxDefense(s));
    return;
  }
  if (cmd.type === 'build' || cmd.type === 'mine') {
    const system = game.systems.find((s) => s.id === cmd.systemId);
    if (!system || system.owner !== playerId) throw new Error('Dafür brauchst du eine eigene Kolonie.');
    if (cmd.type === 'mine') {
      if (system.mined) throw new Error('Bergbaustation bereits gebaut.');
      spend(player, { energy: 50, minerals: 100, data: 0 });
      system.mined = true;
      log(game, `Bergbaustation in ${system.name} einsatzbereit.`, 'success', playerId);
    } else {
      if (!hasShipyard(system)) throw new Error('Eine Sternenbasis mit Raumwerft wird benötigt.');
      if (!Object.hasOwn(SHIPS, cmd.ship)) throw new Error('Unbekannter Schiffstyp.');
      if (player.queue.length >= 5) throw new Error('Die Bauwarteschlange ist voll.');
      const spec = SHIPS[cmd.ship];
      spend(player, spec.cost);
      const time = spec.time / shipyardSpeed(system);
      player.queue.push({ type: cmd.ship, systemId: system.id, remaining: time, total: time });
      log(game, `${spec.name} in Auftrag gegeben.`, 'info', playerId);
    }
    return;
  }
  if (!['move', 'scan', 'colonize'].includes(cmd.type)) throw new Error('Unbekannter Befehl.');
  const fleet = game.fleets.find(
    (f) => f.id === (cmd as { fleetId: string }).fleetId && f.owner === playerId,
  );
  if (!fleet) throw new Error('Eigene Flotte nicht gefunden.');
  if (fleet.route.length || fleet.task) throw new Error('Diese Flotte führt bereits einen Auftrag aus.');
  const system = game.systems.find((s) => s.id === fleet.systemId)!;
  if (cmd.type === 'move') {
    if (cmd.systemId === fleet.systemId)
      throw new Error('Die Flotte befindet sich bereits in diesem System.');
    if (!player.discovered.includes(cmd.systemId)) throw new Error('Unbekanntes Zielsystem.');
    const route = fleetRoute(game, fleet, cmd.systemId);
    if (!route?.length) throw new Error('Wähle ein anderes erreichbares System.');
    fleet.route = route;
    startLeg(game, fleet, player);
    log(game, `${fleet.name} → ${game.systems.find((s) => s.id === cmd.systemId)!.name}.`, 'info', playerId);
  } else if (cmd.type === 'scan') {
    if (fleet.type !== 'scout') throw new Error('Ein Forschungsschiff wird benötigt.');
    if (player.surveyed.includes(system.id)) throw new Error('Dieses System ist bereits untersucht.');
    if (system.defense && system.owner !== playerId)
      throw new Error('Feindliche Verteidigung verhindert die Untersuchung.');
    fleet.task = { type: 'scan', remaining: 8, total: 8 };
  } else if (cmd.type === 'colonize') {
    if (fleet.type !== 'colony') throw new Error('Ein Kolonieschiff wird benötigt.');
    if (system.kind !== 'star' || system.owner !== playerId || system.colony)
      throw new Error('Dieses System kann nicht kolonisiert werden.');
    if (!player.surveyed.includes(system.id))
      throw new Error('Untersuche das System zuerst mit einem Forschungsschiff.');
    spend(player, { energy: 80, minerals: 80, data: 0 });
    fleet.task = { type: 'colonize', remaining: 12, total: 12 };
  }
}
export function tickGame(game: GameState, elapsed: number) {
  assertColonies(game);
  if (game.paused || game.winner) return;
  const dt = Math.max(0, Math.min(elapsed, 2)) * game.speed;
  const months = monthsDue(game.tick, game.tick + dt);
  game.tick += dt;
  if (months)
    for (const player of game.players) {
      const ledger = empireLedger(game, player);
      const rate = economyTotals(ledger.filter((l) => l.category !== 'synthesis'));
      for (const r of RESOURCE_IDS) player.resources[r] = (player.resources[r] ?? 0) + rate[r] * months;
      for (const tech of advanceResearch(player, empireCompute(game, player), months))
        log(game, `Forschung abgeschlossen: ${TECHS[tech].name}.`, 'success', player.id);
    }
  for (const system of game.systems) completeStarbase(system, game.tick);
  for (const system of game.systems) {
    if (!system.owner || !system.colony) continue;
    const colony = system.colony;
    const owner = game.players.find((p) => p.id === system.owner)!;
    if (months) growColony(colony, system.planet, owner, months * ECONOMY_MONTH_DAYS);
    if (colony.construction) {
      colony.construction.remaining -= dt * Math.max(0.1, 1 + empireModifiers(owner.empire).construction);
      if (colony.construction.remaining <= 0) {
        const id = colony.construction.building;
        const before = maxDefense(system);
        completeColonyConstruction(colony);
        system.defense = Math.min(
          maxDefense(system),
          system.defense + Math.max(0, maxDefense(system) - before),
        );
        log(game, `${BUILDINGS[id].name} in ${system.name} einsatzbereit.`, 'success', system.owner);
      }
    }
  }
  for (const player of game.players) {
    const construction = player.queue[0];
    if (construction) {
      const yard = game.systems.find((s) => s.id === construction.systemId)!;
      if (yard.owner !== player.id) {
        log(game, `Bauauftrag verloren: Werft in ${yard.name} eingenommen.`, 'warning', player.id);
        player.queue.shift();
      } else {
        construction.remaining -= dt * Math.max(0.1, 1 + empireModifiers(player.empire).construction);
        if (construction.remaining <= 0) {
          const id = game.nextId++;
          game.fleets.push({
            id: `f${id}`,
            owner: player.id,
            name: `${SHIPS[construction.type].name} ${id}`,
            type: construction.type,
            systemId: construction.systemId,
            route: [],
            progress: 0,
            duration: 0,
            hp: 100,
            task: null,
          });
          player.queue.shift();
          log(game, `${SHIPS[construction.type].name} einsatzbereit.`, 'success', player.id);
        }
      }
    }
  }
  const consumed = new Set<string>();
  for (const fleet of game.fleets) {
    const player = game.players.find((p) => p.id === fleet.owner)!;
    if (fleet.route.length) {
      fleet.progress += dt / fleet.duration;
      if (fleet.progress >= 1) {
        fleet.systemId = fleet.route.shift()!;
        fleet.progress = 0;
        reveal(game, player, fleet.systemId);
        const system = game.systems.find((s) => s.id === fleet.systemId)!;
        if (system.defense > 0 && system.owner !== player.id) fleet.route = [];
        if (fleet.route.length) startLeg(game, fleet, player);
        else log(game, `${fleet.name} erreicht ${system.name}.`, 'info', player.id);
      }
    } else if (fleet.task) {
      const contested = game.fleets.some(
        (other) =>
          other.owner !== fleet.owner &&
          other.systemId === fleet.systemId &&
          !other.route.length &&
          other.type === 'corvette',
      );
      fleet.task.blocked = contested;
      if (contested) continue;
      fleet.task.remaining -= dt;
      if (fleet.task.remaining <= 0) {
        const system = game.systems.find((s) => s.id === fleet.systemId)!;
        if (fleet.task.type === 'scan') {
          if (!player.surveyed.includes(system.id)) {
            player.surveyed.push(system.id);
            const bonus = system.anomaly && !system.studied ? 90 : 25;
            player.resources.data += bonus;
            if (system.anomaly) system.studied = true;
            log(game, `${system.name} untersucht. +${bonus} Daten.`, 'success', player.id);
          }
        } else if (system.owner === player.id && !system.colony) {
          system.colony = createColony(false, `${game.code}:${system.id}:1`, system.planet);
          system.colonyName = `${system.name} Prime`;
          system.colony.populations = [
            { speciesId: player.empire!.primarySpeciesId, population: system.colony.population },
          ];
          consumed.add(fleet.id);
          log(game, `${player.name} gründet eine Kolonie in ${system.name}.`, 'success');
        } else {
          player.resources.energy += 80;
          player.resources.minerals += 80;
          log(
            game,
            `Kolonisierung abgebrochen: ${system.name} ist nicht mehr frei. Kosten erstattet.`,
            'warning',
            player.id,
          );
        }
        fleet.task = null;
      }
    }
  }
  // Resolve damage simultaneously so message / fleet ordering cannot decide combat.
  const damage = new Map<string, number>();
  for (const system of game.systems) {
    const present = game.fleets.filter(
      (f) => f.systemId === system.id && !f.route.length && !consumed.has(f.id),
    );
    const attackers = present.filter((f) => f.type === 'corvette' && system.owner !== f.owner);
    if (system.defense > 0 && attackers.length) {
      let total = 0;
      for (const f of attackers) {
        const p = game.players.find((p) => p.id === f.owner)!;
        total +=
          (SHIPS[f.type].power *
            (p.techs.includes('weapons') ? 1.4 : 1) *
            Math.max(0.1, 1 + empireModifiers(p.empire).damage) *
            dt) /
          10;
        damage.set(f.id, (damage.get(f.id) || 0) + (4 * dt) / attackers.length);
      }
      system.defense = Math.max(0, system.defense - total);
      if (system.defense === 0) {
        log(game, `Die Verteidigung von ${system.name} ist gefallen.`, 'warning');
        if (system.owner) {
          system.owner = null;
          system.starbase = null;
          system.mined = false;
          system.colony = null;
        }
      }
    }
    for (const f of present.filter((f) => f.type === 'corvette')) {
      const enemies = present.filter((other) => other.owner !== f.owner);
      if (!enemies.length) continue;
      const p = game.players.find((p) => p.id === f.owner)!;
      const target = enemies.find((e) => e.type === 'corvette') || enemies[0];
      damage.set(
        target.id,
        (damage.get(target.id) || 0) +
          9 *
            dt *
            (p.techs.includes('weapons') ? 1.4 : 1) *
            Math.max(0.1, 1 + empireModifiers(p.empire).damage),
      );
    }
    if (system.owner && !present.some((f) => f.owner !== system.owner)) {
      system.defense = Math.min(maxDefense(system), system.defense + dt * 0.75);
      for (const f of present) f.hp = Math.min(100, f.hp + dt * colonyRepair(system));
    }
  }
  for (const f of game.fleets) {
    f.hp -= damage.get(f.id) || 0;
    if (f.hp <= 0) log(game, `${f.name} wurde im Kampf zerstört.`, 'warning', f.owner);
  }
  game.fleets = game.fleets.filter((f) => f.hp > 0 && !consumed.has(f.id));
  const winner = game.players.find((p) => game.systems.filter((s) => s.owner === p.id).length >= WIN_SYSTEMS);
  if (winner) {
    game.winner = winner.id;
    log(game, `${winner.name} kontrolliert ${WIN_SYSTEMS} Systeme und gewinnt den Sektor!`, 'success');
  }
  if (!game.winner) for (const player of game.players) if (player.ai) runAI(game, player);
}
export function fleetRoute(game: Pick<GameState, 'systems' | 'links'>, fleet: Fleet, target: string) {
  if (fleet.type === 'corvette') return pathfind(game, fleet.systemId, target);
  const accessible = new Set(
    game.systems
      .filter((s) => s.id === fleet.systemId || s.defense <= 0 || s.owner === fleet.owner)
      .map((s) => s.id),
  );
  return pathfind(
    { links: game.links.filter(([a, b]) => accessible.has(a) && accessible.has(b)) },
    fleet.systemId,
    target,
  );
}

export function addAI(game: GameState): Player {
  const names = ['Helix-Direktorat', 'Auralisches Kollektiv', 'Vesper-Konkordat'];
  const index = game.players.filter((p) => p.ai).length;
  const library = starterLibrary();
  const template = snapshotTemplate(library, library.empires[(index + 1) % library.empires.length].id);
  template.empire.name = names[index % names.length];
  template.empire.color = COLORS[game.players.length] || COLORS[0];
  const player = addPlayer(game, `ai-${game.nextId++}`, names[index % names.length], template);
  player.online = false;
  player.ai = { startedAt: game.tick, nextDecision: game.tick + 5 };
  for (const fleet of game.fleets.filter((f) => f.owner === player.id)) {
    fleet.name = `${['HX', 'AU', 'VS'][game.players.filter((p) => p.ai).length - 1] || 'AI'} ${SHIPS[fleet.type].name}`;
  }
  log(game, `${player.name}: autonomes Imperium im Sektor aktiv.`, 'warning');
  return player;
}

/** Deterministic opponent: same costs, commands, fog and production as human empires. */
function runAI(game: GameState, player: Player) {
  if (!player.ai || game.tick < player.ai.nextDecision) return;
  player.ai.nextDecision = game.tick + 4;
  const view = viewFor(game, player.id);
  const ownSystems = view.systems.filter((s) => s.owner === player.id);
  const ownFleets = view.fleets.filter((f) => f.owner === player.id);
  if (!ownSystems.length) return;
  const attempt = (cmd: GameCommand) => {
    try {
      command(game, player.id, cmd);
      return true;
    } catch {
      return false;
    }
  };
  const nearest = (fleet: Fleet, candidates: StarSystem[]) =>
    candidates
      .map((s) => ({ system: s, route: fleetRoute(game, fleet, s.id) }))
      .filter((item): item is { system: StarSystem; route: string[] } => item.route !== null)
      .sort(
        (a, b) =>
          a.route.length - b.route.length ||
          Math.hypot(
            a.system.x - game.systems.find((s) => s.id === fleet.systemId)!.x,
            a.system.y - game.systems.find((s) => s.id === fleet.systemId)!.y,
          ) -
            Math.hypot(
              b.system.x - game.systems.find((s) => s.id === fleet.systemId)!.x,
              b.system.y - game.systems.find((s) => s.id === fleet.systemId)!.y,
            ),
      )[0]?.system;

  const reserved = new Set(
    ownFleets
      .filter((f) => f.type === 'scout' && (f.route.length || f.task))
      .map((f) => f.route.at(-1) || f.systemId),
  );
  for (const fleet of ownFleets.filter((f) => !f.route.length && !f.task)) {
    const system = view.systems.find((s) => s.id === fleet.systemId)!;
    const hostile = view.fleets.filter(
      (f) => f.owner !== player.id && !f.route.length && f.systemId === fleet.systemId,
    );
    if (fleet.type === 'scout') {
      if (hostile.some((f) => f.type === 'corvette')) {
        const refuge = nearest(fleet, ownSystems);
        if (refuge && refuge.id !== fleet.systemId)
          attempt({ type: 'move', fleetId: fleet.id, systemId: refuge.id });
        continue;
      }
      if (!player.surveyed.includes(system.id) && (system.defense === 0 || system.owner === player.id)) {
        attempt({ type: 'scan', fleetId: fleet.id });
        reserved.add(system.id);
        continue;
      }
      const target = nearest(
        fleet,
        view.systems.filter(
          (s) =>
            !s.owner &&
            s.defense === 0 &&
            !player.surveyed.includes(s.id) &&
            !reserved.has(s.id) &&
            s.kind === 'star',
        ),
      );
      if (target && attempt({ type: 'move', fleetId: fleet.id, systemId: target.id }))
        reserved.add(target.id);
    } else if (fleet.type === 'colony') {
      if (
        system.owner === player.id &&
        !system.colony &&
        system.kind === 'star' &&
        player.surveyed.includes(system.id) &&
        !hostile.some((f) => f.type === 'corvette')
      ) {
        attempt({ type: 'colonize', fleetId: fleet.id });
        continue;
      }
      const colonizing = new Set(
        ownFleets
          .filter((f) => f.type === 'colony' && f.id !== fleet.id)
          .map((f) => f.route.at(-1) || (f.task ? f.systemId : '')),
      );
      const target = nearest(
        fleet,
        view.systems.filter(
          (s) =>
            s.kind === 'star' &&
            s.owner === player.id &&
            !s.colony &&
            player.surveyed.includes(s.id) &&
            !colonizing.has(s.id),
        ),
      );
      if (target && target.id !== fleet.systemId)
        attempt({ type: 'move', fleetId: fleet.id, systemId: target.id });
    } else {
      if (fleet.hp < 35) {
        const refuge = nearest(fleet, ownSystems);
        if (refuge && refuge.id !== fleet.systemId)
          attempt({ type: 'move', fleetId: fleet.id, systemId: refuge.id });
        continue;
      }
      if (system.owner === player.id && fleet.hp < 90) continue;
      if (hostile.length || (system.defense > 0 && system.owner !== player.id)) continue;
      const threatened = ownSystems.filter((s) =>
        view.fleets.some((f) => f.owner !== player.id && f.systemId === s.id),
      );
      const defenseTarget = nearest(fleet, threatened);
      if (defenseTarget && defenseTarget.id !== fleet.systemId) {
        attempt({ type: 'move', fleetId: fleet.id, systemId: defenseTarget.id });
        continue;
      }
      const military = ownFleets.filter((f) => f.type === 'corvette');
      if (military.length < 2) continue;
      const invasion = game.tick - player.ai.startedAt > 150;
      const candidates = view.systems.filter(
        (s) => (!s.owner && s.defense > 0) || (invasion && s.owner && s.owner !== player.id),
      );
      // A shared rally objective keeps the small task force together.
      const anchor = { ...fleet, systemId: player.home };
      const target = nearest(anchor, candidates);
      if (target && target.id !== fleet.systemId)
        attempt({ type: 'move', fleetId: fleet.id, systemId: target.id });
    }
  }
  for (const s of view.systems.filter(
    (s) => !s.owner && !s.starbase && !s.defense && player.surveyed.includes(s.id),
  )) {
    if (attempt({ type: 'starbase_build', systemId: s.id })) break;
  }
  const yard = ownSystems.find((s) => hasShipyard(s));
  const count = (type: ShipType) =>
    ownFleets.filter((f) => f.type === type).length + player.queue.filter((q) => q.type === type).length;
  if (player.queue.length < 2) {
    const target: ShipType | null =
      count('scout') === 0
        ? 'scout'
        : count('colony') === 0
          ? 'colony'
          : count('corvette') < 3
            ? 'corvette'
            : null;
    if (target && yard) attempt({ type: 'build', ship: target, systemId: yard.id });
  }
  if (!player.research.projects.length) {
    const next = (['extraction', 'propulsion', 'weapons'] as TechId[]).find((t) => !player.techs.includes(t));
    if (next) attempt({ type: 'research', tech: next });
  }
  if (player.resources.energy > 220 && player.resources.minerals > 240) {
    const unmined = ownSystems.find((s) => !s.mined);
    if (unmined) attempt({ type: 'mine', systemId: unmined.id });
    else {
      for (const system of ownSystems) {
        const development = planColonyDevelopment(system);
        if (development) {
          attempt(development);
          break;
        }
      }
    }
  }
}
export function viewFor(game: GameState, playerId: string): GameView {
  assertColonies(game);
  const me = game.players.find((p) => p.id === playerId)!;
  const visible = new Set([
    ...game.systems.filter((s) => s.owner === playerId).map((s) => s.id),
    ...game.fleets.filter((f) => f.owner === playerId).map((f) => f.systemId),
  ]);
  return {
    ...game,
    systems: game.systems.map((s) => ({
      ...s,
      colony: s.owner === playerId ? s.colony : null,
      starbase: s.starbase?.owner === playerId ? s.starbase : null,
      starbaseLevel: s.starbase?.level ?? 0,
      resources:
        me.surveyed.includes(s.id) || visible.has(s.id) ? s.resources : { energy: 0, minerals: 0, data: 0 },
    })),
    fleets: game.fleets.filter((f) => f.owner === playerId || visible.has(f.systemId)),
    log: game.log.filter((l) => !l.playerId || l.playerId === playerId),
    players: game.players.map((p) => ({
      id: p.id,
      name: p.name,
      color: p.color,
      online: p.online,
      colonies: game.systems.filter((s) => s.owner === p.id && s.colony).length,
      ai: !!p.ai,
      flag: structuredClone(p.empire.design.flag),
      shipSet: p.empire.design.shipSet,
    })),
    me,
  };
}
