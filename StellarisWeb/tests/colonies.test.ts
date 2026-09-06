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
} from '../shared/game.ts';
import {
  baseIncome,
  colonyProduction,
  districtCapacity,
  hydrateColonies,
  occupiedDistricts,
  upgradeSpec,
} from '../shared/colonies.ts';
function setup() {
  const game = createGame('C01012');
  const player = addPlayer(game, 'p1', 'Terraner');
  return { game, player, home: game.systems.find((s) => s.id === player.home)! };
}
function advance(game: GameState, seconds: number) {
  for (let i = 0; i < seconds * 4; i++) tickGame(game, 0.25);
}

test('legacy save migration preserves ownership, resources, ship orders and identifiers', () => {
  const { game, player, home } = setup();
  const ship = game.fleets[0];
  command(game, player.id, { type: 'move', fleetId: ship.id, systemId: 's1' });
  for (const s of game.systems) delete s.colony;
  const before = JSON.stringify({ players: game.players, fleets: game.fleets, code: game.code });
  hydrateColonies(game);
  assert.equal(home.colony!.population, 6);
  assert.equal(home.colony!.focus, 'balanced');
  assert.equal(JSON.stringify({ players: game.players, fleets: game.fleets, code: game.code }), before);
  const migrated = JSON.stringify(game);
  hydrateColonies(game);
  assert.equal(JSON.stringify(game), migrated);
});
test('colony construction spends once, takes simulation time and changes real production', () => {
  const { game, player, home } = setup();
  const spec = upgradeSpec(home.colony!, 'reactor');
  const minerals = player.resources.minerals,
    rate = income(game, player);
  command(game, player.id, { type: 'colony_upgrade', systemId: home.id, building: 'reactor' });
  assert.equal(player.resources.minerals, minerals - spec.cost.minerals);
  assert.equal(home.colony!.buildings.reactor, 0);
  assert.throws(
    () => command(game, player.id, { type: 'colony_upgrade', systemId: home.id, building: 'reactor' }),
    /bereits/,
  );
  command(game, player.id, { type: 'pause' });
  advance(game, 30);
  assert.equal(home.colony!.construction!.remaining, spec.time);
  command(game, player.id, { type: 'pause' });
  advance(game, spec.time + 1);
  assert.equal(home.colony!.buildings.reactor, 1);
  assert.equal(home.colony!.construction, null);
  assert.equal(income(game, player).energy, rate.energy + 4);
});
test('district limits, ownership and malicious enum values are enforced by the server rules', () => {
  const { game, player, home } = setup();
  addPlayer(game, 'p2', 'Enemy');
  assert.throws(
    () => command(game, 'p2', { type: 'colony_upgrade', systemId: home.id, building: 'reactor' }),
    /eigene Kolonie/,
  );
  assert.throws(
    () =>
      command(game, player.id, {
        type: 'colony_upgrade',
        systemId: home.id,
        building: 'constructor',
      } as unknown as GameCommand),
    /Unbekannter/,
  );
  assert.throws(
    () =>
      command(game, player.id, {
        type: 'colony_focus',
        systemId: home.id,
        focus: '__proto__',
      } as unknown as GameCommand),
    /Unbekannter/,
  );
  home.colony!.buildings.reactor = 3;
  assert.throws(
    () => command(game, player.id, { type: 'colony_upgrade', systemId: home.id, building: 'reactor' }),
    /Maximale/,
  );
  home.colony!.buildings.foundry = 3;
  home.colony!.buildings.laboratory = 1;
  assert.equal(occupiedDistricts(home.colony!), districtCapacity(home.colony!));
  assert.throws(
    () => command(game, player.id, { type: 'colony_upgrade', systemId: home.id, building: 'bastion' }),
    /belegt/,
  );
});
test('focus, mining, district output and technology agree with the economic ledger', () => {
  const { game, player, home } = setup();
  home.mined = true;
  home.colony!.buildings.laboratory = 2;
  player.techs.push('extraction');
  command(game, player.id, { type: 'colony_focus', systemId: home.id, focus: 'science' });
  const production = colonyProduction(home, player);
  assert.ok(Math.abs(production.science - (home.resources.science + 6) * 1.4) < 1e-8);
  assert.equal(production.energy, home.resources.energy * 2 * 0.85 * 1.5);
  const base = baseIncome(player),
    total = income(game, player);
  for (const r of ['energy', 'minerals', 'science'] as const) assert.equal(total[r], base[r] + production[r]);
  const before = { ...player.resources };
  advance(game, 4);
  for (const r of ['energy', 'minerals', 'science'] as const)
    assert.ok(Math.abs(player.resources[r] - before[r] - total[r]) < 1e-8);
});
test('cancelling construction refunds 50 percent exactly once', () => {
  const { game, player, home } = setup();
  const before = { ...player.resources };
  command(game, player.id, { type: 'colony_upgrade', systemId: home.id, building: 'foundry' });
  command(game, player.id, { type: 'colony_cancel', systemId: home.id });
  assert.equal(player.resources.energy, before.energy - 40);
  assert.equal(player.resources.minerals, before.minerals - 40);
  assert.throws(
    () => command(game, player.id, { type: 'colony_cancel', systemId: home.id }),
    /Kein planetarer/,
  );
  advance(game, 25);
  assert.equal(home.colony!.buildings.foundry, 0);
});
test('growing population unlocks districts, and hostile fleets prevent peaceful repairs', () => {
  const { game, player, home } = setup();
  home.colony!.population = 7.99;
  const before = districtCapacity(home.colony!);
  advance(game, 3);
  assert.equal(districtCapacity(home.colony!), before + 1);
  const fleet = game.fleets.find((f) => f.type === 'corvette')!;
  fleet.hp = 40;
  advance(game, 4);
  assert.equal(fleet.hp, 46);
  const enemy = addPlayer(game, 'p2', 'Enemy'),
    hostile = game.fleets.find((f) => f.owner === enemy.id && f.type === 'corvette')!;
  hostile.systemId = home.id;
  const hp = fleet.hp;
  advance(game, 1);
  assert.ok(fleet.hp < hp);
  assert.equal(viewFor(game, enemy.id).systems.find((s) => s.id === home.id)!.colony, null);
});
test('shield bastions add real defense and repairs, and capture destroys colony infrastructure', () => {
  const { game, player, home } = setup();
  command(game, player.id, { type: 'colony_upgrade', systemId: home.id, building: 'bastion' });
  advance(game, 21);
  assert.equal(home.defense, 70);
  const fleet = game.fleets.find((f) => f.type === 'scout')!;
  fleet.hp = 50;
  advance(game, 2);
  assert.equal(fleet.hp, 55);
  const other = addPlayer(game, 'p2', 'Other');
  const enemy = game.fleets.find((f) => f.owner === other.id && f.type === 'corvette')!;
  game.fleets = game.fleets.filter((f) => f.owner !== player.id);
  enemy.systemId = home.id;
  home.defense = 1;
  advance(game, 1);
  assert.equal(home.owner, null);
  assert.equal(home.colony, null);
});
