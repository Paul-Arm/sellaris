import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { adminToken } from '../admin';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { addPlayer, createGame, type GameCommand } from '../../shared/game';

test(
  'starbases: two clients, territory before colonies, modules, shipyard, revisions, pause and reconnect',
  { timeout: 120000 },
  async () => {
    const database = `singularity-game-starbases-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const game = createGame('BA5E01'),
      p = addPlayer(game, 'a', 'Builder'),
      other = addPlayer(game, 'b', 'Rival');
    game.paused = true;
    p.resources = { energy: 10000, minerals: 10000, data: 1000 };
    const system = game.systems.find((s) => !s.owner && s.kind === 'star' && !s.defense)!;
    p.surveyed.push(system.id);
    other.surveyed.push(system.id);
    const colonist = game.fleets.find((f) => f.owner === p.id && f.type === 'colony')!;
    colonist.systemId = system.id;
    const clients: Client[] = [],
      admin = await connect(database, { token: adminToken() });
    clients.push(admin);
    async function until(check: () => boolean) {
      const end = Date.now() + 35000;
      while (!check()) {
        assert(Date.now() < end, 'starbase state timed out');
        await delay(60);
      }
    }
    const issue = async (c: Client, cmd: GameCommand) => {
      await delay(75);
      await c.conn.reducers.gameCommand({ commandJson: JSON.stringify(cmd) });
    };
    try {
      await admin.conn.reducers.initializeGame({
        code: game.code,
        sourceJson: JSON.stringify(game),
        seed: 42,
        creationKey: database,
      });
      for (const id of [p.id, other.id]) {
        const c = await connect(database);
        clients.push(c);
        const ticket = randomBytes(32).toString('hex');
        await admin.conn.reducers.reserveGameSeat({ ticket, externalId: id, templateJson: '' });
        await c.conn.reducers.redeemGameSeat({ ticket });
        await subscribe(c.conn, GAME_QUERIES);
      }
      const [, a, b] = clients,
        view = () => gameView(a)!,
        current = () => view().systems.find((s) => s.id === system.id)!;
      await issue(a, { type: 'starbase_build', systemId: system.id });
      await until(() => !!current().starbase?.project);
      assert.equal(current().owner, null);
      assert.equal(view().me.resources.minerals, 9850);
      await assert.rejects(issue(b, { type: 'starbase_build', systemId: system.id }));
      await assert.rejects(
        issue(b, { type: 'starbase_cancel', systemId: system.id, revision: current().starbase!.revision }),
      );
      assert.equal(gameView(b)!.systems.find((s) => s.id === system.id)!.starbase, null);
      await assert.rejects(issue(a, { type: 'colonize', fleetId: colonist.id }));
      const paused = view().tick;
      await delay(350);
      assert.equal(view().tick, paused);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => current().owner === p.id);
      assert.equal(current().colony, null);
      assert.equal(current().starbase!.level, 1);
      await assert.rejects(issue(a, { type: 'build', systemId: system.id, ship: 'scout' }));
      await issue(a, { type: 'colonize', fleetId: colonist.id });
      await until(() => !!current().colony);
      await issue(a, {
        type: 'starbase_upgrade',
        systemId: system.id,
        revision: current().starbase!.revision,
      });
      await until(() => current().starbase!.level === 2);
      const revision = current().starbase!.revision;
      await issue(a, { type: 'starbase_module', systemId: system.id, revision, slot: 1, module: 'shipyard' });
      await assert.rejects(issue(a, { type: 'starbase_cancel', systemId: system.id, revision }));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const joined = await connect(database, { token: a.token });
      clients.push(joined);
      await subscribe(joined.conn, GAME_QUERIES);
      assert.deepEqual(
        gameView(joined)!.systems.find((s) => s.id === system.id)!.starbase,
        current().starbase,
      );
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => current().starbase!.modules.length === 1);
      assert.equal(current().starbase!.modules[0].slot, 1);
      await issue(a, { type: 'build', systemId: system.id, ship: 'scout' });
      await until(() =>
        view().fleets.some((f) => f.owner === p.id && f.type === 'scout' && f.systemId === system.id),
      );
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      await issue(a, {
        type: 'starbase_module',
        systemId: system.id,
        revision: current().starbase!.revision,
        slot: 0,
        module: 'battery',
      });
      const cash = view().me.resources.minerals,
        rev = current().starbase!.revision;
      await issue(a, { type: 'starbase_cancel', systemId: system.id, revision: rev });
      assert.equal(view().me.resources.minerals, cash + 70);
      await assert.rejects(issue(a, { type: 'starbase_cancel', systemId: system.id, revision: rev }));
      assert.equal(current().starbase!.modules.length, 1);
    } finally {
      await admin.conn.reducers.setClock({ paused: true, speed: 1 });
      for (const c of clients) c.conn.disconnect();
    }
  },
);
