import { colonyEconomy } from '../shared/colonies';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  addPlayer,
  command,
  createGame,
  income,
  pathfind,
  tickGame,
  viewFor,
  type GameCommand,
  type GameState,
} from '../shared/game.ts';
function setup() {
  const game = createGame('ABC123');
  const p = addPlayer(game, 'p1', 'Terraner');
  return { game, p };
}
function advance(game: GameState, seconds: number) {
  for (let i = 0; i < seconds * 4; i++) tickGame(game, 0.25);
}

test('all systems are reachable and four players get distinct homes', () => {
  const { game } = setup();
  for (let i = 2; i <= 4; i++) addPlayer(game, `p${i}`, `Player ${i}`);
  assert.equal(new Set(game.players.map((p) => p.home)).size, 4);
  assert.throws(() => addPlayer(game, 'p5', 'Fifth'), /voll/);
  for (const s of game.systems) assert.notEqual(pathfind(game, 's0', s.id), null);
});
test('rejects unauthorized commands, invalid identifiers and insufficient resources without mutation', () => {
  const { game, p } = setup();
  addPlayer(game, 'p2', 'Other');
  const fleet = game.fleets.find((f) => f.owner === 'p2')!;
  assert.throws(
    () => command(game, p.id, { type: 'move', fleetId: fleet.id, systemId: 's1' }),
    /Eigene Flotte/,
  );
  assert.throws(() => command(game, p.id, { type: 'mine', systemId: 's22' }), /eigene Kolonie/);
  assert.throws(
    () => command(game, p.id, { type: 'research', tech: 'toString' } as unknown as GameCommand),
    /Unbekannte/,
  );
  assert.throws(
    () =>
      command(game, p.id, { type: 'build', ship: 'constructor', systemId: 's0' } as unknown as GameCommand),
    /Unbekannter/,
  );
  p.resources.minerals = 0;
  const before = structuredClone(p.resources);
  assert.throws(() => command(game, p.id, { type: 'build', ship: 'corvette', systemId: 's0' }), /Ressourcen/);
  assert.deepEqual(p.resources, before);
  assert.equal(p.queue.length, 0);
});
test('full exploration and colonization flow consumes a colony ship and increases income', () => {
  const { game, p } = setup();
  const scout = game.fleets.find((f) => f.type === 'scout')!,
    colony = game.fleets.find((f) => f.type === 'colony')!;
  command(game, p.id, { type: 'move', fleetId: scout.id, systemId: 's1' });
  advance(game, 12);
  assert.equal(scout.systemId, 's1');
  assert.equal(scout.route.length, 0);
  command(game, p.id, { type: 'scan', fleetId: scout.id });
  const data = p.resources.data;
  advance(game, 9);
  assert.ok(p.surveyed.includes('s1'));
  assert.ok(p.resources.data >= data + 90);
  const rate = income(game, p);
  command(game, p.id, { type: 'move', fleetId: colony.id, systemId: 's1' });
  advance(game, 12);
  command(game, p.id, { type: 'colonize', fleetId: colony.id });
  advance(game, 13);
  assert.equal(game.systems.find((s) => s.id === 's1')!.owner, p.id);
  assert.ok(!game.fleets.find((f) => f.id === colony.id));
  assert.ok(income(game, p).energy > rate.energy);
});
test('colonization requires a survey and a colony ship; duplicate scans cannot grant repeat rewards', () => {
  const { game, p } = setup();
  const scout = game.fleets.find((f) => f.type === 'scout')!,
    colony = game.fleets.find((f) => f.type === 'colony')!;
  colony.systemId = 's1';
  assert.throws(() => command(game, p.id, { type: 'colonize', fleetId: colony.id }), /Untersuche/);
  assert.throws(() => command(game, p.id, { type: 'colonize', fleetId: scout.id }), /Kolonieschiff/);
  assert.throws(() => command(game, p.id, { type: 'scan', fleetId: scout.id }), /bereits untersucht/);
  colony.systemId = 'rift';
  assert.throws(() => command(game, p.id, { type: 'colonize', fleetId: colony.id }), /nicht kolonisiert/);
});
test('mining and research change real production and disallow duplicate spending', () => {
  const { game, p } = setup();
  const before = income(game, p);
  command(game, p.id, { type: 'mine', systemId: p.home });
  const home = game.systems.find((s) => s.id === p.home)!;
  assert.equal(income(game, p).energy, before.energy + home.resources.energy);
  assert.throws(() => command(game, p.id, { type: 'mine', systemId: p.home }), /bereits/);
  command(game, p.id, { type: 'research', tech: 'extraction' });
  advance(game, 54);
  assert.ok(p.techs.includes('extraction'));
  const current = colonyEconomy(home.colony!, home.planet, p);
  assert.ok(
    Math.abs(
      income(game, p).energy -
        ((current.output.energy + current.upkeep + home.resources.energy) * 1.5 - current.upkeep + 3),
    ) < 1e-8,
  );
  assert.throws(() => command(game, p.id, { type: 'research', tech: 'extraction' }), /Bereits/);
});
test('host pause is authoritative and build queues resolve sequentially', () => {
  const { game, p } = setup();
  addPlayer(game, 'p2', 'Other');
  assert.throws(() => command(game, 'p2', { type: 'pause' }), /Host/);
  assert.throws(() => command(game, p.id, { type: 'speed', value: 99 }), /Geschwindigkeit/);
  command(game, p.id, { type: 'build', ship: 'scout', systemId: 's0' });
  command(game, p.id, { type: 'build', ship: 'corvette', systemId: 's0' });
  command(game, p.id, { type: 'pause' });
  advance(game, 30);
  assert.equal(p.queue[0].remaining, 12);
  command(game, p.id, { type: 'pause' });
  advance(game, 13);
  assert.equal(p.queue.length, 1);
  assert.equal(game.fleets.filter((f) => f.owner === p.id).length, 4);
  advance(game, 15);
  assert.equal(p.queue.length, 0);
  assert.equal(game.fleets.filter((f) => f.owner === p.id).length, 5);
});
test('combat destroys hostile defense and equal fleets exchange simultaneous damage', () => {
  const { game, p } = setup();
  const enemy = addPlayer(game, 'p2', 'Other');
  const f = game.fleets.find((f) => f.owner === p.id && f.type === 'corvette')!;
  f.systemId = 's10';
  advance(game, 15);
  assert.equal(game.systems.find((s) => s.id === 's10')!.defense, 0);
  assert.ok(f.hp > 0);
  const e = game.fleets.find((f) => f.owner === enemy.id && f.type === 'corvette')!;
  e.systemId = 's6';
  f.systemId = 's6';
  f.hp = 100;
  e.hp = 100;
  advance(game, 12);
  assert.ok(!game.fleets.find((other) => other.id === e.id));
  assert.ok(!game.fleets.find((other) => other.id === f.id));
});
test('views hide other resources, private events and remote enemy fleets', () => {
  const { game, p } = setup();
  addPlayer(game, 'p2', 'Other');
  const view = viewFor(game, p.id);
  assert.ok(!('resources' in view.players[1]));
  assert.ok(view.fleets.every((f) => f.owner === p.id));
  assert.ok(view.log.every((l) => !l.playerId || l.playerId === p.id));
  assert.deepEqual(view.systems.find((s) => s.id === 's21')!.resources, {
    energy: 0,
    minerals: 0,
    data: 0,
  });
  assert.equal(view.me.resources.energy, p.resources.energy);
});
test('race to colonize the same system refunds the losing colony action', () => {
  const { game, p } = setup();
  const other = addPlayer(game, 'p2', 'Other');
  for (const player of [p, other]) {
    player.surveyed.push('s1');
    const fleet = game.fleets.find((f) => f.owner === player.id && f.type === 'colony')!;
    fleet.systemId = 's1';
    command(game, player.id, { type: 'colonize', fleetId: fleet.id });
  }
  const before = other.resources.minerals;
  advance(game, 13);
  assert.equal(game.systems.find((s) => s.id === 's1')!.owner, p.id);
  assert.ok(other.resources.minerals >= before + 80);
  assert.ok(game.fleets.some((f) => f.owner === other.id && f.type === 'colony'));
});
test('eight colonies produce a winner and freeze the finished simulation', () => {
  const { game, p } = setup();
  for (const s of game.systems.slice(0, 8)) s.owner = p.id;
  tickGame(game, 1);
  assert.equal(game.winner, p.id);
  const time = game.tick;
  tickGame(game, 1);
  assert.equal(game.tick, time);
  assert.throws(() => command(game, p.id, { type: 'pause' }), /beendet/);
});
