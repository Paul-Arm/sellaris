import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { seedDatabase, adminToken } from '../admin';
import { connect, join, subscribe, GALAXY_QUERIES, type Client } from '../client';
import { BattleDetailSubscription } from '../detail-subscriptions';
import { SCENARIOS } from '../domain';

async function until(check: () => boolean) {
  for (let i = 0; i < 100; i++) {
    if (check()) return;
    await delay(25);
  }
  assert.fail('Snapshot condition not reached');
}
const assertNoDetails = (c: Client) => {
  for (const table of [
    c.conn.db.battleMotion,
    c.conn.db.battleVitals,
    c.conn.db.battleRoster,
    c.conn.db.fleetShips,
    c.conn.db.focusedBattle,
    c.conn.db.visibleBattles,
  ])
    assert.equal(table.count(), 0n);
};
test(
  'summary-only galaxy, scoped battle subscriptions and durable HP accounting',
  { timeout: 30000 },
  async (t) => {
    const server = process.env.SPACETIME_HTTP || 'http://127.0.0.1:3100';
    const uri = process.env.SPACETIME_WS || 'ws://127.0.0.1:3100';
    const database = `singularity-overview-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      server,
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    await seedDatabase(database, SCENARIOS.smoke, uri);
    const admin = await connect(database, { uri, token: adminToken() }),
      player = await connect(database, { uri });
    const clients = [admin, player];
    await admin.conn.reducers.setClock({ paused: true, speed: 1 });
    await join(player, 1);
    const details = new BattleDetailSubscription(player);
    try {
      await t.test(
        'overview updates slowly without tactical rows and reports exact effective damage',
        async () => {
          const initial = player.conn.db.visibleBattleSummaries.id.find(1)!;
          assert(initial);
          assert.equal(initial.attacker.ships, 20);
          assert.equal(initial.defender.ships, 20);
          assertNoDetails(player);
          let updates = 0;
          const changed = () => {
            updates++;
          };
          player.conn.db.visibleBattleSummaries.onUpdate(changed);
          await admin.conn.reducers.setClock({ paused: false, speed: 4 });
          await delay(2300);
          await admin.conn.reducers.setClock({ paused: true, speed: 4 });
          await until(
            () =>
              [...player.conn.db.clock.iter()][0]?.paused === true &&
              player.conn.db.visibleBattleSummaries.id.find(1)!.sampledAt > initial.sampledAt + 6,
          );
          const summary = player.conn.db.visibleBattleSummaries.id.find(1)!;
          assert(updates >= 2 && updates <= 4, 'Summary cadence is real-time 1 Hz, even at 4x game speed');
          assertNoDetails(player);
          const missingA =
            summary.attacker.startingHull +
            summary.attacker.startingShield -
            summary.attacker.hull -
            summary.attacker.shield;
          const missingD =
            summary.defender.startingHull +
            summary.defender.startingShield -
            summary.defender.hull -
            summary.defender.shield;
          assert(Math.abs(missingA - summary.defender.damageDealt) < 0.001);
          assert(Math.abs(missingD - summary.attacker.damageDealt) < 0.001);
          assert(summary.attacker.damageDealt > 0);
          const before = JSON.stringify(summary);
          await admin.conn.reducers.initializeBattleReports({});
          assert.equal(
            JSON.stringify(player.conn.db.visibleBattleSummaries.id.find(1)),
            before,
            'Backfill must never reset measured damage',
          );
          player.conn.db.visibleBattleSummaries.removeOnUpdate(changed);
        },
      );
      await t.test(
        'open, close, rapid transitions and overview reconnect never retain hidden details',
        async () => {
          await details.focus(1, 1);
          assert.equal(player.conn.db.battleMotion.count(), 40n);
          assert.equal(player.conn.db.focusedBattle.count(), 1n);
          const roster = [...player.conn.db.battleRoster.iter()];
          const byId = new Map([...player.conn.db.battleVitals.iter()].map((p) => [p.shipId, p]));
          const sumA = roster
            .filter((r) => r.side === 0)
            .reduce((sum, r) => sum + byId.get(r.shipId)!.hull, 0);
          assert.equal(sumA, player.conn.db.visibleBattleSummaries.id.find(1)!.attacker.hull);
          await details.focus(0, 0);
          assertNoDetails(player);
          await Promise.all([details.focus(1, 1), details.focus(0, 0)]);
          assertNoDetails(player);
          await details.focus(1, 1);
          const reconnect = await connect(database, { uri, token: player.token });
          clients.push(reconnect);
          await subscribe(reconnect.conn, GALAXY_QUERIES);
          assert.equal(reconnect.identity, player.identity);
          assertNoDetails(reconnect);
          assert.equal(reconnect.conn.db.visibleBattleSummaries.count(), 1n);
          await details.focus(0, 0);
          let detailEvents = 0;
          const changed = () => {
            detailEvents++;
          };
          player.conn.db.battleMotion.onInsert(changed);
          player.conn.db.battleMotion.onUpdate(changed);
          await admin.conn.reducers.setClock({ paused: false, speed: 1 });
          await delay(500);
          await admin.conn.reducers.setClock({ paused: true, speed: 1 });
          await until(() => [...player.conn.db.clock.iter()][0]?.paused === true);
          assertNoDetails(player);
          assert.equal(detailEvents, 0);
          player.conn.db.battleMotion.removeOnInsert(changed);
          player.conn.db.battleMotion.removeOnUpdate(changed);
        },
      );
      await t.test('withdrawal does not count as damage, ending preserves the surviving side', async () => {
        const start = player.conn.db.visibleBattleSummaries.id.find(1)!;
        await player.conn.reducers.withdrawFleet({ fleetId: 1 });
        await until(() => player.conn.db.visibleBattleSummaries.id.find(1)!.attacker.ships === 10);
        assert.equal(
          player.conn.db.visibleBattleSummaries.id.find(1)!.defender.damageDealt,
          start.defender.damageDealt,
        );
        await player.conn.reducers.withdrawFleet({ fleetId: 2 });
        await until(() => player.conn.db.visibleBattleSummaries.id.find(1)!.state === 'finished');
        const end = player.conn.db.visibleBattleSummaries.id.find(1)!;
        assert.equal(end.winnerId, 2);
        assert.equal(end.attacker.ships, 0);
        assert.equal(end.defender.ships, 20);
        assert(end.defender.hull > 0);
        assertNoDetails(player);
      });
    } finally {
      details.dispose();
      await admin.conn.reducers.setClock({ paused: true, speed: 1 });
      for (const c of clients) c.conn.disconnect();
    }
  },
);
