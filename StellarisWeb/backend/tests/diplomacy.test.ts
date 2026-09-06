import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { adminToken } from '../admin';
import { createGame, addPlayer, type GameCommand, type GameState } from '../../shared/game';
import { BattleDetailSubscription } from '../detail-subscriptions';

const issue = async (c: Client, command: GameCommand) => {
  await delay(60);
  return c.conn.reducers.gameCommand({ commandJson: JSON.stringify(command) });
};
const funds = (c: Client) => ({ ...gameView(c)!.me.resources });
const offer = (c: Client) => gameView(c)!.offers!.sort((a, b) => b.id - a.id)[0];
const zero = { energy: 0, minerals: 0, science: 0 };
async function until(check: () => boolean, timeout = 10000) {
  const deadline = Date.now() + timeout;
  while (!check()) {
    assert(Date.now() < deadline, 'diplomacy state timed out');
    await delay(60);
  }
}
async function fixture(configure?: (game: GameState) => void) {
  const database = `singularity-game-diplomacy-${Date.now()}`;
  cli([
    'publish',
    database,
    '--server',
    'http://127.0.0.1:3100',
    '--js-path',
    'spacetimedb/dist/bundle.js',
    '--yes=skip-login',
  ]);
  const game = createGame('DD1122');
  game.paused = true;
  for (const id of ['a', 'b', 'c']) addPlayer(game, id, id);
  configure?.(game);
  const admin = await connect(database, { token: adminToken() });
  const clients = [admin];
  try {
    await admin.conn.reducers.initializeGame({
      code: game.code,
      seed: 1,
      sourceJson: JSON.stringify(game),
      migrationKey: 'diplomacy-tests',
    });
    for (const id of ['a', 'b', 'c']) {
      const client = await connect(database);
      clients.push(client);
      const ticket = randomBytes(32).toString('hex');
      await admin.conn.reducers.reserveGameSeat({ ticket, externalId: id, templateJson: '' });
      await client.conn.reducers.redeemGameSeat({ ticket });
      await subscribe(client.conn, GAME_QUERIES);
    }
    return {
      game,
      admin,
      a: clients[1],
      b: clients[2],
      c: clients[3],
      clients,
      database,
      cleanup: async () => {
        await admin.conn.reducers.setClock({ paused: true, speed: 1 });
        clients.forEach((c) => c.conn.disconnect());
      },
    };
  } catch (e) {
    clients.forEach((c) => c.conn.disconnect());
    throw e;
  }
}

test(
  'private escrow trades validate authority, affordability, replay and reconnect',
  { timeout: 25000 },
  async () => {
    const f = await fixture(),
      { a, b, c } = f;
    try {
      const startA = funds(a),
        startB = funds(b);
      const trade: GameCommand = {
        type: 'offer_treaty',
        empireId: 'b',
        kind: 'trade',
        give: { ...zero, energy: 50 },
        receive: { ...zero, minerals: 40 },
      };
      for (const energy of [-1, 1.5, 10001, NaN, startA.energy + 1])
        await assert.rejects(issue(a, { ...trade, give: { ...zero, energy } }));
      await assert.rejects(issue(a, { ...trade, empireId: 'a' }));
      assert.deepEqual(funds(a), startA);
      await issue(a, trade);
      const id = offer(a).id;
      assert.equal(funds(a).energy, startA.energy - 50);
      assert.deepEqual(funds(b), startB);
      await until(() => !!offer(b));
      assert.equal(gameView(c)!.offers!.length, 0);
      assert.equal(c.conn.db.myGameOffers.count(), 0n);
      await assert.rejects(issue(a, trade), 'no duplicate pending pair');
      await assert.rejects(issue(a, { type: 'respond_treaty', treatyId: id, accept: true }));
      await assert.rejects(issue(c, { type: 'respond_treaty', treatyId: id, accept: true }));
      await assert.rejects(issue(b, { type: 'cancel_treaty', treatyId: id }));
      const pending = offer(b);
      b.conn.disconnect();
      const resumed = await connect(f.database, { token: b.token });
      f.clients.push(resumed);
      await subscribe(resumed.conn, GAME_QUERIES);
      assert.deepEqual(offer(resumed), pending);
      assert.deepEqual(funds(resumed), startB);
      await issue(resumed, { type: 'respond_treaty', treatyId: id, accept: true });
      await until(() => offer(a).status === 'accepted');
      assert.deepEqual(funds(a), { ...startA, energy: startA.energy - 50, minerals: startA.minerals + 40 });
      assert.deepEqual(funds(resumed), {
        ...startB,
        energy: startB.energy + 50,
        minerals: startB.minerals - 40,
      });
      const settled = funds(resumed);
      await assert.rejects(issue(resumed, { type: 'respond_treaty', treatyId: id, accept: true }));
      assert.deepEqual(funds(resumed), settled);

      const before = funds(a);
      await issue(a, { ...trade, receive: { ...zero, minerals: 10000 } });
      const impossible = offer(a).id;
      await assert.rejects(issue(resumed, { type: 'respond_treaty', treatyId: impossible, accept: true }));
      assert.equal(offer(resumed).status, 'pending');
      assert.deepEqual(funds(resumed), settled);
      await issue(a, { type: 'cancel_treaty', treatyId: impossible });
      assert.deepEqual(funds(a), before);
      await assert.rejects(issue(a, { type: 'cancel_treaty', treatyId: impossible }));
      assert.deepEqual(funds(a), before);
      await issue(a, trade);
      await issue(resumed, { type: 'respond_treaty', treatyId: offer(a).id, accept: false });
      await until(() => offer(a).status === 'rejected');
      assert.deepEqual(funds(a), before);
      await issue(a, trade);
      await issue(a, { type: 'declare_war', empireId: 'b' });
      assert.deepEqual(funds(a), before, 'war refunds trade escrow');
      assert.equal(offer(a).status, 'cancelled');
      await assert.rejects(issue(a, trade));
    } finally {
      await f.cleanup();
    }
  },
);

