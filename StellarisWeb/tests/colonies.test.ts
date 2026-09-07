import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  addPlayer,
  command,
  createGame,
  income,
  tickGame,
  viewFor,
  type GameCommand,
  type GameState,
} from '../shared/game';
import {
  assertColonies,
  baseIncome,
  colonyBuildingLevel,
  colonyEconomy,
  colonyProduction,
  createColony,
  districtCapacity,
  districtSpec,
  generateColonySectors,
  growColony,
  maxDefense,
  occupiedDistricts,
  planColonyDevelopment,
  type BuildingId,
} from '../shared/colonies';
function setup() {
  const game = createGame('C01012'),
    player = addPlayer(game, 'p1', 'Terraner'),
    home = game.systems.find((s) => s.id === player.home)!,
    c = home.colony!;
  return { game, player, home, c };
}
function advance(game: GameState, days: number) {
  for (let i = 0; i < days * 4; i++) tickGame(game, 0.25);
}
function near(actual: number, expected: number) {
  assert.ok(Math.abs(actual - expected) < 1e-7, `${actual} ≠ ${expected}`);
}

test('geography is deterministic, different per world and independent of saves/names', () => {
  const a = createColony(true, 'galaxy:s1:1'),
    b = createColony(true, 'galaxy:s2:1');
  assert.deepEqual(a, createColony(true, 'galaxy:s1:1'));
  assert.notDeepEqual(a.sectors, b.sectors);
  assert.deepEqual(JSON.parse(JSON.stringify(a)), a);
  for (let seed = 0; seed < 100; seed++)
    for (const planet of ['Kontinentalwelt', 'Wüstenwelt', 'Ozeanwelt']) {
      const sectors = generateColonySectors(seed, planet);
      assert.ok(sectors.length >= 7 && sectors.length <= 12);
      assert.equal(new Set(sectors.map((s) => `${s.x}:${s.y}`)).size, sectors.length);
      for (const s of sectors) {
        near(s.x * s.x + s.y * s.y + s.z * s.z, 1);
        assert.ok(Math.hypot(s.x, s.y) < 0.81);
        assert.ok(s.slots >= 2 && s.slots <= 3);
      }
    }
  const { game, home } = setup();
  (home.colony as any).schema = 1;
  assert.throws(() => assertColonies(game), /neue Partie/);
});

test('jobs consume population, unstaffed buildings only cost upkeep, and focus reallocates real output', () => {
  const { home, player, c } = setup();
  const balanced = colonyEconomy(c, home.planet, player);
  near(balanced.employed + balanced.unemployed, c.population);
  assert.ok(balanced.supply >= balanced.demand - 1e-8);
  for (const row of balanced.districts) assert.ok(row.employed >= 0 && row.employed <= row.jobs);
  c.focus = 'data';
  const data = colonyEconomy(c, home.planet, player);
  assert.ok(data.output.data > balanced.output.data);
  near(data.employed, balanced.employed);
  c.population = 0;
  const empty = colonyEconomy(c, home.planet, player);
  near(empty.output.data, 0);
  near(empty.output.minerals, 0);
  near(empty.output.energy, -empty.upkeep);
  c.sectors.flatMap((s) => s.districts).forEach((d) => (d.enabled = false));
  near(colonyEconomy(c).output.energy, 0);
});

test('housing and food gate growth and preserve species population totals', () => {
  const { home, player, c } = setup();
  c.population = 7.999;
  c.populations![0].population = c.population;
  c.sectors[0].feature = 'ore';
  c.sectors[0].districts.forEach((d) => (d.level = 1));
  growColony(c, home.planet, player, 1000);
  near(c.population, 8);
  near(
    c.populations!.reduce((n, g) => n + g.population, 0),
    8,
  );
  const housing = c.sectors[0].districts.find((d) => d.building === 'habitat')!;
  housing.level = 2;
  growColony(c, home.planet, player, 1000);
  near(c.population, 8);
  c.sectors[0].districts.find((d) => d.building === 'biosphere')!.level = 2;
  growColony(c, home.planet, player, 60);
  assert.ok(c.population > 8);
  near(c.populations![0].population, c.population);
  housing.enabled = false;
  const before = c.population;
  growColony(c, home.planet, player, 60);
  near(c.population, before);
});

test('construction spends once, pauses, completes in simulation time and persists chosen sector', () => {
  const { game, player, home, c } = setup(),
    spec = districtSpec('reactor'),
    before = player.resources.minerals;
  const build = {
    type: 'colony_build' as const,
    systemId: home.id,
    sectorId: 3,
    building: 'reactor' as const,
    revision: c.revision,
  };
  command(game, player.id, build);
  near(player.resources.minerals, before - spec.cost.minerals);
  assert.equal(c.sectors[3].districts.length, 0);
  assert.throws(() => command(game, player.id, build), /zwischenzeitlich/);
  assert.throws(() => command(game, player.id, { ...build, revision: c.revision }), /bereits/);
  command(game, player.id, { type: 'pause' });
  advance(game, 30);
  near(c.construction!.remaining, spec.time);
  command(game, player.id, { type: 'pause' });
  advance(game, spec.time + 1);
  assert.equal(c.construction, null);
  assert.equal(c.sectors[3].districts[0].building, 'reactor');
  assert.equal(colonyBuildingLevel(c, 'reactor'), 2);
});

