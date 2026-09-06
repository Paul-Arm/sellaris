import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { adminToken } from '../admin';
import { addPlayer, createGame, type GameCommand } from '../../shared/game';
import { colonyEconomy, colonyProduction, districtSpec } from '../../shared/colonies';

const issue = (client: Client, cmd: GameCommand) =>
  client.conn.reducers.gameCommand({ commandJson: JSON.stringify(cmd) });
async function until(check: () => boolean) {
  const end = Date.now() + 12000;
  while (!check()) {
    assert.ok(Date.now() < end, 'colony project did not finish');
    await delay(75);
  }
}
test(
  'planetary sectors: authoritative build, upgrade, pause, jobs, cancellation, races and reconnect',
  { timeout: 30000 },
  async () => {
    const database = `singularity-colony-test-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const game = createGame('C010AB'),
      p = addPlayer(game, 'colony-owner', 'Terraner');
    game.paused = true;
    p.resources = { energy: 10000, minerals: 10000, science: 10000 };
    const admin = await connect(database, { token: adminToken() }),
      a = await connect(database),
      b = await connect(database);
    let recovered: Client | undefined;
    try {
      await admin.conn.reducers.initializeGame({
        code: game.code,
        seed: 42,
        sourceJson: JSON.stringify(game),
        migrationKey: 'colony-fixture',
      });
      const ticket = randomBytes(32).toString('hex');
      await admin.conn.reducers.reserveGameSeat({ ticket, externalId: p.id, templateJson: '' });
      await a.conn.reducers.redeemGameSeat({ ticket });
      await subscribe(a.conn, GAME_QUERIES);
      const home = () => gameView(a)!.systems.find((s) => s.id === p.home)!,
        c = () => home().colony!,
        target = () => ({ systemId: p.home, revision: c().revision });
      const original = JSON.stringify(c().sectors),
        before = { ...gameView(a)!.me.resources },
        spec = districtSpec('laboratory');
      const build = {
        type: 'colony_build' as const,
        building: 'laboratory' as const,
        sectorId: 3,
        ...target(),
      };
      await assert.rejects(issue(b, build));
      await issue(a, build);
      assert.equal(gameView(a)!.me.resources.minerals, before.minerals - spec.cost.minerals);
      await assert.rejects(issue(a, build), /zwischenzeitlich/);
      assert.equal(JSON.stringify(c().sectors), original);
      const remaining = c().construction!.remaining;
      await delay(500);
      assert.equal(c().construction!.remaining, remaining);
      recovered = await connect(database, { token: a.token });
      await subscribe(recovered.conn, GAME_QUERIES);
      assert.deepEqual(gameView(recovered)!.systems.find((s) => s.id === p.home)!.colony, c());
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => !c().construction);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const built = c().sectors[3].districts[0];
      assert.equal(built.building, 'laboratory');
      assert.equal(built.level, 1);
      const productive = colonyEconomy(c(), home().planet, gameView(a)!.me);
      assert.ok(productive.districts.find((d) => d.id === built.id)!.employed > 0);
      assert.ok(c().population > 6);
      await issue(a, { type: 'colony_toggle', districtId: built.id, enabled: false, ...target() });
      assert.equal(colonyEconomy(c()).districts.find((d) => d.id === built.id)!.jobs, 0);
      await issue(a, { type: 'colony_toggle', districtId: built.id, enabled: true, ...target() });
      const rates = [...a.conn.db.myColonies.iter()][0],
        expected = colonyProduction(home(), gameView(a)!.me);
      assert.equal(rates.energyRate, expected.energy);
      assert.equal(rates.scienceRate, expected.science);
      await issue(a, { type: 'colony_upgrade', districtId: built.id, ...target() });
      await assert.rejects(
        issue(a, { type: 'colony_demolish', districtId: built.id, ...target() }),
        /abbrechen/,
      );
      const paid = gameView(a)!.me.resources.minerals;
      await issue(a, { type: 'colony_cancel', ...target() });
      assert.equal(
        gameView(a)!.me.resources.minerals,
        paid + districtSpec('laboratory', 2).cost.minerals / 2,
      );
      await assert.rejects(issue(a, { type: 'colony_cancel', ...target() }), /Kein planetarer/);
      await issue(a, { type: 'colony_upgrade', districtId: built.id, ...target() });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => !c().construction);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.equal(c().sectors[3].districts.length, 1);
      assert.equal(c().sectors[3].districts[0].level, 2);
      const geometry = c().sectors.map(({ id, x, y, z, feature, slots }) => ({
        id,
        x,
        y,
        z,
        feature,
        slots,
      }));
      await issue(a, { type: 'colony_demolish', districtId: built.id, ...target() });
      assert.equal(c().sectors[3].districts.length, 0);
      assert.deepEqual(
        c().sectors.map(({ id, x, y, z, feature, slots }) => ({ id, x, y, z, feature, slots })),
        geometry,
      );
    } finally {
      a.conn.disconnect();
      b.conn.disconnect();
      recovered?.conn.disconnect();
      admin.conn.disconnect();
      cli(['delete', database, '--server', 'http://127.0.0.1:3100', '--yes']);
    }
  },
);