test(
  'peaceful co-location, explicit war and accepted peace preserve survivors and stop combat',
  { timeout: 25000 },
  async () => {
    const f = await fixture((game) => {
      for (const ship of game.fleets)
        if (ship.type === 'corvette' && ship.owner !== 'c') ship.systemId = 's0';
      game.fleets.find((s) => s.owner === 'b' && s.type === 'scout')!.systemId = 's0';
    });
    const { a, b, c, admin } = f;
    const scope = new BattleDetailSubscription(a);
    try {
      await admin.conn.reducers.setClock({ paused: false, speed: 1 });
      const defense = gameView(a)!.systems.find((s) => s.id === 's0')!.defense;
      const scout = gameView(b)!.fleets.find((s) => s.owner === 'b' && s.type === 'scout')!;
      await issue(b, { type: 'scan', fleetId: scout.id });
      await delay(1300);
      assert.equal(a.conn.db.visibleBattleSummaries.count(), 0n, 'peaceful fleets do not fight');
      assert(
        gameView(a)!.systems.find((s) => s.id === 's0')!.defense >= defense,
        'foreign peaceful corvettes do not besiege',
      );
      assert.equal(gameView(b)!.fleets.find((s) => s.id === scout.id)!.task!.blocked, false);
      await issue(a, { type: 'declare_war', empireId: 'b' });
      await until(() => a.conn.db.visibleBattleSummaries.count() === 1n);
      const battle = [...a.conn.db.visibleBattleSummaries.iter()][0];
      await scope.focus(0, battle.id);
      await until(() => [...a.conn.db.visibleBattleSummaries.iter()][0].attacker.damageDealt > 0);
      await admin.conn.reducers.setClock({ paused: true, speed: 1 });
      await issue(a, { type: 'offer_treaty', empireId: 'b', kind: 'peace' });
      const id = offer(a).id;
      await assert.rejects(issue(c, { type: 'respond_treaty', treatyId: id, accept: true }));
      await assert.rejects(issue(a, { type: 'respond_treaty', treatyId: id, accept: true }));
      const survivors = [...a.conn.db.battleVitals.iter()].map((s) => ({ id: s.shipId, hull: s.hull }));
      const ships = gameView(a)!.fleets.reduce((n, s) => n + (s.shipCount || 0), 0);
      assert(survivors.length > 0);
      await issue(b, { type: 'respond_treaty', treatyId: id, accept: true });
      await until(() => [...a.conn.db.visibleBattleSummaries.iter()][0].state === 'finished');
      assert.equal([...a.conn.db.visibleBattleSummaries.iter()][0].winnerId, 0);
      assert.equal(a.conn.db.battleMotion.count(), 0n);
      assert(gameView(a)!.fleets.every((s) => !s.battleId));
      assert.equal(
        gameView(a)!.fleets.reduce((n, s) => n + (s.shipCount || 0), 0),
        ships,
      );
      await assert.rejects(issue(a, { type: 'declare_war', empireId: 'b' }), 'truce is enforced');
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await delay(1100);
      assert([...a.conn.db.visibleBattleSummaries.iter()].every((s) => s.state === 'finished'));
      assert.equal(gameView(b)!.fleets.find((s) => s.id === scout.id)?.task?.blocked ?? false, false);
      await scope.focus(0, 0);
    } finally {
      scope.dispose();
      await f.cleanup();
    }
  },
);

test(
  'offer deadlines use durable game time and AI answers through the same rules',
  { timeout: 30000 },
  async () => {
    const f = await fixture((g) => {
      g.players[2].ai = { startedAt: 0, nextDecision: 0 };
    });
    const { a, b, c, admin } = f;
    try {
      await issue(a, {
        type: 'offer_treaty',
        empireId: 'b',
        kind: 'trade',
        give: { ...zero, energy: 30 },
        receive: zero,
      });
      const held = funds(a),
        pending = offer(a);
      await delay(350);
      assert.deepEqual(offer(a), pending);
      assert.deepEqual(funds(a), held);
      await issue(a, {
        type: 'offer_treaty',
        empireId: 'c',
        kind: 'trade',
        give: { ...zero, energy: 24 },
        receive: { ...zero, minerals: 20 },
      });
      const fair = offer(a).id;
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(a)!.offers!.find((o) => o.id === fair)?.status === 'accepted');
      await issue(a, {
        type: 'offer_treaty',
        empireId: 'c',
        kind: 'trade',
        give: zero,
        receive: { ...zero, science: 50 },
      });
      const unfair = offer(a).id;
      await until(() => gameView(a)!.offers!.find((o) => o.id === unfair)?.status === 'rejected');
      await until(() => gameView(a)!.offers!.find((o) => o.id === pending.id)?.status === 'expired', 18000);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const refunded = funds(a);
      assert(refunded.energy >= held.energy + 30 - 24, 'expired escrow returned alongside earned production');
      await assert.rejects(issue(b, { type: 'respond_treaty', treatyId: pending.id, accept: true }));
      await assert.rejects(issue(a, { type: 'cancel_treaty', treatyId: pending.id }));
      assert.deepEqual(funds(a), refunded);
      assert.equal(c.conn.db.fleetShips.count(), 0n);
    } finally {
      await f.cleanup();
    }
  },
);