test('ownership, full sectors, forged fields, invalid ids and stale revisions reject atomically', () => {
  const { game, player, home, c } = setup();
  addPlayer(game, 'p2', 'Enemy');
  const build = {
    type: 'colony_build' as const,
    systemId: home.id,
    sectorId: 3,
    building: 'reactor' as const,
    revision: c.revision,
  };
  assert.throws(() => command(game, 'p2', build), /eigene Kolonie/);
  const before = JSON.stringify({ c, resources: player.resources });
  for (const change of [
    { building: 'constructor' },
    { building: '__proto__' },
    { sectorId: 999 },
    { revision: NaN },
    { revision: -1 },
  ])
    assert.throws(() => command(game, player.id, { ...build, ...change } as GameCommand));
  assert.throws(() =>
    command(game, player.id, {
      type: 'colony_focus',
      systemId: home.id,
      revision: c.revision,
      focus: '__proto__',
    } as unknown as GameCommand),
  );
  assert.equal(JSON.stringify({ c, resources: player.resources }), before);
  c.sectors[3].slots = 0;
  assert.throws(() => command(game, player.id, build), /belegt/);
});

test('upgrades retain their slot, cancellation refunds once, and disabled districts have no jobs', () => {
  const { game, player, home, c } = setup(),
    d = c.sectors[1].districts[0],
    used = occupiedDistricts(c),
    target = () => ({ systemId: home.id, revision: c.revision });
  player.resources = { energy: 10000, minerals: 10000, data: 10000 };
  command(game, player.id, { type: 'colony_upgrade', districtId: d.id, ...target() });
  assert.throws(
    () => command(game, player.id, { type: 'colony_toggle', districtId: d.id, enabled: false, ...target() }),
    /zuerst abbrechen/,
  );
  assert.throws(
    () => command(game, player.id, { type: 'colony_demolish', districtId: d.id, ...target() }),
    /zuerst abbrechen/,
  );
  advance(game, 40);
  assert.equal(d.level, 2);
  assert.equal(occupiedDistricts(c), used);
  command(game, player.id, { type: 'colony_toggle', districtId: d.id, enabled: false, ...target() });
  assert.equal(colonyEconomy(c).districts.find((r) => r.id === d.id)!.jobs, 0);
  const funds = { ...player.resources };
  command(game, player.id, { type: 'colony_build', sectorId: 3, building: 'foundry', ...target() });
  command(game, player.id, { type: 'colony_cancel', ...target() });
  near(player.resources.energy, funds.energy - 40);
  near(player.resources.minerals, funds.minerals - 40);
  assert.throws(() => command(game, player.id, { type: 'colony_cancel', ...target() }), /Kein planetarer/);
  command(game, player.id, { type: 'colony_demolish', districtId: d.id, ...target() });
  assert.equal(occupiedDistricts(c), used - 1);
});

test('features, mining, technology and net production agree with the ledger', () => {
  const { game, player, home, c } = setup();
  c.focus = 'energy';
  c.sectors[1].feature = 'ore';
  const base = colonyEconomy(c, home.planet, player).output.energy;
  c.sectors[1].feature = 'geothermal';
  assert.ok(colonyEconomy(c, home.planet, player).output.energy > base);
  home.mined = true;
  player.techs.push('extraction');
  const output = colonyProduction(home, player),
    total = income(game, player),
    core = baseIncome(player);
  for (const r of ['energy', 'minerals', 'data'] as const) near(total[r], output[r] + core[r]);
  const before = player.resources.energy;
  advance(game, 4);
  assert.ok(player.resources.energy > before);
});

test('bastions require staff, improve defense and repair, and enemy colony details stay private', () => {
  const { game, player, home, c } = setup();
  command(game, player.id, {
    type: 'colony_build',
    systemId: home.id,
    revision: c.revision,
    sectorId: 3,
    building: 'bastion',
  });
  advance(game, 21);
  near(maxDefense(home), 70);
  const fleet = game.fleets.find((f) => f.type === 'scout')!;
  fleet.hp = 50;
  advance(game, 2);
  near(fleet.hp, 55);
  const enemy = addPlayer(game, 'p2', 'Other');
  assert.equal(viewFor(game, enemy.id).systems.find((s) => s.id === home.id)!.colony, null);
  c.population = 0;
  near(maxDefense(home), 30);
});

test('AI only expands when population or capacity can use it', () => {
  const { home, c } = setup();
  assert.equal(planColonyDevelopment(home), null);
  c.population = 15;
  assert.equal((planColonyDevelopment(home) as any).building, 'habitat');
  assert.ok(districtCapacity(c) >= occupiedDistricts(c));
});

test('forged build district ids cannot turn cheap construction into an upgrade', () => {
  const { game, player, home, c } = setup();
  const habitat = c.sectors[0].districts[0];
  const level = habitat.level;
  command(game, player.id, {
    type: 'colony_build',
    systemId: home.id,
    revision: c.revision,
    sectorId: 0,
    building: 'reactor',
    districtId: habitat.id,
  } as unknown as GameCommand);
  assert.equal(c.construction!.districtId, null);
  assert.equal(c.construction!.level, 1);
  assert.deepEqual(c.construction!.cost, districtSpec('reactor').cost);
  advance(game, 17);
  assert.equal(habitat.level, level);
  assert.equal(c.sectors[0].districts.at(-1)!.building, 'reactor');
  habitat.level = 3;
  assert.throws(
    () =>
      command(game, player.id, {
        type: 'colony_upgrade',
        systemId: home.id,
        revision: c.revision,
        districtId: habitat.id,
      }),
    /Maximale/,
  );
});
