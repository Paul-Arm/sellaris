import { test } from 'node:test';
import assert from 'node:assert/strict';
import { colonyInventory, colonyTree, filterColonies, fleetAvailable, reorderInventory, virtualWindow, type ColonyEntry } from '../src/inventory-model';
import { createGame, addPlayer, viewFor, type Fleet } from '../shared/game';

function entries(count = 2000): ColonyEntry[] {
  return Array.from({ length: count }, (_, i) => ({
    id: `c${i}`, name: `Kolonie ${i}`, systemId: `s${Math.floor(i / 2)}`, systemName: `System ${Math.floor(i / 2)}`,
    workers: i % 9, vacancies: i % 5, population: 5 + i % 9, tier: i % 4,
    world: { planet: 'Kontinentalwelt', colony: { construction: null } } as ColonyEntry['world'],
  }));
}
const base = { query: '', tier: 'all', status: 'all', sort: 'name' as const, order: [] };

test('1,000 systems retain every colony while the virtual window stays bounded', () => {
  const all = entries(), visible = filterColonies(all, base);
  const collapsed = colonyTree(all, visible, new Set(), 'name');
  assert.equal(collapsed.length, 1000);
  const expanded = colonyTree(all, visible, new Set(all.map((c) => c.systemId)), 'name');
  assert.equal(expanded.length, 3000);
  assert.equal(expanded.filter((r) => r.kind === 'colony').length, 2000);
  const range = virtualWindow(expanded.length, 999999, 520, 34);
  assert.equal(range.end, expanded.length);
  assert.ok(range.end - range.start <= Math.ceil(520 / 34) + 10);
  assert.deepEqual(virtualWindow(0, 0, 520, 34), { start: 0, end: 0 });
});
test('tier, workers, search and ordering compose before tree expansion', () => {
  const all = entries();
  const filtered = filterColonies(all, { ...base, query: 'System 99', tier: '3', status: 'workers', sort: 'workers' });
  assert.ok(filtered.length > 0);
  assert.ok(filtered.every((c) => c.tier === 3 && c.workers > 0 && `${c.systemName} ${c.name}`.includes('99')));
  assert.ok(filtered.every((c, i) => i === 0 || filtered[i - 1].workers >= c.workers));
  const rows = colonyTree(all, filtered, new Set(filtered.map((c) => c.systemId)), 'workers');
  const groups = rows.filter((r) => r.kind === 'system');
  assert.ok(groups.every((r, i) => i === 0 || groups[i - 1].workers >= r.workers));
  assert.equal(rows.filter((r) => r.kind === 'colony').length, filtered.length);
  const flat = colonyTree(all, filtered, new Set(), 'workers', true);
  assert.equal(flat.length, filtered.length);
  assert.ok(flat.every((r) => r.kind === 'colony' && !r.parentId));
});
test('manual ordering retains hidden siblings and remains stable when new items arrive', () => {
  const ids = ['a', 'hidden', 'b', 'c'];
  assert.deepEqual(reorderInventory(ids, 'c', 'a'), ['c', 'a', 'hidden', 'b']);
  assert.deepEqual(ids, ['a', 'hidden', 'b', 'c']);
  assert.deepEqual(reorderInventory(ids, 'missing', 'a'), ids);
  const all = entries(5);
  const ordered = filterColonies(all, { ...base, sort: 'manual', order: ['c3', 'c1'] });
  assert.deepEqual(ordered.map((c) => c.id), ['c3', 'c1', 'c0', 'c2', 'c4']);
});
test('worker counts come from actual employment, including secondary colonies', () => {
  const state = createGame('INV123'), player = addPlayer(state, 'p1', 'Test');
  const game = viewFor(state, player.id), home = game.systems.find((s) => s.id === player.home)!;
  const colony = structuredClone(home.colony!);
  colony.population = 7;
  colony.sectors.forEach((s) => { s.districts = []; });
  game.planetColonies = [{ objectId: 'secondary', systemId: home.id, bodySlot: 2, name: 'Nebenwelt', planet: home.planet, colony }];
  const inventory = colonyInventory(game);
  const secondary = inventory.find((c) => c.id === 'secondary')!;
  assert.equal(secondary.workers, 7);
  assert.equal(secondary.vacancies, 0);
  assert.equal(secondary.tier, 0);
  assert.equal(secondary.systemId, home.id);
  assert.ok(inventory.some((c) => c.id === home.id));
});
test('availability excludes combat, queued movement, blocked motion and braking', () => {
  const idle = { route: [], task: null } as unknown as Fleet;
  assert.equal(fleetAvailable(idle), true);
  assert.equal(fleetAvailable({ ...idle, battleId: 1 }), false);
  assert.equal(fleetAvailable({ ...idle, route: ['s1'] }), false);
  assert.equal(fleetAvailable({ ...idle, navigation: { phase: 'braking', orders: [], motion: {} } as unknown as Fleet['navigation'] }), false);
  assert.equal(fleetAvailable({ ...idle, navigation: { phase: 'idle', orders: [], motion: { paused: true } } as unknown as Fleet['navigation'] }), false);
});
