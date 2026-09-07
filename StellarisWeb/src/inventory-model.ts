import { colonyEconomy, type Colony } from '../shared/colonies';
import type { Fleet, GameView, Player, ShipType } from '../shared/game';
import { ownedColonyWorlds } from '../shared/planetColonies';

export const fleetCategories = [
  { id: 'civil', name: 'Zivil', type: 'colony' },
  { id: 'research', name: 'Forschung', type: 'scout' },
  { id: 'military', name: 'Militär', type: 'corvette' },
] as const satisfies readonly { id: string; name: string; type: ShipType }[];
export type InventoryCategory = 'colonies' | (typeof fleetCategories)[number]['id'];
export type InventorySelection = { systemId: string; fleetId?: string; bodySlot?: number };
export type ColonyWorld = ReturnType<typeof ownedColonyWorlds>[number];
export type ColonyEntry = {
  id: string;
  name: string;
  systemId: string;
  systemName: string;
  tier: number;
  workers: number;
  vacancies: number;
  population: number;
  world: ColonyWorld;
};
export type ColonySort = 'name' | 'workers' | 'vacancies' | 'population' | 'tier' | 'manual';
export type ColonyFilter = { query: string; tier: string; status: string; sort: ColonySort; order: string[] };
export type ColonyTreeRow =
  | { kind: 'system'; id: string; systemId: string; name: string; worlds: ColonyEntry[]; total: number; workers: number; population: number; tier: number; vacancies: number }
  | { kind: 'colony'; id: string; colony: ColonyEntry; parentId?: string };
export const inventoryCollator = new Intl.Collator('de', { numeric: true, sensitivity: 'base' });
const economies = new WeakMap<Colony, { planet: string; empire: Player['empire']; workers: number; vacancies: number }>();

export function colonyInventory(game: GameView): ColonyEntry[] {
  return ownedColonyWorlds(game).map((world) => {
    const colony = world.colony!;
    let economy = economies.get(colony);
    if (!economy || economy.planet !== world.planet || economy.empire !== game.me.empire) {
      const e = colonyEconomy(colony, world.planet, game.me);
      economy = { planet: world.planet, empire: game.me.empire, workers: e.unemployed, vacancies: Math.max(0, e.jobs - e.employed) };
      economies.set(colony, economy);
    }
    return {
      id: world.worldId,
      name: world.colonyName || (world.name === 'Sol' ? 'Erde' : `${world.name} Prime`),
      systemId: world.id,
      systemName: world.name,
      // Colonies have district levels, not a separate progression tier.
      tier: colony.sectors.reduce((tier, sector) => sector.districts.reduce((n, d) => Math.max(n, d.level), tier), 0),
      workers: economy.workers,
      vacancies: economy.vacancies,
      population: colony.population,
      world,
    };
  });
}

export function matchesInventory(query: string, text: string) {
  const haystack = text.toLocaleLowerCase('de');
  return query.toLocaleLowerCase('de').trim().split(/\s+/).every((term) => haystack.includes(term));
}

export function filterColonies(entries: ColonyEntry[], filter: ColonyFilter) {
  const rank = new Map(filter.order.map((id, i) => [id, i]));
  return entries.filter((entry) =>
    matchesInventory(filter.query, `${entry.name} ${entry.systemName} ${entry.world.planet}`) &&
    (filter.tier === 'all' || entry.tier === Number(filter.tier)) &&
    (filter.status === 'all' || (filter.status === 'workers' && entry.workers > 0.001) ||
      (filter.status === 'vacancies' && entry.vacancies > 0.001) ||
      (filter.status === 'building' && !!entry.world.colony?.construction)),
  ).sort((a, b) => {
    const delta = filter.sort === 'manual' ? (rank.get(a.id) ?? Infinity) - (rank.get(b.id) ?? Infinity)
      : filter.sort === 'name' ? 0 : b[filter.sort] - a[filter.sort];
    return delta || inventoryCollator.compare(a.name, b.name) || inventoryCollator.compare(a.id, b.id);
  });
}

export function colonyTree(entries: ColonyEntry[], visible: ColonyEntry[], expanded: ReadonlySet<string>, sort: ColonySort, flat = false): ColonyTreeRow[] {
  if (flat) return visible.map((colony) => ({ kind: 'colony', id: `colony:${colony.id}`, colony }));
  const totals = new Map<string, number>();
  for (const entry of entries) totals.set(entry.systemId, (totals.get(entry.systemId) || 0) + 1);
  const groups = new Map<string, Extract<ColonyTreeRow, { kind: 'system' }>>();
  for (const colony of visible) {
    let group = groups.get(colony.systemId);
    if (!group) {
      group = { kind: 'system', id: `system:${colony.systemId}`, systemId: colony.systemId, name: colony.systemName, worlds: [], total: totals.get(colony.systemId)!, workers: 0, vacancies: 0, population: 0, tier: 0 };
      groups.set(colony.systemId, group);
    }
    group.worlds.push(colony);
    group.workers += colony.workers;
    group.vacancies += colony.vacancies;
    group.population += colony.population;
    group.tier = Math.max(group.tier, colony.tier);
  }
  const sorted = [...groups.values()].sort((a, b) =>
    (sort !== 'name' && sort !== 'manual' ? b[sort] - a[sort] : 0) || inventoryCollator.compare(a.name, b.name));
  return sorted.flatMap((group): ColonyTreeRow[] => [group, ...(expanded.has(group.systemId)
    ? group.worlds.map((colony): ColonyTreeRow => ({ kind: 'colony', id: `colony:${colony.id}`, colony, parentId: group.id })) : [])]);
}

export function fleetAvailable(fleet: Fleet) {
  return !fleet.route.length && !fleet.task && !fleet.navigation?.orders.length && !fleet.battleId &&
    !fleet.navigation?.motion.paused && fleet.navigation?.phase !== 'braking';
}
export function fleetInventoryStatus(fleet: Fleet) {
  if (fleet.battleId) return 'Gefecht';
  if (fleet.task?.blocked || fleet.navigation?.motion.paused) return 'Blockiert';
  if (fleet.route.length) return 'Hyperraum';
  if (fleet.task) return fleet.task.type === 'scan' ? 'Erkundung' : 'Kolonisierung';
  if (fleet.navigation?.orders.length) return 'Auftrag';
  if (fleet.navigation?.phase === 'braking') return 'Bremst';
  return 'Verfügbar';
}

/** Move to the target position without dropping filtered-out or unseen siblings. */
export function reorderInventory(ids: readonly string[], source: string, target: string): string[] {
  const from = ids.indexOf(source), to = ids.indexOf(target);
  if (from < 0 || to < 0 || from === to) return [...ids];
  const next = [...ids];
  next.splice(from, 1);
  next.splice(to, 0, source);
  return next;
}

export function virtualWindow(count: number, top: number, height: number, rowHeight: number, overscan = 5) {
  const first = Math.min(Math.max(0, count - 1), Math.max(0, Math.floor(top / rowHeight)));
  return { start: Math.max(0, first - overscan), end: Math.min(count, first + Math.ceil(height / rowHeight) + overscan) };
}
