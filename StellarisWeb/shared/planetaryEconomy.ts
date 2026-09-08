import { optimizeProduction, type ComputePlayer } from './compute';
import { starbaseDefense, starbaseRepair } from './starbases';
import type { GameState, Player, Resource, Resources, StarSystem } from './game';
import { colonyModifiers, populationGrowth, type PopulationGroup } from './empireState';
import { environmentForPlanet, governmentModifiers } from './empires';
import { RESOURCE_CATALOG, RESOURCE_IDS, resourceAmounts } from './resources';
import { economyLine, economyTotals, modifyEconomy, type EconomyModifier, type EconomyLine } from './economy';

export type BuildingId =
  'habitat' | 'biosphere' | 'reactor' | 'foundry' | 'laboratory' | 'bastion' | 'datacenter';
export type ColonyFocus = 'balanced' | 'energy' | 'minerals' | 'data';
export interface ColonyDistrict {
  id: number;
  slot: number;
  building: BuildingId;
  level: number;
  enabled: boolean;
}
export interface ColonySector {
  id: number;
  name: string;
  x: number;
  y: number;
  z: number;
  feature: 'fertile' | 'ore' | 'crystals' | 'geothermal' | 'sheltered';
  slots: number;
  districts: ColonyDistrict[];
}
export interface Colony {
  economyModifiers?: EconomyModifier[];
  schema: 3;
  seed: number;
  bodySlot: number;
  revision: number;
  nextDistrictId: number;
  population: number;
  populations?: PopulationGroup[];
  focus: ColonyFocus;
  sectors: ColonySector[];
  construction: {
    sectorId: number;
    slot: number;
    districtId: number | null;
    building: BuildingId;
    level: number;
    remaining: number;
    total: number;
    cost: Resources;
  } | null;
}
type ColonyTarget = { systemId: string; bodySlot?: number; revision: number };
export type ColonyCommand = ColonyTarget &
  (
    | { type: 'colony_build'; sectorId: number; slot: number; building: BuildingId }
    | { type: 'colony_upgrade'; districtId: number }
    | { type: 'colony_toggle'; districtId: number; enabled: boolean }
    | { type: 'colony_demolish'; districtId: number }
    | { type: 'colony_focus'; focus: ColonyFocus }
    | { type: 'colony_cancel' }
  );
export const COLONY_COMMANDS = [
  'colony_build',
  'colony_upgrade',
  'colony_toggle',
  'colony_demolish',
  'colony_focus',
  'colony_cancel',
] as const;
export const BUILDINGS: Record<
  BuildingId,
  {
    name: string;
    description: string;
    jobs: number;
    resource: Resource | null;
    perJob: number;
    housing: number;
    supply: number;
    upkeep: number;
    cost: Resources;
    time: number;
    maxLevel: number;
  }
