import { SCENARIOS } from '../domain';
import { gameDay } from '../../shared/time';
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { seedDatabase, adminToken } from '../admin';
import { connect, subscribe, join, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { addPlayer, createGame, income } from '../../shared/game';
import { RESOURCE_IDS } from '../../shared/resources';

test(
  'native monthly economy: immediate actions, private balanced ledger, one payout, growth and durable reconnect',
  { timeout: 60000 },
  async () => {
    const database = `singularity-game-economy-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const source = createGame('EC0101'),
      player = addPlayer(source, 'economy', 'Economy');
    source.paused = true;
    source.tick = 28;
    player.resources = { energy: 1000, minerals: 1000, data: 1000 };
    player.empire!.economyModifiers = [
      { id: 'production', name: 'Produktionsbonus', category: 'jobs', resource: 'energy', percent: 0.25 },
    ];
    const clients: Client[] = [];
    try {
      const admin = await connect(database, { token: adminToken() });
      clients.push(admin);
      await admin.conn.reducers.initializeGame({
        code: source.code,
        seed: 42,
        sourceJson: JSON.stringify(source),
        creationKey: 'monthly-economy',
      });
      const client = await connect(database);
      clients.push(client);
      const ticket = randomBytes(32).toString('hex');
      await admin.conn.reducers.reserveGameSeat({ ticket, externalId: player.id, templateJson: '' });
      await client.conn.reducers.redeemGameSeat({ ticket });
      await subscribe(client.conn, GAME_QUERIES);
      const view = () => gameView(client)!;
      const start = view(),
        before = { ...start.me.resources },
        population = start.systems.find((s) => s.owner === player.id)!.colony!.population;
      await client.conn.reducers.gameCommand({
        commandJson: JSON.stringify({ type: 'research', tech: 'computing' }),
      });
      assert.equal(view().me.resources.data, before.data - 50);
      assert.equal(view().me.research.projects[0].done, 0);
      const forecast = income(view(), view().me);
      const stock = { ...view().me.resources };
      await admin.conn.reducers.setClock({ paused: false, speed: 1 });
      const until = async (check: () => boolean) => {
        const end = Date.now() + 20000;
        while (!check()) {
          assert(Date.now() < end, 'monthly economy timed out');
          await delay(40);
        }
      };
      await until(() => view().tick >= 29);
      assert.deepEqual(view().me.resources, stock, 'no daily income');
      await until(() => view().tick >= 31 && view().me.research.projects[0].done > 0);
      await admin.conn.reducers.setClock({ paused: true, speed: 1 });
      for (const resource of RESOURCE_IDS)
        assert(
          Math.abs(view().me.resources[resource] - stock[resource] - forecast[resource]) < 1e-7,
          `exact monthly ${resource} balance`,
        );
      assert(view().systems.find((s) => s.owner === player.id)!.colony!.population > population);
      const closed = { ...view().me.resources };
      for (const percent of [0, 50, 100])
        await client.conn.reducers.gameCommand({
          commandJson: JSON.stringify({ type: 'compute_allocation', use: 'synthesis', percent }),
        });
      assert.deepEqual(view().me.resources, closed, 'commands do not duplicate the monthly payout');
      const reconnect = await connect(database, { token: client.token });
      clients.push(reconnect);
      await subscribe(reconnect.conn, GAME_QUERIES);
      assert.deepEqual(gameView(reconnect)!.me.resources, closed);
      const anonymous = await connect(database);
      clients.push(anonymous);
      await subscribe(anonymous.conn, ['SELECT * FROM my_empire']);
      assert.equal(anonymous.conn.db.myEmpire.count(), 0n);
    } finally {
      for (const client of clients) client.conn.disconnect();
      cli(['delete', database, '--server', 'http://127.0.0.1:3100', '--yes']);
    }
  },
);

test(
  'lab simulation uses the same monthly boundary and catalog resource rows',
  { timeout: 30000 },
  async () => {
    const database = `singularity-test-monthly-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const clients: Client[] = [];
    try {
      await seedDatabase(database, { ...SCENARIOS.smoke, battleCount: 0 });
      const admin = await connect(database, { token: adminToken() });
      clients.push(admin);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const client = await connect(database);
      clients.push(client);
      await join(client, 1);
      const stock = { ...[...client.conn.db.myEmpire.iter()][0] };
      const colonies = [...client.conn.db.myColonies.iter()];
      const trade = [...client.conn.db.myTrade.iter()];
      const production = Object.fromEntries(
        RESOURCE_IDS.map((r) => [
          r,
          colonies.reduce((n, c) => n + c.monthlyProduction[r], 0) +
            (r === 'energy' ? trade.reduce((n, t) => n + t.monthlyEnergy, 0) : 0),
        ]),
      );
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      const until = async (check: () => boolean) => {
        const deadline = Date.now() + 15000;
        while (!check()) {
          assert(Date.now() < deadline, 'monthly simulation deadline');
          await delay(40);
        }
      };
      await until(() => gameDay(client.clock.now()) >= 15);
      for (const r of RESOURCE_IDS) assert.equal([...client.conn.db.myEmpire.iter()][0][r], stock[r]);
      await until(() => [...client.conn.db.myColonies.iter()].every((c) => c.lastProducedAt === 30));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const closing = [...client.conn.db.myEmpire.iter()][0];
      for (const r of RESOURCE_IDS)
        assert.equal(closing[r], stock[r] + production[r] * stock.productionModifier);
      await delay(1100);
      for (const r of RESOURCE_IDS) assert.equal([...client.conn.db.myEmpire.iter()][0][r], closing[r]);
    } finally {
      for (const c of clients) c.conn.disconnect();
      cli(['delete', database, '--server', 'http://127.0.0.1:3100', '--yes']);
    }
  },
);
