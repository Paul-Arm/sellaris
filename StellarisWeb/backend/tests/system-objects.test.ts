import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { build } from 'esbuild';
import { cli } from '../tool.mjs';
import { adminToken } from '../admin';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { SystemSubscription } from '../system-subscription';
import { addPlayer, createGame } from '../../shared/game';
import { generateSystemBodies } from '../../shared/systemGeneration';
import { objectBodies } from '../../shared/systemObjects';

async function until(check: () => boolean) {
  const end = Date.now() + 30000;
  while (!check()) {
    assert(Date.now() < end, 'object subscription timed out');
    await delay(40);
  }
}
test(
  'persistent objects: two clients, scopes, ownership, revisions, lifecycle and reconnect',
  { timeout: 120000 },
  async () => {
    await build({
      entryPoints: ['spacetimedb/test-fixtures/object-module.ts'],
      outfile: 'artifacts/object-test-module.js',
      bundle: true,
      platform: 'neutral',
      format: 'esm',
      conditions: ['module'],
      external: ['spacetime:*'],
    });
    const database = `singularity-game-objects-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'artifacts/object-test-module.js',
      '--yes=skip-login',
    ]);
    const source = createGame('ABC123');
    source.paused = true;
    const pa = addPlayer(source, 'a', 'Architect');
    addPlayer(source, 'b', 'Visitor');
    pa.resources = { energy: 2000, minerals: 2000, science: 1000 };
    const clients: Client[] = [];
    const admin = await connect(database, { token: adminToken() });
    clients.push(admin);
    try {
      await admin.conn.reducers.initializeGame({
        code: source.code,
        seed: 42,
        sourceJson: JSON.stringify(source),
        migrationKey: 'objects',
      });
      for (const id of ['a', 'b']) {
        const c = await connect(database);
        clients.push(c);
        const ticket = randomBytes(32).toString('hex');
        await admin.conn.reducers.reserveGameSeat({ ticket, externalId: id, templateJson: '' });
        await c.conn.reducers.redeemGameSeat({ ticket });
        await subscribe(c.conn, GAME_QUERIES);
      }
      const [, a, b] = clients;
      const home = [...a.conn.db.myGamePlayer.iter()][0].homeId;
      const other = [...b.conn.db.myGamePlayer.iter()][0].homeId;
      assert.equal(a.conn.db.focusedSystemObjects.count(), 0n, 'galaxy subscribes to no object details');
      const sa = new SystemSubscription(a),
        sb = new SystemSubscription(b);
      await sa.focus(home);
      await sb.focus(home);
      const rows = () => [...a.conn.db.focusedSystemObjects.iter()];
      assert.equal(rows().length, 9);
      assert.deepEqual(
        objectBodies(rows()).map(({ objectId, revision, ...body }) => body),
        generateSystemBodies(source.systems.find((s) => s.id === pa.home)!),
      );
      assert.equal([...a.conn.db.focusedObjectSystems.iter()][0].mainObjectId, `${home}:1`);
      await a.conn.reducers.gameCommand({
        commandJson: JSON.stringify({ type: 'site_build', systemId: pa.home, bodySlot: 4, facility: 'mine' }),
      });
      const id = `${home}:2`;
      await assert.rejects(
        b.conn.reducers.renameBody({ objectId: id, revision: 1, name: 'Stolen' }),
        /eigene/,
      );

      await assert.rejects(a.conn.reducers.renameBody({ objectId: id, revision: 1, name: '  ' }), /Zeichen/);
      await a.conn.reducers.renameBody({ objectId: id, revision: 1, name: '  Hoffnung  ' });
      await until(() =>
        [...b.conn.db.focusedSystemObjects.iter()].some((r) => r.id === id && r.revision === 2),
      );
      assert.equal(objectBodies(rows()).find((r) => r.slot === 2)!.name, 'Hoffnung');
      await assert.rejects(
        a.conn.reducers.renameBody({ objectId: id, revision: 1, name: 'stale' }),
        /zwischenzeitlich/,
      );
      await a.conn.reducers.gameCommand({
        commandJson: JSON.stringify({
          type: 'site_build',
          systemId: pa.home,
          bodySlot: 2,
          facility: 'habitat',
        }),
      });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(a)!.sites!.some((s) => s.bodySlot === 2));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const site = gameView(a)!.sites!.find((s) => s.bodySlot === 2)!;
      assert.equal(site.id, id, 'existing site ID is the stable body reference');
      const fixture = (removeId = '', revision = 0) =>
        cli([
          'call',
          database,
          'fixture_object',
          String(home),
          removeId,
          String(revision),
          '--server',
          'http://127.0.0.1:3100',
        ]);
      fixture();
      await until(() => rows().length === 10 && b.conn.db.focusedSystemObjects.count() === 10n);
      const added = rows().find((r) => r.slot === 9)!;
      await a.conn.reducers.renameBody({ objectId: added.id, revision: 1, name: 'Neuer Mond' });
      await until(() =>
        [...b.conn.db.focusedSystemObjects.iter()].some((r) => r.id === added.id && r.revision === 2),
      );
      assert.throws(() => fixture(id, 2), /Abhängige/, 'active facility blocks removal');
      assert.throws(() => fixture(`${home}:1`, 1), /Abhängige/, 'colony and moons block removal');
      fixture(added.id, 2);
      await until(() =>
        [...b.conn.db.focusedSystemObjects.iter()].some((r) => r.id === added.id && r.state === 'removed'),
      );
      await assert.rejects(
        a.conn.reducers.gameCommand({
          commandJson: JSON.stringify({
            type: 'site_build',
            systemId: pa.home,
            bodySlot: 9,
            facility: 'mine',
          }),
        }),
      );

      fixture();
      await until(() => rows().some((r) => r.slot === 10));
      await a.conn.reducers.gameCommand({
        commandJson: JSON.stringify({
          type: 'site_build',
          systemId: pa.home,
          bodySlot: 10,
          facility: 'mine',
        }),
      });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(a)!.sites!.some((s) => s.bodySlot === 10));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert(
        gameView(a)!.sites!.some((s) => s.bodySlot === 10),
        'build validation accepts persisted slots beyond legacy range',
      );
      assert.equal(rows().find((r) => r.slot === 9)!.state, 'removed', 'slots are never reused');
      const token = a.token;
      await sa.focus(0);
      a.conn.disconnect();
      const resumed = await connect(database, { token });
      clients.push(resumed);
      await subscribe(resumed.conn, GAME_QUERIES);
      await new SystemSubscription(resumed).focus(home);
      assert.equal(
        objectBodies(resumed.conn.db.focusedSystemObjects.iter()).find((r) => r.slot === 2)!.name,
        'Hoffnung',
      );
      assert([...resumed.conn.db.focusedSystemObjects.iter()].some((r) => r.state === 'removed'));
      await sb.focus(other);
      assert([...b.conn.db.focusedSystemObjects.iter()].every((r) => r.systemId === other));
      cli(['call', database, 'fixture_empty', String(other), '--server', 'http://127.0.0.1:3100']);
      await until(() => b.conn.db.focusedSystemObjects.count() === 0n);

      assert.equal(b.conn.db.focusedSystemObjects.count(), 0n, 'marked empty systems are not regenerated');
      assert.equal(b.conn.db.focusedObjectSystems.count(), 1n);
      await sb.focus(0);
      assert.equal(b.conn.db.focusedSystemObjects.count(), 0n);
    } finally {
      for (const c of clients) c.conn.disconnect();
    }
  },
);
