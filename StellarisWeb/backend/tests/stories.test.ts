import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { adminToken } from '../admin';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { addPlayer, createGame, type GameCommand, type GameState } from '../../shared/game';
import { baseIncome, colonyProduction } from '../../shared/colonies';
import { snapshotTemplate, starterLibrary } from '../../shared/empires';

const issue = async (client: Client, cmd: GameCommand) => {
  await delay(65);
  return client.conn.reducers.gameCommand({ commandJson: JSON.stringify(cmd) });
};
async function until(check: () => boolean, timeout = 12000) {
  const deadline = Date.now() + timeout;
  while (!check()) {
    assert(Date.now() < deadline, 'story state timed out');
    await delay(65);
  }
}
const funds = (c: Client) => ({ ...gameView(c)!.me.resources });
async function fixture(configure: (game: GameState) => void) {
  const database = `singularity-game-stories-${Date.now()}`;
  cli([
    'publish',
    database,
    '--server',
    'http://127.0.0.1:3100',
    '--js-path',
    'spacetimedb/dist/bundle.js',
    '--yes=skip-login',
  ]);
  const source = createGame('FABB12');
  source.paused = true;
  for (const id of ['a', 'b']) {
    const p = addPlayer(source, id, id);
    p.resources = { energy: 1000, minerals: 1000, science: 1000 };
  }
  configure(source);
  const admin = await connect(database, { token: adminToken() }),
    clients = [admin];
  try {
    await admin.conn.reducers.initializeGame({
      code: source.code,
      sourceJson: JSON.stringify(source),
      seed: 42,
      migrationKey: 'stories',
    });
    for (const id of ['a', 'b']) {
      const client = await connect(database);
      clients.push(client);
      const ticket = randomBytes(32).toString('hex');
      await admin.conn.reducers.reserveGameSeat({ ticket, externalId: id, templateJson: '' });
      await client.conn.reducers.redeemGameSeat({ ticket });
      await subscribe(client.conn, GAME_QUERIES);
    }
    return {
      source,
      database,
      admin,
      clients,
      a: clients[1],
      b: clients[2],
      close: async () => {
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
  'discoveries create private, durable decisions with atomic costs and one-time outcomes',
  { timeout: 18000 },
  async () => {
    const f = await fixture((g) => {
      g.players[0].resources.energy = 0;
      const anomaly = g.systems.find((s) => s.anomaly && s.kind === 'star')!;
      anomaly.defense = 0;
      for (const fleet of g.fleets.filter((s) => s.type === 'scout')) {
        fleet.systemId = anomaly.id;
        fleet.task = { type: 'scan', remaining: 0.01, total: 8 };
      }
      const colony = g.fleets.find((s) => s.owner === 'a' && s.type === 'colony')!;
      colony.systemId = 's1';
      colony.task = { type: 'colonize', remaining: 0.01, total: 12 };
    });
    const { a, b, admin } = f;
    try {
      const originalCrisis = gameView(a)!.crises;
      await admin.conn.reducers.initializeStories({});
      assert.deepEqual(gameView(a)!.crises, originalCrisis, 'bootstrap does not restart its countdown');
      await assert.rejects(a.conn.reducers.initializeStories({}));
      await admin.conn.reducers.setClock({ paused: false, speed: 1 });
      await until(() => gameView(a)!.decisions!.length === 2);
      await admin.conn.reducers.setClock({ paused: true, speed: 1 });
      assert.equal(gameView(b)!.decisions!.length, 0, 'only the first discovery receives an archive');
      const archive = gameView(a)!.decisions!.find((d) => d.kind === 'archive_v1')!;
      const frontier = gameView(a)!.decisions!.find((d) => d.kind === 'frontier_v1')!;
      const before = funds(a);
      await assert.rejects(issue(b, { type: 'resolve_decision', decisionId: archive.id, choice: 'salvage' }));
      await assert.rejects(
        issue(a, { type: 'resolve_decision', decisionId: archive.id, choice: 'invented' }),
      );
      await assert.rejects(
        issue(a, { type: 'resolve_decision', decisionId: archive.id, choice: 'decode' }),
        'insufficient energy',
      );
      assert.deepEqual(funds(a), before);
      await delay(150);
      assert.deepEqual(
        gameView(a)!.decisions!.find((d) => d.id === archive.id),
        archive,
        'pause retains deadline and state',
      );
      const restored = await connect(f.database, { token: a.token });
      f.clients.push(restored);
      await subscribe(restored.conn, GAME_QUERIES);
      assert.deepEqual(gameView(restored)!.decisions, gameView(a)!.decisions);
      await issue(restored, { type: 'resolve_decision', decisionId: frontier.id, choice: 'restore' });
      await issue(restored, { type: 'resolve_decision', decisionId: archive.id, choice: 'decode' });
      await until(() => gameView(a)!.decisions!.every((d) => d.phase === 'resolved'));
      assert.deepEqual(funds(a), {
        energy: before.energy + 110 - 40,
        minerals: before.minerals - 40,
        science: before.science + 100,
      });
      const final = funds(a);
      await assert.rejects(issue(a, { type: 'resolve_decision', decisionId: archive.id, choice: 'salvage' }));
      assert.deepEqual(funds(a), final);
      assert.equal(a.conn.db.battleMotion.count(), 0n);
      const intruder = await connect(f.database);
      f.clients.push(intruder);
      await assert.rejects(subscribe(intruder.conn, ['SELECT * FROM game_story']));
    } finally {
      await f.close();
    }
  },
);

test(
  'crisis phases reduce real production; shielding, hot join, expiry and cooperative containment are persistent',
  { timeout: 90000 },
  async () => {
    const f = await fixture((g) => {
      const fleet = g.fleets.find((s) => s.owner === 'a' && s.type === 'scout')!;
      fleet.systemId = g.systems.find((s) => s.kind === 'rift')!.id;
      fleet.task = { type: 'scan', remaining: 0.01, total: 8 };
    });
    const { a, b, admin } = f;
    try {
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(a)!.crises![0].phase === 'warning');
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const crisis = gameView(a)!.crises![0];
      assert.equal(crisis.target, 4);
      assert.equal(gameView(a)!.decisions!.filter((d) => d.phase === 'pending').length, 1);
      assert.equal(gameView(b)!.decisions!.filter((d) => d.phase === 'pending').length, 1);
      const response = gameView(a)!.decisions![0];
      const beforeShield = funds(a);
      await issue(a, { type: 'resolve_decision', decisionId: response.id, choice: 'shield' });
      assert.equal(funds(a).energy, beforeShield.energy - 120);
      assert(gameView(a)!.crises![0].shielded);
      assert(!gameView(b)!.crises![0].shielded, 'shield is private and applies only to its owner');
      assert.equal(b.conn.db.myCrisisPledges.count(), 0n);
      await assert.rejects(issue(a, { type: 'crisis_action', crisisId: 1, action: 'shield' }));
      await issue(b, { type: 'crisis_action', crisisId: 1, action: 'contribute' });
      await until(() => gameView(a)!.crises![0].progress === 1);
      assert.equal(gameView(a)!.crises![0].contributions, 0);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(a)!.crises![0].phase === 'active', 34000);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const av = gameView(a)!,
        bv = gameView(b)!;
      assert.equal(av.systems.find((s) => s.id === av.me.home)!.productionFactor, 1);
      assert.equal(bv.systems.find((s) => s.id === bv.me.home)!.productionFactor, 0.75);
      assert.equal(bv.decisions![0].phase, 'expired', 'unanswered crisis chooses its safe fallback');
      const bColony = [...b.conn.db.myColonies.iter()][0],
        rate = colonyProduction(
          bv.systems.find((s) => s.id === bv.me.home)!,
          bv.me,
        );
      assert.equal(bColony.energyRate, rate.energy, 'UI and authoritative colony rate agree');
      await issue(b, { type: 'colony_focus', systemId: bv.me.home, focus: 'balanced' });
      const start = gameView(b)!.tick,
        balance = funds(b),
        anchors = [...b.conn.db.myColonies.iter()];
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(b)!.tick > start + 8);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      await issue(b, { type: 'colony_focus', systemId: bv.me.home, focus: 'balanced' });
      const end = gameView(b)!.tick,
        base = baseIncome(gameView(b)!.me),
        updated = [...b.conn.db.myColonies.iter()];
      const expected =
        balance.energy +
        base.energy * (Math.floor(end / 4) - Math.floor(start / 4)) +
        anchors.reduce(
          (n, c) =>
            n + c.energyRate * ((updated.find((u) => u.id === c.id)!.lastProducedAt - c.lastProducedAt) / 4),
          0,
        );
      assert(Math.abs(funds(b).energy - expected) < 1e-6, 'credited resources actually use the reduced rate');
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(b)!.crises![0].phase === 'surge', 34000);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.equal(gameView(b)!.systems.find((s) => s.id === bv.me.home)!.productionFactor, 0.5);
      assert.equal(gameView(a)!.systems.find((s) => s.id === av.me.home)!.productionFactor, 1);
      const newcomer = await connect(f.database);
      f.clients.push(newcomer);
      const ticket = randomBytes(32).toString('hex'),
        lib = starterLibrary();
      await admin.conn.reducers.reserveGameSeat({
        ticket,
        externalId: 'late',
        templateJson: JSON.stringify(snapshotTemplate(lib, lib.empires[0].id)),
      });
      await newcomer.conn.reducers.redeemGameSeat({ ticket });
      await subscribe(newcomer.conn, GAME_QUERIES);
      assert.equal(gameView(newcomer)!.crises![0].target, 4, 'late join cannot increase the agreed target');
      assert.equal(gameView(newcomer)!.decisions![0].phase, 'pending');
      assert.equal(
        [...newcomer.conn.db.myColonies.iter()][0].energyRate,
        colonyProduction(
          gameView(newcomer)!.systems.find((s) => s.id === gameView(newcomer)!.me.home)!,
          gameView(newcomer)!.me,
        ).energy,
      );
      await issue(a, { type: 'colony_focus', systemId: av.me.home, focus: 'balanced' });
      await issue(b, { type: 'colony_focus', systemId: bv.me.home, focus: 'balanced' });
      const aBefore = funds(a),
        bBefore = funds(b);
      await issue(a, { type: 'crisis_action', crisisId: 1, action: 'contribute' });
      await issue(a, { type: 'crisis_action', crisisId: 1, action: 'contribute' });
      await issue(b, { type: 'crisis_action', crisisId: 1, action: 'contribute' });
      await until(() => gameView(a)!.crises![0].phase === 'contained');
      await until(() => gameView(newcomer)!.decisions![0].outcome === 'contained');
      assert.equal(funds(a).science, aBefore.science - 60 + 80);
      assert.equal(funds(b).science, bBefore.science - 30 + 80, 'reward includes its earlier contribution');
      assert.equal(gameView(newcomer)!.decisions![0].outcome, 'contained');
      assert.equal(gameView(b)!.systems.find((s) => s.id === bv.me.home)!.productionFactor, 1);
      assert.equal([...b.conn.db.myColonies.iter()][0].energyRate, rate.energy / 0.75);
      const paid = funds(a);
      await assert.rejects(issue(a, { type: 'crisis_action', crisisId: 1, action: 'contribute' }));
      await admin.conn.reducers.initializeStories({});
      assert.equal(gameView(a)!.crises![0].phase, 'contained');
      assert.deepEqual(funds(a), paid, 'containment rewards cannot replay');
    } finally {
      await f.close();
    }
  },
);