> = {
  datacenter: {
    name: 'Rechenzentrum',
    description: 'Besetzte Jobs liefern je 2 Compute pro Monat für Forschung und Simulationen.',
    jobs: 2,
    resource: null,
    perJob: 0,
    housing: 0,
    supply: 0,
    upkeep: 2,
    cost: { energy: 100, minerals: 140, data: 0 },
    time: 24,
    maxLevel: 3,
  },
  habitat: {
    name: 'Habitat',
    description: 'Wohnraum für neue Pops.',
    jobs: 0,
    resource: null,
    perJob: 0,
    housing: 8,
    supply: 0,
    upkeep: 0.5,
    cost: { energy: 50, minerals: 90, data: 0 },
    time: 18,
    maxLevel: 3,
  },
  biosphere: {
    name: 'Biosphäre',
    description: 'Versorgt bis zu acht Pops mit besetzten Jobs.',
    jobs: 2,
    resource: null,
    perJob: 0,
    housing: 0,
    supply: 4,
    upkeep: 0.5,
    cost: { energy: 40, minerals: 75, data: 0 },
    time: 16,
    maxLevel: 3,
  },
  reactor: {
    name: 'Kraftwerk',
    description: 'Techniker erzeugen Energie.',
    jobs: 2,
    resource: 'energy',
    perJob: 4,
    housing: 0,
    supply: 0,
    upkeep: 0.5,
    cost: { energy: 50, minerals: 100, data: 0 },
    time: 16,
    maxLevel: 3,
  },
  foundry: {
    name: 'Förderdistrikt',
    description: 'Bergleute gewinnen Mineralien.',
    jobs: 2,
    resource: 'minerals',
    perJob: 3,
    housing: 0,
    supply: 0,
    upkeep: 0.5,
    cost: { energy: 80, minerals: 80, data: 0 },
    time: 18,
    maxLevel: 3,
  },
  laboratory: {
    name: 'Forschungscampus',
    description: 'Forscher erheben und archivieren Daten.',
    jobs: 2,
    resource: 'data',
    perJob: 3,
    housing: 0,
    supply: 0,
    upkeep: 1,
    cost: { energy: 90, minerals: 120, data: 0 },
    time: 22,
    maxLevel: 3,
  },
  bastion: {
    name: 'Schildbastion',
    description: 'Besetzte Wachposten stärken Verteidigung und Schiffsreparatur.',
    jobs: 1,
    resource: null,
    perJob: 0,
    housing: 0,
    supply: 0,
    upkeep: 1,
    cost: { energy: 60, minerals: 120, data: 0 },
    time: 20,
    maxLevel: 3,
  },
};
export const FOCUSES: Record<ColonyFocus, { name: string; description: string }> = {
  balanced: { name: 'Ausgewogen', description: 'Verteilt Arbeitskräfte gleichmäßig auf produktive Jobs.' },
  energy: { name: 'Energie', description: 'Besetzt Energiejobs zuerst. Versorgung hat Vorrang.' },
  minerals: { name: 'Mineralien', description: 'Besetzt Förderjobs zuerst. Versorgung hat Vorrang.' },
  data: { name: 'Daten', description: 'Besetzt Forscherjobs zuerst. Versorgung hat Vorrang.' },
};
export const FEATURES = {
  fertile: { name: 'Fruchtbare Senke', description: '+20 % Versorgung', building: 'biosphere' },
  ore: { name: 'Erzvorkommen', description: '+20 % Mineralien', building: 'foundry' },
  crystals: { name: 'Kristallfeld', description: '+20 % Daten', building: 'laboratory' },
  geothermal: { name: 'Geothermie', description: '+20 % Energie', building: 'reactor' },
  sheltered: { name: 'Geschützte Lage', description: '+2 Wohnraum je Habitatstufe', building: 'habitat' },
} as const;
function hash(value: string) {
  let h = 2166136261;
  for (let i = 0; i < value.length; i++) h = Math.imul(h ^ value.charCodeAt(i), 16777619);
  return h >>> 0;
}
function random(seed: number) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
/** A stable administrative projection: every sector is visible on the front hemisphere. */
export function generateColonySectors(seed: number, planet: string): ColonySector[] {
  const rand = random(seed),
    count =
      planet === 'Ozeanwelt' ? 10 + (seed % 3) : planet === 'Wüstenwelt' ? 7 + (seed % 3) : 8 + (seed % 4);
  const candidates = Array.from({ length: 240 }, () => {
    const a = rand() * Math.PI * 2,
      r = Math.sqrt(rand()) * 0.8;
    return { x: Math.cos(a) * r, y: Math.sin(a) * r };
  });
  const points = [{ x: -0.2 + rand() * 0.1, y: 0.15 + rand() * 0.08 }];
  while (points.length < count) {
    let best = candidates[0],
      distance = -1;
    for (const p of candidates) {
      let d = Infinity;
      for (const q of points) d = Math.min(d, (p.x - q.x) ** 2 + (p.y - q.y) ** 2);
      if (d > distance) {
        best = p;
        distance = d;
      }
    }
    points.push(best);
  }
  const names = [
    'Hauptstadt',
    'Nordbogen',
    'Morgenpol',
    'Südbogen',
    'Dämmerzone',
    'Westbogen',
    'Äquator',
    'Ostbogen',
    'Hochzone',
    'Polarkreis',
    'Tiefenzone',
    'Fernbogen',
  ];
  const features = (
    planet === 'Wüstenwelt'
      ? ['geothermal', 'ore', 'crystals', 'sheltered']
      : planet === 'Ozeanwelt'
        ? ['fertile', 'geothermal', 'crystals', 'sheltered']
        : Object.keys(FEATURES)
  ) as ColonySector['feature'][];
  return points.map((p, id) => ({
    ...p,
    z: Math.sqrt(1 - p.x * p.x - p.y * p.y),
    id,
    name: names[id],
    feature: features[Math.floor(rand() * features.length)],
    slots: id === 0 ? 3 : 2 + Math.floor(rand() * 2),
    districts: [],
  }));
}
export function createColony(capital = false, identity = 'colony', planet = 'Kontinentalwelt'): Colony {
  const seed = hash(identity),
    sectors = generateColonySectors(seed, planet);
  const colony: Colony = {
    schema: 3,
    seed,
    bodySlot: 1,
    revision: 0,
    nextDistrictId: 1,
    population: capital ? 6 : 2,
    focus: 'balanced',
    sectors,
    construction: null,
  };
  const place = (sector: number, building: BuildingId) =>
    sectors[sector].districts.push({
      id: colony.nextDistrictId++,
      slot: sectors[sector].districts.length,
      building,
      level: 1,
      enabled: true,
    });
  place(0, 'habitat');
  place(0, 'biosphere');
  place(1, 'reactor');
  place(1, 'foundry');
  if (capital) {
    place(2, 'laboratory');
    sectors[0].districts.forEach((d) => (d.level = 2));
  }
  return colony;
}
/** Old galaxies are intentionally unsupported; new games generate the current schema. */
export function assertColonies(game: GameState) {
  for (const system of game.systems)
    if (system.colony && system.colony.schema !== 3)
      throw new Error('Diese Galaxie verwendet ein älteres Koloniesystem. Bitte eine neue Partie starten.');
}
export const districtCapacity = (c: Colony) => c.sectors.reduce((n, s) => n + s.slots, 0);
export const occupiedDistricts = (c: Colony) => c.sectors.reduce((n, s) => n + s.districts.length, 0);
export function colonyBuildingLevel(c: Colony | null | undefined, building: BuildingId) {
  return (
    c?.sectors.reduce(
      (n, s) => n + s.districts.reduce((m, d) => m + (d.enabled && d.building === building ? d.level : 0), 0),
      0,
    ) ?? 0
  );
}
export function districtSpec(building: BuildingId, level = 1): { cost: Resources; time: number } {
  const s = BUILDINGS[building],
    factor = 1 + (level - 1) * 0.65;
  return {
    cost: resourceAmounts(
      Object.fromEntries(RESOURCE_IDS.map((id) => [id, Math.ceil((s.cost[id] ?? 0) * factor)])),
    ),
    time: s.time + (level - 1) * 8,
  };
}
export function featureMultiplier(s: ColonySector, b: BuildingId) {
  return FEATURES[s.feature].building === b && b !== 'habitat' ? 1.2 : 1;
}
export interface DistrictEconomy {
  compute: number;
  defense: number;
  workers: { speciesId: string; name: string; employed: number }[];
  id: number;
  sectorId: number;
  building: BuildingId;
  jobs: number;
  employed: number;
  output: Resources;
  supply: number;
  housing: number;
  upkeep: number;
}
export interface ColonyEconomy {
  ledger: EconomyLine[];
  compute: number;
  districts: DistrictEconomy[];
  jobs: number;
  employed: number;
  unemployed: number;
  housing: number;
  supply: number;
  supplyCapacity: number;
  demand: number;
  upkeep: number;
  output: Resources;
  defense: number;
  repair: number;
  growthFactor: number;
}
export function colonyEconomy(
  c: Colony,
  planet = 'Kontinentalwelt',
  player?: Pick<Player, 'empire'> & ComputePlayer,
): ColonyEconomy {
  const population = Math.max(0, c.population);
  const common = [...(player?.empire?.economyModifiers ?? []), ...(c.economyModifiers ?? [])];
  const upkeep = colonyModifiers(player?.empire, c.populations, environmentForPlanet(planet)).upkeep;
  if (upkeep)
    common.push({
      id: 'population-upkeep',
      name: 'Bevölkerungsmerkmale',
      category: 'upkeep',
      resource: 'energy',
      percent: upkeep,
    });
  const groups = c.populations?.length
    ? c.populations
    : [{ speciesId: player?.empire?.primarySpeciesId ?? '', population }];
  const total = groups.reduce((n, g) => n + Math.max(0, g.population), 0);
  const workers = groups
    .map((g) => {
      const species = player?.empire?.species.find((s) => s.id === g.speciesId);
      const mods = colonyModifiers(player?.empire, [{ ...g, population: 1 }], environmentForPlanet(planet));
      const modifiers: EconomyModifier[] = [...common, ...(species?.economyModifiers ?? [])];
      for (const resource of RESOURCE_IDS) {
        const percent = (mods as Partial<Record<Resource, number>>)[resource] ?? 0;
        if (percent)
          modifiers.push({
            id: `species:${g.speciesId}:${resource}`,
            name: `${species?.name ?? 'Bevölkerung'} · Merkmale, Regierung & Klima`,
            category: 'jobs',
            resource,
            percent,
          });
      }
      if (mods.research)
        modifiers.push({
          id: `compute:${g.speciesId}`,
          name: 'Forschungsmodifikatoren',
          category: 'compute',
          percent: mods.research,
        });
      return {
        speciesId: g.speciesId,
        name: species?.name ?? 'Bevölkerung',
        available: total ? (Math.max(0, g.population) * population) / total : 0,
        modifiers,
      };
    })
    .sort((a, b) => a.speciesId.localeCompare(b.speciesId));
  const rows = c.sectors.flatMap((sector) =>
    sector.districts.map((d) => ({
      id: d.id,
      sectorId: sector.id,
      building: d.building,
      jobs: d.enabled ? BUILDINGS[d.building].jobs * d.level : 0,
      compute: 0,
      defense: 0,
      employed: 0,
      workers: [] as DistrictEconomy['workers'],
      output: resourceAmounts(),
      supply: 0,
      housing: d.enabled
        ? modifyEconomy(
            (BUILDINGS[d.building].housing +
              (sector.feature === 'sheltered' && d.building === 'habitat' ? 2 : 0)) *
              d.level,
            common,
            { category: 'housing', job: d.building },
          ).amount
        : 0,
      upkeep: d.enabled
        ? modifyEconomy(BUILDINGS[d.building].upkeep * d.level, common, {
            category: 'upkeep',
            resource: 'energy',
            job: d.building,
          }).amount
        : 0,
      baseUpkeep: d.enabled ? BUILDINGS[d.building].upkeep * d.level : 0,
      boost: featureMultiplier(sector, d.building),
    })),
  );
  let available = population;
  // First reserve job quotas according to the colony focus. Then match species cohorts to
  // these quotas. Complexity depends on districts × species, never the number of pops.
  const allocate = (group: typeof rows, budget: number) => {
    const jobs = group.reduce((n, r) => n + r.jobs - r.employed, 0),
      work = Math.min(available, budget, jobs);
    if (jobs <= 0 || work <= 0) return;
    for (const r of group) r.employed += ((r.jobs - r.employed) * work) / jobs;
    available = Math.max(0, available - work);
  };
  const farms = rows.filter((r) => r.building === 'biosphere');
  const farmCapacity = farms.reduce(
    (n, r) =>
      n +
      r.jobs *
        BUILDINGS.biosphere.supply *
        r.boost *
        modifyEconomy(1, common, { category: 'supply', job: 'biosphere' }).amount,
    0,
  );
  const farmJobs = farms.reduce((n, r) => n + r.jobs, 0);
  allocate(farms, farmCapacity ? Math.min(1, population / farmCapacity) * farmJobs : 0);
  allocate(
    rows.filter((r) => r.building === 'bastion'),
    Infinity,
  );
  const productive = rows.filter(
    (r) => BUILDINGS[r.building].resource !== null || r.building === 'datacenter',
  );
  if (c.focus !== 'balanced')
    allocate(
      productive.filter((r) => BUILDINGS[r.building].resource === c.focus),
      Infinity,
    );
  allocate(productive, Infinity);
  allocate(farms, Infinity);
  const category = (building: BuildingId) =>
    building === 'datacenter'
      ? ('compute' as const)
      : building === 'biosphere'
        ? ('supply' as const)
        : building === 'bastion'
          ? ('defense' as const)
          : ('jobs' as const);
  const candidates = rows
    .flatMap((row) =>
      workers.map((worker) => ({
        row,
        worker,
        score: modifyEconomy(1, worker.modifiers, {
          category: category(row.building),
          job: row.building,
          resource: BUILDINGS[row.building].resource ?? undefined,
          speciesId: worker.speciesId,
        }).amount,
      })),
    )
    .sort(
      (a, b) =>
        b.score - a.score || a.row.id - b.row.id || a.worker.speciesId.localeCompare(b.worker.speciesId),
    );
  const assigned = new Map<number, number>();
  for (const { row, worker } of candidates) {
    const count = Math.min(worker.available, Math.max(0, row.employed - (assigned.get(row.id) ?? 0)));
    if (count <= 0) continue;
    row.workers.push({ speciesId: worker.speciesId, name: worker.name, employed: count });
    worker.available -= count;
    assigned.set(row.id, (assigned.get(row.id) ?? 0) + count);
  }
  const workerIndex = new Map(workers.map((w) => [w.speciesId, w]));
  const jobAmount = (row: (typeof rows)[number], base: number, cat: import('./economy').EconomyCategory) =>
    row.workers.reduce(
      (n, w) =>
        n +
        w.employed *
          modifyEconomy(base, workerIndex.get(w.speciesId)!.modifiers, {
            category: cat,
            job: row.building,
            speciesId: w.speciesId,
          }).amount,
      0,
    );
  for (const row of farms) row.supply = jobAmount(row, BUILDINGS.biosphere.supply * row.boost, 'supply');
  const supply = farms.reduce((n, r) => n + r.supply, 0),
    supplyFactor = population > 0 ? Math.min(1, supply / population) : 1;
  const ledger: EconomyLine[] = [];
  const governmentUnity = player?.empire
    ? governmentModifiers(player.empire.design.government, player.empire.design.origin).unity : 0;
  ledger.push(economyLine('population-unity', 'Bevölkerung & Regierung', population * 0.5,
    [...common, { id: 'government-unity', name: 'Regierung: Einigkeit', percent: governmentUnity }],
    { category: 'population', resource: 'unity' }));
  let defense = 0,
    compute = 0,
    repair = 0;
  for (const row of rows) {
    const spec = BUILDINGS[row.building];
    if (spec.resource)
      for (const worker of row.workers) {
        const modifiers = [
          ...workerIndex.get(worker.speciesId)!.modifiers,
          { id: 'terrain', name: 'Planetare Vorkommen', factor: row.boost },
          { id: 'supply', name: 'Versorgung', factor: Math.max(0.25, supplyFactor) },
        ];
        // Flat output bonuses apply per occupied job, including fractional cohorts.
        const line = economyLine(
          `${row.id}:${worker.speciesId}:${spec.resource}`,
          spec.name,
          spec.perJob,
          modifiers,
          { category: 'jobs', resource: spec.resource, job: row.building, speciesId: worker.speciesId },
        );
        line.base *= worker.employed;
        line.amount *= worker.employed;
        line.modifiers = line.modifiers.map((m) => ({ ...m, delta: m.delta * worker.employed }));
        line.species = worker.name;
        line.employed = worker.employed;
        optimizeProduction([line], player ?? {});
        ledger.push(line);
        row.output[spec.resource] += line.amount;
      }
    if (row.baseUpkeep)
      ledger.push(
        economyLine(
          `upkeep:${row.id}`,
          spec.name,
          row.baseUpkeep,
          common,
          { category: 'upkeep', resource: 'energy', job: row.building },
          true,
        ),
      );
    if (row.building === 'bastion') {
      row.defense = jobAmount(row, 40, 'defense');
      defense += row.defense;
      repair += jobAmount(row, 1, 'repair');
    }
    if (row.building === 'datacenter') {
      row.compute = jobAmount(row, 2, 'compute') * Math.max(0.25, supplyFactor);
      compute += row.compute;
    }
  }
  return {
    ledger,
    compute,
    districts: rows,
    jobs: rows.reduce((n, r) => n + r.jobs, 0),
    employed: population - available,
    unemployed: available,
    housing: rows.reduce((n, r) => n + r.housing, 0),
    supply,
    supplyCapacity: farmCapacity,
    demand: population,
    upkeep: rows.reduce((n, r) => n + r.upkeep, 0),
    output: economyTotals(ledger),
    defense,
    repair,
    growthFactor:
      supplyFactor >= 1 - 1e-8 &&
      rows.reduce((n, r) => n + r.housing, 0) > population &&
      farmCapacity > population
        ? modifyEconomy(1, common, { category: 'growth' }).amount
        : 0,
  };
}
export function colonyGrowthPerMinute(c: Colony, planet: string, player: Pick<Player, 'empire'>) {
  const e = colonyEconomy(c, planet, player);
  return (
    0.25 *
    e.growthFactor *
    (c.populations?.reduce(
      (n, g) =>
        n +
        (g.population / Math.max(0.001, c.population)) *
          populationGrowth(player.empire, g.speciesId, environmentForPlanet(planet)),
      0,
    ) ?? 1)
  );
}
export function growColony(c: Colony, planet: string, player: Pick<Player, 'empire'>, elapsed: number) {
  if (elapsed <= 0) return;
  const e = colonyEconomy(c, planet, player),
    total = c.population;
  if (!e.growthFactor || total <= 0) return;
  const groups = c.populations ?? [];
  if (!groups.length) {
    c.population = Math.min(e.housing, e.supplyCapacity, total + (elapsed / 240) * e.growthFactor);
    return;
  }
  const increments = groups.map(
      (g) =>
        (((elapsed / 240) * e.growthFactor * g.population) / total) *
        populationGrowth(player.empire, g.speciesId, environmentForPlanet(planet)),
    ),
    increase = increments.reduce((n, v) => n + v, 0),
    scale =
      increase > 0 ? Math.min(1, Math.max(0, Math.min(e.housing, e.supplyCapacity) - total) / increase) : 0;
  groups.forEach((g, i) => (g.population += increments[i] * scale));
  c.population = groups.reduce((n, g) => n + g.population, 0);
}
export function completeColonyConstruction(c: Colony) {
  const p = c.construction;
  if (!p) return;
  const sector = c.sectors.find((s) => s.id === p.sectorId)!;
  if (p.districtId !== null) {
    const d = sector.districts.find((d) => d.id === p.districtId)!;
    d.level = p.level;
  } else
    sector.districts.push({
      id: c.nextDistrictId++,
      slot: p.slot,
      building: p.building,
      level: 1,
      enabled: true,
    });
  c.construction = null;
  c.revision++;
}
export function applyColonyCommand(system: StarSystem, player: Player, cmd: ColonyCommand) {
  if (system.owner !== player.id || !system.colony) throw new Error('Dafür brauchst du eine eigene Kolonie.');
  const c = system.colony;
  if (!Number.isSafeInteger(cmd.revision) || cmd.revision !== c.revision)
    throw new Error('Die Kolonie wurde zwischenzeitlich verändert. Bitte erneut versuchen.');
  if (cmd.type === 'colony_focus') {
    if (!Object.hasOwn(FOCUSES, cmd.focus)) throw new Error('Unbekannter Produktionsschwerpunkt.');
    c.focus = cmd.focus;
  } else if (cmd.type === 'colony_cancel') {
    if (!c.construction) throw new Error('Kein planetarer Bauauftrag aktiv.');
    for (const r of RESOURCE_IDS)
      player.resources[r] = (player.resources[r] ?? 0) + (c.construction.cost[r] ?? 0) * 0.5;
    c.construction = null;
  } else {
    const districtId = cmd.type === 'colony_build' ? null : cmd.districtId;
    const sector =
      cmd.type === 'colony_build'
        ? c.sectors.find((s) => s.id === cmd.sectorId)
        : c.sectors.find((s) => s.districts.some((d) => d.id === districtId));
    if (!sector) throw new Error('Unbekannter Sektor oder Distrikt.');
    const d = sector.districts.find((d) => d.id === districtId);
    if (cmd.type === 'colony_toggle' || cmd.type === 'colony_demolish') {
      if (c.construction?.districtId === districtId) throw new Error('Diesen Ausbau zuerst abbrechen.');
      if (cmd.type === 'colony_toggle') {
        if (typeof cmd.enabled !== 'boolean') throw new Error('Ungültiger Betriebszustand.');
        d!.enabled = cmd.enabled;
      } else sector.districts = sector.districts.filter((d) => d.id !== districtId);
    } else {
      if (c.construction) throw new Error('In dieser Kolonie läuft bereits ein Ausbau.');
      const building = cmd.type === 'colony_build' ? cmd.building : d!.building;
      if (!Object.hasOwn(BUILDINGS, building)) throw new Error('Unbekannter Kolonieausbau.');
      if (cmd.type === 'colony_build' && sector.districts.length >= sector.slots)
        throw new Error('Alle Bauplätze dieses Sektors sind belegt.');
      if (
        cmd.type === 'colony_build' &&
        (!Number.isSafeInteger(cmd.slot) ||
          cmd.slot < 0 ||
          cmd.slot >= sector.slots ||
          sector.districts.some((d) => d.slot === cmd.slot))
      )
        throw new Error('Ungültiger oder belegter Bauplatz.');
      const level = d ? d.level + 1 : 1;
      if (level > BUILDINGS[building].maxLevel) throw new Error('Maximale Ausbaustufe erreicht.');
      const spec = districtSpec(building, level);
      for (const r of RESOURCE_IDS)
        if ((player.resources[r] ?? 0) < (spec.cost[r] ?? 0)) throw new Error('Nicht genügend Rohstoffe.');
      for (const r of RESOURCE_IDS) player.resources[r] = (player.resources[r] ?? 0) - (spec.cost[r] ?? 0);
      c.construction = {
        sectorId: sector.id,
        slot: cmd.type === 'colony_build' ? cmd.slot : d!.slot,
        districtId: d?.id ?? null,
        building,
        level,
        total: spec.time,
        remaining: spec.time,
        cost: spec.cost,
      };
    }
  }
  c.revision++;
  system.defense = Math.min(system.defense, maxDefense(system));
}
export function colonyLedger(system: StarSystem, player: Pick<Player, 'techs' | 'empire'> & ComputePlayer): EconomyLine[] {
  const c = system.colony;
  const ledger = c ? colonyEconomy(c, system.planet, { empire: player.empire }).ledger : [];
  const common = player.empire?.economyModifiers ?? [];
  if (system.mined)
    for (const resource of RESOURCE_IDS) {
      if (resource !== 'energy' && resource !== 'minerals') continue;
      ledger.push(
        economyLine(`mining:${resource}`, 'Orbitaler Bergbau', system.resources[resource] ?? 0, common, {
          category: 'mining',
          resource,
        }),
      );
    }
  for (const line of ledger) {
    line.systemId = system.id;
    line.worldId = `${system.id}:${c?.bodySlot ?? 0}`;
    line.id = `${system.id}:${c?.bodySlot ?? 0}:${line.id}`;
    line.source = `${system.colonyName ?? system.name} · ${line.source}`;
    if (line.category === 'upkeep') continue;
    if (player.techs.includes('extraction') && (line.resource === 'energy' || line.resource === 'minerals')) {
      line.modifiers.push({
        id: 'extraction',
        name: 'Extraktionstechnologie +50 %',
        delta: line.amount * 0.5,
      });
      line.amount *= 1.5;
    }
    const factor = system.productionFactor ?? 1;
    if (factor !== 1) {
      line.modifiers.push({
        id: 'production',
        name: 'Reichslage / Krise',
        delta: line.amount * (factor - 1),
      });
      line.amount *= factor;
    }
  }
  return optimizeProduction(ledger, player);
}
export function colonyProduction(system: StarSystem, player: Pick<Player, 'techs' | 'empire'> & ComputePlayer): Resources {
  return economyTotals(colonyLedger(system, player));
}
export function baseLedger(player: Pick<Player, 'techs'> & Partial<Pick<Player, 'empire'>>): EconomyLine[] {
  return RESOURCE_IDS.map((resource) =>
    economyLine(
      `base:${resource}`,
      'Grundversorgung',
      RESOURCE_CATALOG[resource].base,
      [
        ...(player.empire?.economyModifiers ?? []),
        ...(player.techs.includes('extraction') && (resource === 'energy' || resource === 'minerals')
          ? [{ id: 'extraction', name: 'Extraktionstechnologie +50 %', factor: 1.5 }]
          : []),
      ],
      { category: 'base', resource },
    ),
  );
}
export function baseIncome(player: Pick<Player, 'techs'> & Partial<Pick<Player, 'empire'>>): Resources {
  return economyTotals(baseLedger(player));
}
export function maxDefense(s: StarSystem) {
  return (
    starbaseDefense(s.starbase) +
    (s.planetDefense || 0) +
    (s.colony ? colonyEconomy(s.colony, s.planet).defense : 0)
  );
}
export function colonyRepair(s: StarSystem) {
  return (
    starbaseRepair(s.starbase) +
    (s.planetDefense || 0) / 40 +
    (s.colony ? colonyEconomy(s.colony, s.planet).repair : 0)
  );
}
/** One bounded AI choice, shared by the local simulation and native backend. */
export function planColonyDevelopment(s: StarSystem): ColonyCommand | null {
  const c = s.colony;
  if (!c || c.construction) return null;
  const e = colonyEconomy(c, s.planet);
  if (e.housing - c.population >= 2 && e.supplyCapacity >= c.population + 1 && e.jobs >= c.population + 0.5)
    return null;
  const building: BuildingId =
    e.housing - c.population < 2
      ? 'habitat'
      : e.supplyCapacity < c.population + 1
        ? 'biosphere'
        : e.output.energy < 2
          ? 'reactor'
          : e.unemployed > 0.5
            ? (['foundry', 'reactor', 'laboratory'] as const)[c.nextDistrictId % 3]
            : 'laboratory';
  const sector = [...c.sectors]
    .filter((s) => s.districts.length < s.slots)
    .sort((a, b) => featureMultiplier(b, building) - featureMultiplier(a, building) || a.id - b.id)[0];
  if (sector)
    return {
      type: 'colony_build',
      systemId: s.id,
      revision: c.revision,
      sectorId: sector.id,
      slot: Array.from({ length: sector.slots }, (_, slot) => slot).find(
        (slot) => !sector.districts.some((d) => d.slot === slot),
      )!,
      building,
    };
  const d = c.sectors.flatMap((s) => s.districts).find((d) => d.building === building && d.level < 3);
  return d ? { type: 'colony_upgrade', systemId: s.id, revision: c.revision, districtId: d.id } : null;
}
