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
import { snapshotTemplate, starterLibrary } from '../../shared/empires';
import { objectBodies } from '../../shared/systemObjects';
import { colonyProduction } from '../../shared/colonies';
import { terraformingSpec } from '../../shared/terraforming';

async function until(check: () => boolean, timeout = 35000) {
  const end = Date.now() + timeout;
  while (!check()) {
    assert(Date.now() < end, 'terraforming state timed out');
    await delay(60);
  }
}
test(
  'terraforming: research, ownership, escrow, pause, parallel projects, real climate production and system loss',
  { timeout: 55000 },
  async () => {
    await build({
      entryPoints: ['spacetimedb/test-fixtures/object-module.ts'],
      outfile: 'artifacts/terraform-test-module.js',
      bundle: true,
      platform: 'neutral',
      format: 'esm',
      conditions: ['module'],
      external: ['spacetime:*'],
    });
    const database = `singularity-game-terraform-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'artifacts/terraform-test-module.js',
      '--yes=skip-login',
    ]);
    const source = createGame('FE1234'),
      lib = starterLibrary();
    const pa = addPlayer(source, 'a', 'Terraformer', snapshotTemplate(lib, lib.empires[0].id));
    const pb = addPlayer(source, 'b', 'Visitor');
    const pc = addPlayer(source, 'c', 'Impoverished');
    pc.techs.push('terraforming');
    pc.resources = { energy: 0, minerals: 0, data: 0 };
    pa.techs.push('terraforming');
    pa.resources = { energy: 10000, minerals: 10000, data: 10000 };
    pb.resources = { energy: 0, minerals: 0, data: 0 };
    const homeSource = source.systems.find((s) => s.id === pa.home)!;
    homeSource.planet = 'Wüstenwelt';
    source.paused = true;
    const clients: Client[] = [],
      admin = await connect(database, { token: adminToken() });
    clients.push(admin);
    try {
      await admin.conn.reducers.initializeGame({
        code: source.code,
        seed: 42,
        sourceJson: JSON.stringify(source),
        migrationKey: 'terraform',
      });
      for (const id of ['a', 'b', 'c']) {
        const c = await connect(database);
        clients.push(c);
        const ticket = randomBytes(32).toString('hex');
        await admin.conn.reducers.reserveGameSeat({ ticket, externalId: id, templateJson: '' });
        await c.conn.reducers.redeemGameSeat({ ticket });
        await subscribe(c.conn, GAME_QUERIES);
      }
      const [, a, b] = clients,
        home = [...a.conn.db.myGamePlayer.iter()][0].homeId;
      const other = [...b.conn.db.myGamePlayer.iter()][0].homeId;
      const poor = clients[3],
        poorHome = [...poor.conn.db.myGamePlayer.iter()][0].homeId;
      await assert.rejects(
        poor.conn.reducers.startTerraforming({ objectId: `${poorHome}:1`, revision: 1, target: 'ocean' }),
        /Rohstoffe/,
      );
      assert.deepEqual(gameView(poor)!.me.resources, { energy: 0, minerals: 0, data: 0 });
      await new SystemSubscription(a).focus(home);
      await new SystemSubscription(b).focus(home);
      const bodies = () => objectBodies(a.conn.db.focusedSystemObjects.iter());
      const body = (slot: number) => bodies().find((b) => b.slot === slot)!;
      const start = (slot: number, target = 'continental', revision = body(slot).revision) =>
        a.conn.reducers.startTerraforming({ objectId: body(slot).objectId, revision, target });
      const funds = () => ({ ...gameView(a)!.me.resources });
      await assert.rejects(
        b.conn.reducers.startTerraforming({ objectId: `${home}:1`, revision: 1, target: 'ocean' }),
        /eigenen/,
      );
      await assert.rejects(
        b.conn.reducers.startTerraforming({ objectId: `${other}:1`, revision: 1, target: 'ocean' }),
        /Klimagestaltung/,
      );
      await assert.rejects(start(0), /Ungültiges/);
      await assert.rejects(start(2), /Ungültiges/);
      await assert.rejects(start(1, 'unknown'), /Ungültiges/);
      await assert.rejects(start(1, 'desert'), /bereits/);
      await assert.rejects(start(1, 'continental', 0), /zwischenzeitlich/);
      const initial = funds(),
        spec = terraformingSpec('desert', 'continental');
      await start(1);
      assert.deepEqual(funds(), {
        energy: initial.energy - spec.cost.energy,
        minerals: initial.minerals - spec.cost.minerals,
        data: initial.data - spec.cost.data,
      });
      assert.equal(
        b.conn.db.myTerraformProjects.count(),
        0n,
        'foreign project costs and schedule stay private',
      );
      await assert.rejects(start(1), /bereits/);
      await assert.rejects(b.conn.reducers.cancelTerraforming({ objectId: `${home}:1` }), /eigenes/);
      const paid = funds();
      await a.conn.reducers.cancelTerraforming({ objectId: `${home}:1` });
      assert.deepEqual(funds(), {
        energy: paid.energy + spec.cost.energy / 2,
        minerals: paid.minerals + spec.cost.minerals / 2,
        data: paid.data + spec.cost.data / 2,
      });
      await assert.rejects(a.conn.reducers.cancelTerraforming({ objectId: `${home}:1` }));
      await delay(1100); // start a fresh command-quota window
      await start(1);
      await start(3);
      await a.conn.reducers.gameCommand({
        commandJson: JSON.stringify({ type: 'site_build', systemId: pa.home, bodySlot: 3, facility: 'mine' }),
      });
      await a.conn.reducers.renameBody({ objectId: `${home}:3`, revision: body(3).revision, name: 'Gaia' });
      const projects = [...a.conn.db.myTerraformProjects.iter()];
      await delay(1100);
      assert.deepEqual(
        [...a.conn.db.myTerraformProjects.iter()],
        projects,
        'pause holds authoritative deadlines',
      );
      assert.equal(body(1).environment, 'desert');
      const resumed = await connect(database, { token: a.token });
      clients.push(resumed);
      await subscribe(resumed.conn, GAME_QUERIES);
      assert.deepEqual(
        [...resumed.conn.db.myTerraformProjects.iter()],
        projects,
        'reconnect restores both projects',
      );
      const before = gameView(a)!,
        beforeSystem = before.systems.find((s) => s.id === pa.home)!;
      const beforeRate = colonyProduction(beforeSystem, before.me);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => a.conn.db.myTerraformProjects.count() === 0n);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      await until(
        () =>
          objectBodies(b.conn.db.focusedSystemObjects.iter()).find((p) => p.slot === 1)?.environment ===
          'continental',
        4000,
      );
      assert.equal(body(3).name, 'Gaia', 'renaming during construction survives completion');
      assert.equal(body(3).environment, 'continental');
      const after = gameView(a)!,
        system = after.systems.find((s) => s.id === pa.home)!;
      assert.equal(system.planet, 'Kontinentalwelt');
      assert(system.colony!.population > beforeSystem.colony!.population);
      assert.deepEqual(system.colony!.sectors, beforeSystem.colony!.sectors);
      assert(
        colonyProduction(system, after.me).energy > beforeRate.energy,
        'habitability improves actual colony production',
      );
      const nativeColony = [...a.conn.db.myColonies.iter()].find((c) => c.id === home)!;
      assert(
        Math.abs(nativeColony.energyRate - colonyProduction(system, after.me).energy) < 1e-6,
        'native production rate matches climate preview',
      );
      assert(
        after.sites!.some((site) => site.bodySlot === 3 && site.level === 1),
        'parallel facility survives terraforming',
      );
      await start(1, 'arid');
      const invested = funds();
      cli(['call', database, 'fixture_lose_system', String(home), '--server', 'http://127.0.0.1:3100']);
      await until(() => a.conn.db.myTerraformProjects.count() === 0n, 4000);
      assert.deepEqual(funds(), invested, 'system loss does not refund the project');
      await assert.rejects(a.conn.reducers.cancelTerraforming({ objectId: `${home}:1` }));
    } finally {
      await admin.conn.reducers.setClock({ paused: true, speed: 1 });
      for (const c of clients) c.conn.disconnect();
    }
  },
);
