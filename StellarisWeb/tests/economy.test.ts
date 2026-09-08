import test from 'node:test';
import assert from 'node:assert/strict';
import { addPlayer, createGame, tickGame, command, income } from '../shared/game';
import { createColony, colonyEconomy, colonyLedger, baseIncome } from '../shared/planetaryEconomy';
import { economyTotals, resourceBalance, modifyEconomy, monthsDue, monthBoundary } from '../shared/economy';
import { empireLedger, empireCompute } from '../shared/empireEconomy';
import { RESOURCE_IDS, resourceAmounts } from '../shared/resources';

const near = (a: number, b: number) => assert.ok(Math.abs(a - b) < 1e-7, `${a} != ${b}`);

test('Compute boosts material production without changing upkeep, capacity or population-based unity', () => {
  const { game, player, system, colony } = setup();
  const before = empireLedger(game, player),
    capacity = empireCompute(game, player);
  command(game, player.id, { type: 'compute_allocation', use: 'production', percent: 50 });
  const after = empireLedger(game, player);
  near(empireCompute(game, player), capacity);
  near(resourceBalance(after, 'energy').expenses, resourceBalance(before, 'energy').expenses);
  assert(resourceBalance(after, 'energy').income > resourceBalance(before, 'energy').income);
  const boostedJobs = colonyEconomy(colony, system.planet, { ...player, compute: capacity });
  assert(boostedJobs.ledger.some((line) => line.modifiers.some((modifier) => modifier.id === 'compute-production')));
  near(resourceBalance(after, 'unity').net, resourceBalance(before, 'unity').net);
  assert(resourceBalance(after, 'unity').net > 0);
  const expected = income(game, player),
    stock = { ...player.resources };
  for (let i = 0; i < 30; i++) tickGame(game, 1);
  for (const resource of RESOURCE_IDS) near(player.resources[resource], stock[resource] + expected[resource]);
  const unity = colonyEconomy(colony, system.planet, player).output.unity;
  colony.population *= 2;
  near(colonyEconomy(colony, system.planet, player).output.unity, unity * 2);
  const governed = colonyEconomy(colony, system.planet, player).output.unity;
  player.empire!.design.government.authority = 'oligarchic';
  assert(colonyEconomy(colony, system.planet, player).output.unity < governed);
});
function setup() {
  const game = createGame('EC0101'),
    player = addPlayer(game, 'economy', 'Economy');
  const system = game.systems.find((s) => s.owner === player.id)!;
  return { game, player, system, colony: system.colony! };
}
test('one global monthly boundary; no fractional payout, growth or research between months', () => {
  const { game, player, colony } = setup();
  const initial = { ...player.resources },
    population = colony.population;
  const forecast = income(game, player);
  for (let i = 0; i < 29; i++) tickGame(game, 1);
  assert.deepEqual(player.resources, initial);
  assert.equal(colony.population, population);
  tickGame(game, 1);
  for (const id of RESOURCE_IDS) near(player.resources[id], initial[id] + forecast[id]);
  assert(colony.population > population);
  const closing = { ...player.resources };
  tickGame(game, 0);
  tickGame(game, 1);
  assert.deepEqual(player.resources, closing);
  assert.equal(monthsDue(29, 30), 1);
  assert.equal(monthsDue(30, 90), 2);
  assert.equal(monthsDue(60, 59), 0);
  assert.equal(monthBoundary(59.999), 30);
});
test('research costs are immediate; changing allocation cannot reset the monthly anchor', () => {
  const { game, player } = setup();
  player.resources.data = 1000;
  command(game, player.id, { type: 'research', tech: 'computing' });
  assert.equal(player.resources.data, 950);
  for (let i = 0; i < 29; i++) tickGame(game, 1);
  assert.equal(player.research.projects[0].done, 0);
  command(game, player.id, { type: 'compute_allocation', use: 'synthesis', percent: 0 });
  const compute = empireCompute(game, player);
  tickGame(game, 1);
  near(player.research.projects[0].done, compute);
  command(game, player.id, { type: 'pause' });
  const frozen = JSON.stringify(game);
  tickGame(game, 2);
  assert.equal(JSON.stringify(game), frozen);
});
test('build costs and refunds book once immediately, without earning partial monthly income', () => {
  const { game, player, system, colony } = setup();
  game.tick = 29;
  const before = { ...player.resources };
  command(game, player.id, {
    type: 'colony_build',
    slot: 0,
    systemId: system.id,
    sectorId: 3,
    building: 'reactor',
    revision: colony.revision,
  });
  near(player.resources.energy, before.energy - 50);
  command(game, player.id, { type: 'colony_cancel', systemId: system.id, revision: colony.revision });
  near(player.resources.energy, before.energy - 25);
  assert.throws(() =>
    command(game, player.id, { type: 'colony_cancel', systemId: system.id, revision: colony.revision }),
  );
});
test('modifier selectors compose across all categories, percentage debuffs and multipliers', () => {
  const modifiers = [
    { id: 'a', name: 'Bonus', percent: 0.5, category: 'jobs' as const },
    { id: 'b', name: 'Malus', percent: -0.25, resource: 'energy' as const },
    { id: 'c', name: 'Job', factor: 2, job: 'reactor', speciesId: 'a' },
    { id: 'd', name: 'Flat', flat: 1, category: 'jobs' as const },
  ];
  const result = modifyEconomy(3, modifiers, {
    category: 'jobs',
    resource: 'energy',
    job: 'reactor',
    speciesId: 'a',
  });
  near(result.amount, 10);
  near(
    result.modifiers.reduce((n, m) => n + m.delta, 3),
    10,
  );
  near(modifyEconomy(3, modifiers, { category: 'upkeep', resource: 'minerals' }).amount, 3);
  assert.equal(
    modifyEconomy(3, [{ id: 'zero', name: 'Disabled', percent: -5 }], { category: 'jobs' }).amount,
    0,
  );
});
test('species specialize in actual staffed jobs; reversing input order does not change the result', () => {
  const { player, colony } = setup();
  const original = player.empire!.species[0];
  player.empire!.species = [
    {
      ...original,
      id: 'technicians',
      name: 'Techniker',
      economyModifiers: [{ id: 'energy', name: 'Technik', category: 'jobs', resource: 'energy', percent: 1 }],
    },
    {
      ...original,
      id: 'miners',
      name: 'Bergleute',
      economyModifiers: [{ id: 'ore', name: 'Bergbau', category: 'jobs', resource: 'minerals', percent: 1 }],
    },
  ];
  colony.population = 6;
  colony.populations = [
    { speciesId: 'technicians', population: 3 },
    { speciesId: 'miners', population: 3 },
  ];
  const first = colonyEconomy(colony, 'Kontinentalwelt', player);
  const reactor = first.districts.find((d) => d.building === 'reactor')!;
  const mine = first.districts.find((d) => d.building === 'foundry')!;
  assert(reactor.workers.every((w) => w.speciesId === 'technicians'));
  assert(mine.workers.every((w) => w.speciesId === 'miners'));
  for (const group of colony.populations)
    assert(
      first.districts.reduce(
        (n, r) =>
          n + r.workers.filter((w) => w.speciesId === group.speciesId).reduce((m, w) => m + w.employed, 0),
        0,
      ) <=
        group.population + 1e-8,
    );
  colony.populations.reverse();
  assert.deepEqual(colonyEconomy(colony, 'Kontinentalwelt', player), first);
});
test('ledger accounts separately for gross production and maintenance, including crisis and technology', () => {
  const { game, player, system, colony } = setup();
  system.productionFactor = 0.4;
  system.mined = true;
  player.techs.push('extraction');
  colony.economyModifiers = [{ id: 'upkeep', name: 'Energiekrise', category: 'upkeep', percent: 1 }];
  const lines = empireLedger(game, player);
  assert.deepEqual(income(game, player), economyTotals(lines));
  for (const line of lines) near(line.base + line.modifiers.reduce((n, m) => n + m.delta, 0), line.amount);
  const energy = resourceBalance(lines, 'energy');
  near(energy.net, energy.income - energy.expenses);
  assert(energy.expenses > 0);
  assert(
    lines
      .filter((l) => l.category === 'upkeep')
      .every((l) => !l.modifiers.some((m) => m.id === 'production' || m.id === 'extraction')),
  );
  assert(colonyLedger(system, player).some((l) => l.species && l.employed));
});
test('disabled districts contribute neither jobs nor upkeep; large populations stay cohort-sized', () => {
  const c = createColony(true);
  c.population = 1e12;
  c.populations = [{ speciesId: 'billions', population: c.population }];
  const result = colonyEconomy(c);
  assert(result.districts.flatMap((d) => d.workers).length <= result.districts.length);
  near(result.employed + result.unemployed, c.population);
  c.sectors.forEach((s) => s.districts.forEach((d) => (d.enabled = false)));
  assert.deepEqual(colonyEconomy(c).output, resourceAmounts({ unity: c.population * 0.5 }));
});
test('new resource entries get zero balances without changing the arithmetic engine', () => {
  assert.deepEqual(Object.keys(resourceAmounts()), RESOURCE_IDS);
  const { player } = setup();
  player.empire!.economyModifiers = [
    { id: 'base', name: 'Grundversorgung', category: 'base', resource: 'data', percent: 0.5 },
  ];
  near(baseIncome(player).data, 1.5);
});

test('wasteful species use canonical upkeep rules without reducing gross energy production', () => {
  const { player, colony } = setup();
  const initial = colonyEconomy(colony, 'Kontinentalwelt', player);
  player.empire.species[0].traits = ['wasteful'];
  const wasteful = colonyEconomy(colony, 'Kontinentalwelt', player);
  near(wasteful.upkeep, initial.upkeep * 1.1);
  near(wasteful.output.energy + wasteful.upkeep, initial.output.energy + initial.upkeep);
  const efficient = { ...player.empire.species[0], id: 'efficient', traits: [] };
  player.empire.species.push(efficient);
  colony.populations = [
    { speciesId: player.empire.primarySpeciesId, population: colony.population / 2 },
    { speciesId: efficient.id, population: colony.population / 2 },
  ];
  const mixed = colonyEconomy(colony, 'Kontinentalwelt', player);
  near(mixed.upkeep, initial.upkeep * 1.05);
});
