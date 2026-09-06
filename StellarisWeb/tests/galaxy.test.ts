import test from 'node:test';
import assert from 'node:assert/strict';
import { createGalaxy } from '../shared/galaxy';
import {
  DEFAULT_GALAXY_SETTINGS,
  GALAXY_TYPES,
  GALAXY_SIZES,
  parseGalaxySettings,
  type GalaxySettings,
} from '../shared/galaxySettings';
import { blackHoleRadius, buildTerritories, layoutGalaxyLabels } from '../src/galaxy-cartography';
import { createGame, type StarSystem } from '../shared/game';

for (const type of Object.keys(GALAXY_TYPES) as GalaxySettings['type'][])
  for (const systems of GALAXY_SIZES) {
    test(`${type}, ${systems}: exact population, separated systems, connected short lanes`, () => {
      const game = createGalaxy('ABC123', 731, { type, systems, hyperlaneDensity: 'sparse' });
      assert.equal(game.systems.length, systems);
      assert.equal(new Set(game.systems.map((s) => s.id)).size, systems);
      const graph = new Map(game.systems.map((s) => [s.id, [] as string[]]));
      const edges = new Set<string>();
      for (const [a, b] of game.links) {
        assert.notEqual(a, b);
        assert(graph.has(a) && graph.has(b));
        const key = [a, b].sort().join(':');
        assert(!edges.has(key));
        edges.add(key);
        graph.get(a)!.push(b);
        graph.get(b)!.push(a);
      }
      const seen = new Set<string>(),
        pending = [game.systems[0].id];
      while (pending.length) {
        const id = pending.pop()!;
        if (seen.has(id)) continue;
        seen.add(id);
        pending.push(...graph.get(id)!);
      }
      assert.equal(seen.size, systems);
      const scale = Math.sqrt(systems / 1000) * 0.4 + 0.6;
      for (let i = 0; i < systems; i++) {
        const s = game.systems[i];
        assert(Number.isFinite(s.x) && Number.isFinite(s.y));
        const radial = Math.hypot((s.x - 800) / (720 * scale), (s.y - 525) / (440 * scale));
        assert(radial <= 1.001, 'no rectangular corners');
        if (type === 'ring') assert(radial >= 0.479, 'ring center stays empty');
        for (let j = 0; j < i; j++)
          assert(Math.hypot(s.x - game.systems[j].x, s.y - game.systems[j].y) >= 4.98, 'no coincident stars');
      }
      assert(game.systems.some((s) => s.id === 'void' && s.kind === 'blackhole'));
      assert(game.systems.some((s) => s.id === 'rift'));
    });
  }
test('density changes routing without moving stars; seeds reproduce morphology', () => {
  const variants = (['sparse', 'normal', 'dense'] as const).map((hyperlaneDensity) =>
    createGalaxy('ABC123', 12, { type: 'spiral', systems: 400, hyperlaneDensity }),
  );
  assert.deepEqual(variants[0].systems, variants[2].systems);
  assert(
    variants[0].links.length < variants[1].links.length &&
      variants[1].links.length < variants[2].links.length,
  );
  assert.deepEqual(
    createGalaxy('ABC123', 12, { type: 'spiral', systems: 400, hyperlaneDensity: 'normal' }),
    variants[1],
  );
  assert.notDeepEqual(
    createGalaxy('ABC123', 13, { type: 'spiral', systems: 400, hyperlaneDensity: 'normal' }).systems,
    variants[1].systems,
  );
});
test('unsupported creation parameters fail instead of provisioning arbitrary worlds', () => {
  assert.deepEqual(parseGalaxySettings(undefined), DEFAULT_GALAXY_SETTINGS);
  for (const input of [
    null,
    [],
    {},
    { ...DEFAULT_GALAXY_SETTINGS, systems: 999 },
    { ...DEFAULT_GALAXY_SETTINGS, type: 'constructor' },
    { ...DEFAULT_GALAXY_SETTINGS, hyperlaneDensity: 'toString' },
  ])
    assert.throws(() => parseGalaxySettings(input));
});
test('LOD avoids collisions at maximum zoom and keeps selected systems legible in overview', () => {
  const systems = createGalaxy('ABC123', 731).systems;
  for (const zoom of [0.3, 0.6, 1, 1.7, 3.8]) {
    const selected = systems[400];
    const labels = layoutGalaxyLabels(
      systems,
      { x: selected.x, y: selected.y, zoom },
      { width: 1400, height: 900 },
      selected.id,
      null,
      's0',
      new Set(),
      (s) => s.length * 7,
    );
    assert(labels.some((l) => l.system.id === selected.id));
    assert(labels.length <= 180);
    for (let i = 0; i < labels.length; i++)
      for (let j = 0; j < i; j++) {
        const a = labels[i],
          b = labels[j];
        assert(
          Math.abs(a.x - b.x) >= (a.width + b.width) / 2 || a.y >= b.y + b.height || b.y >= a.y + a.height,
        );
      }
  }
});
test('regular black holes remain compact while Erebus keeps its landmark scale', () => {
  const erebus = createGame('ABC123').systems.find((s) => s.id === 'void')!;
  for (const zoom of [0.25, 1, 3.8]) {
    const regular = blackHoleRadius({ ...erebus, id: 's97' }, zoom);
    assert(regular >= 7 && regular <= 13);
    assert(blackHoleRadius(erebus, zoom) > regular);
  }
});
test('labels reserve space for headings, search and command panels', () => {
  const star = { ...createGame('ABC123').systems[0], x: 400, y: 300 };
  const labels = layoutGalaxyLabels(
    [star],
    { x: 400, y: 300, zoom: 1 },
    { width: 800, height: 600 },
    star.id,
    null,
    star.id,
    new Set(),
    () => 30,
    [{ x: 350, y: 300, width: 100, height: 80 }],
  );
  assert.equal(labels.length, 0);
});
test('territory cells respect neutral neighbors, merge internal borders and preserve islands', () => {
  const base = createGame('ABC123').systems[0];
  const stars: StarSystem[] = [
    { ...base, id: 'a', x: 0, y: 0, owner: 'p1' },
    { ...base, id: 'b', x: 50, y: 0, owner: 'p1' },
    { ...base, id: 'c', x: 100, y: 0, owner: null },
    { ...base, id: 'island', x: 1000, y: 0, owner: 'p1' },
    { ...base, id: 'rival', x: 100, y: 150, owner: 'p2' },
  ];
  const territories = buildTerritories(stars);
  const own = territories.find((t) => t.owner === 'p1')!;
  assert.equal(own.cells.length, 3);
  assert(
    !own.edges.some(([a, b]) => Math.abs(a.x - 25) < 0.001 && Math.abs(b.x - 25) < 0.001),
    'shared border removed',
  );
  for (const cell of own.cells.slice(0, 2))
    for (const p of cell) assert(p.x <= 75.001, 'neutral star not annexed');
  for (const cell of own.cells)
    assert(
      Math.max(...cell.map((p) => p.x)) - Math.min(...cell.map((p) => p.x)) <= 220.01,
      'no bridge through empty space',
    );
  assert.deepEqual(buildTerritories(stars.map((s) => ({ ...s, owner: null }))), []);
});
