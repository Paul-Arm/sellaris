import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { adminToken } from '../admin';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { addPlayer, createGame, type GameCommand } from '../../shared/game';
import { facilitySpec } from '../../shared/celestial';

const issue = async (c: Client, cmd: GameCommand) => {
  await delay(65);
  await c.conn.reducers.gameCommand({ commandJson: JSON.stringify(cmd) });
};
async function until(predicate: () => boolean, timeout = 30000) {
  const end = Date.now() + timeout;
  while (!predicate()) {
    assert(Date.now() < end, 'installation state timed out');
    await delay(50);
  }
}
test(
  'orbital construction validates bodies and ownership, persists parallel work, credits real production and refunds once',
  { timeout: 150000 },
  async () => {
    const database = `singularity-game-sites-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const source = createGame('BABC12');
    source.paused = true;
    const pa = addPlayer(source, 'a', 'Architect'),
      pb = addPlayer(source, 'b', 'Observer');
    // Keep colony staffing constant while measuring the orbital installation ledger.
    for (const system of source.systems)
      for (const sector of system.colony?.sectors || [])
        for (const district of sector.districts)
          if (district.building === 'habitat') district.enabled = false;
    pa.resources = { energy: 3000, minerals: 3000, science: 1000 };
    pb.resources = { energy: 0, minerals: 0, science: 0 };
    const rift = source.systems.find((s) => s.kind === 'rift')!;
    pa.surveyed.push(rift.id);
    const scout = source.fleets.find((f) => f.owner === pa.id && f.type === 'scout')!;
    scout.systemId = rift.id;
    const clients: Client[] = [],
      admin = await connect(database, { token: adminToken() });
    clients.push(admin);
    try {
      await admin.conn.reducers.initializeGame({
        code: source.code,
        sourceJson: JSON.stringify(source),
        seed: 42,
        migrationKey: 'sites',
      });
      for (const id of ['a', 'b']) {
        const c = await connect(database);
        clients.push(c);
        const ticket = randomBytes(32).toString('hex');
        await admin.conn.reducers.reserveGameSeat({ ticket, externalId: id, templateJson: '' });
        await c.conn.reducers.redeemGameSeat({ ticket });
        await subscribe(c.conn, GAME_QUERIES);
      }
      const [, a, b] = clients,
        home = gameView(a)!.me.home;
      const funds = () => ({ ...gameView(a)!.me.resources });
      const initial = funds();
      await assert.rejects(
        issue(a, { type: 'mine', systemId: home }),
        'retired instant mining cannot bypass ship proximity',
      );
      await assert.rejects(issue(b, { type: 'site_build', systemId: home, bodySlot: 0, facility: 'solar' }));
      await assert.rejects(
        issue(b, { type: 'site_build', systemId: pb.home, bodySlot: 0, facility: 'solar' }),
        'insufficient resources',
      );
      await assert.rejects(issue(a, { type: 'site_build', systemId: home, bodySlot: 2, facility: 'gas' }));
      await assert.rejects(issue(a, { type: 'site_build', systemId: home, bodySlot: 99, facility: 'solar' }));
      assert.deepEqual(funds(), initial);
      await issue(a, { type: 'site_build', systemId: home, bodySlot: 0, facility: 'solar' });
      await issue(a, { type: 'site_build', systemId: home, bodySlot: 2, facility: 'habitat' });
      await issue(a, { type: 'site_build', systemId: home, bodySlot: 4, facility: 'mine' });
      await issue(a, { type: 'site_build', systemId: rift.id, bodySlot: 0, facility: 'research' });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(a)!.sites!.length === 4);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.equal(gameView(a)!.sites!.length, 4);
      assert.equal(gameView(b)!.sites!.length, 0, 'remote foreign sites and construction are private');
      const pending = gameView(a)!.sites!.find((s) => s.bodySlot === 4)!;
      await assert.rejects(issue(a, { type: 'site_build', systemId: home, bodySlot: 4, facility: 'mine' }));
      await assert.rejects(issue(b, { type: 'site_cancel', siteId: pending.id }));
      const beforeCancel = funds();
      await issue(a, { type: 'site_cancel', siteId: pending.id });
      assert.equal(funds().minerals, beforeCancel.minerals + 45);
      await assert.rejects(issue(a, { type: 'site_cancel', siteId: pending.id }));
      const recovered = await connect(database, { token: a.token });
      clients.push(recovered);
      await subscribe(recovered.conn, GAME_QUERIES);
      assert.deepEqual(
        [...gameView(recovered)!.sites!].sort((a, b) => a.id.localeCompare(b.id)),
        [...gameView(a)!.sites!].sort((a, b) => a.id.localeCompare(b.id)),
        'paused construction reconstructs on reconnect',
      );
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(a)!.sites!.every((s) => s.level === 1 && !s.building));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.deepEqual(gameView(a)!.me.installationIncome, { energy: 7, minerals: 2, science: 4 });
      // A production window is measured from authoritative per-site anchors, independent of tick timing.
      await issue(a, {
        type: 'colony_focus',
        systemId: home,
        focus: 'balanced',
        revision: gameView(a)!.systems.find((s) => s.id === home)!.colony!.revision,
      });
      const anchors = [...a.conn.db.visibleGameSites.iter()],
        startFunds = funds();
      const colonyAnchors = [...a.conn.db.myColonies.iter()],
        start = gameView(a)!.tick;
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(a)!.tick >= start + 8);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      await issue(a, {
        type: 'colony_focus',
        systemId: home,
        focus: 'balanced',
        revision: gameView(a)!.systems.find((s) => s.id === home)!.colony!.revision,
      });
      const end = gameView(a)!.tick;
      const baseEnergy = 2 * (Math.floor(end / 4) - Math.floor(start / 4));
      const colonyEnergy = colonyAnchors.reduce(
        (n, c) =>
          n + (c.energyRate * (a.conn.db.myColonies.id.find(c.id)!.lastProducedAt - c.lastProducedAt)) / 4,
        0,
      );
      const siteEnergy = anchors.reduce(
        (n, s) =>
          n +
          ((s.facility === 'solar' ? 5 : s.facility === 'habitat' ? 2 : 0) *
            (a.conn.db.visibleGameSites.id.find(s.id)!.lastProducedAt - s.lastProducedAt)) /
            4,
        0,
      );
      assert(Math.abs(funds().energy - startFunds.energy - baseEnergy - colonyEnergy - siteEnergy) < 1e-6);
      const solar = gameView(a)!.sites!.find((s) => s.facility === 'solar')!;
      await issue(a, { type: 'site_build', systemId: home, bodySlot: 0, facility: 'solar' });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => !!gameView(a)!.sites!.find((s) => s.id === solar.id)?.building);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const beforeUpgradeCancel = funds();
      await issue(a, { type: 'site_cancel', siteId: solar.id });
      assert.equal(gameView(a)!.sites!.find((s) => s.id === solar.id)!.level, 1);
      assert.equal(funds().energy, beforeUpgradeCancel.energy + facilitySpec('solar', 1).cost.energy / 2);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      for (const level of [2, 3]) {
        await issue(a, { type: 'site_build', systemId: home, bodySlot: 0, facility: 'solar' });
        await until(() => gameView(a)!.sites!.find((s) => s.id === solar.id)!.level === level);
      }
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      await assert.rejects(issue(a, { type: 'site_build', systemId: home, bodySlot: 0, facility: 'solar' }));
      const stranger = await connect(database);
      clients.push(stranger);
      await assert.rejects(subscribe(stranger.conn, ['SELECT * FROM game_site']));
      assert.equal(a.conn.db.battleMotion.count(), 0n, 'building never subscribes individual battle motion');
    } finally {
      await admin.conn.reducers.setClock({ paused: true, speed: 1 });
      clients.forEach((c) => c.conn.disconnect());
    }
  },
);
