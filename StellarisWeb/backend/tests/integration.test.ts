import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { seedDatabase, adminToken } from '../admin';
import { connect, join, subscribe, GALAXY_QUERIES, DETAIL_QUERIES, type Client } from '../client';
import { SCENARIOS } from '../domain';
import { checkCompactBattle } from '../battle-snapshot';
const ALL_DETAIL_QUERIES = [
  ...DETAIL_QUERIES,
  'SELECT * FROM battle_participants',
  'SELECT * FROM visible_battles',
];

const server = process.env.SPACETIME_HTTP || 'http://127.0.0.1:3100';
const uri = process.env.SPACETIME_WS || 'ws://127.0.0.1:3100';
async function sql(database: string, token: string, query: string) {
  return fetch(`${server}/v1/database/${database}/sql`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'text/plain' },
    body: query,
  });
}
async function waitFor(check: () => boolean, message: string) {
  for (let i = 0; i < 100; i++) {
    if (check()) return;
    await delay(25);
  }
  assert.fail(message);
}
test(
  'SpacetimeDB: isolated identities, atomic commands, live hot join and durable jobs',
  { timeout: 60000 },
  async (t) => {
    const database = `singularity-test-${Date.now()}`;
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
    const clients: Client[] = [];
    const admin = await connect(database, { token: adminToken(), uri });
    clients.push(admin);
    await admin.conn.reducers.setClock({ paused: true, speed: 1 });
    try {
      const a = await connect(database, { uri });
      clients.push(a);
      const b = await connect(database, { uri });
      clients.push(b);
      const outsider = await connect(database, { uri });
      clients.push(outsider);
      await join(a, 1, { fleetId: 1, battleId: 1 }, ALL_DETAIL_QUERIES);
      await join(b, 2, { fleetId: 11, battleId: 1 }, ALL_DETAIL_QUERIES);
      await join(outsider, 4);
      await t.test('one initial snapshot includes coherent fleets, ships, clock and battle', () => {
        assert.equal(Number(a.conn.db.star.count()), 100);
        assert.equal(Number(a.conn.db.fleetShips.count()), 10);
        assert.equal(Number(a.conn.db.battleParticipants.count()), 40);
        assert.equal(checkCompactBattle(a, 1, true), 40);
        assert.equal([...a.conn.db.myEmpire.iter()][0].id, 1);
        assert.equal(Number(a.conn.db.fleetShips.count()), a.conn.db.galaxyFleets.id.find(1)!.shipCount);
        const ids = new Set([...a.conn.db.battleParticipants.iter()].map((p) => p.shipId));
        assert([...a.conn.db.battleParticipants.iter()].every((p) => !p.targetId || ids.has(p.targetId)));
        assert([...outsider.conn.db.galaxyFleets.iter()].every((f) => f.empireId === 4));
      });
      await t.test(
        'server rejects broad private queries, foreign focus, forged commands and scheduler calls',
        async () => {
          const response = await sql(database, outsider.token, 'SELECT * FROM ship');
          assert(!response.ok, 'Private ship table must not be readable by player JWT');
          await assert.rejects(outsider.conn.reducers.setFocus({ fleetId: 1, battleId: 0 }));
          await assert.rejects(outsider.conn.reducers.setFocus({ fleetId: 0, battleId: 1 }));
          await assert.rejects(b.conn.reducers.moveFleet({ fleetId: 1, route: [5] }));
          await assert.rejects(b.conn.reducers.setClock({ paused: false, speed: 4 }));
          const scheduleCall = await fetch(`${server}/v1/database/${database}/call/combat_tick`, {
            method: 'POST',
            headers: { Authorization: `Bearer ${b.token}`, 'Content-Type': 'application/json' },
            body: '[{"id":1,"scheduled_at":{"Interval":{"__time_duration_micros__":100000}}}]',
          });
          assert(!scheduleCall.ok, 'Internal scheduled reducer must reject client calls');
          await subscribe(outsider.conn, ALL_DETAIL_QUERIES);
          assert.equal(Number(outsider.conn.db.fleetShips.count()), 0);
          assert.equal(Number(outsider.conn.db.battleParticipants.count()), 0);
          assert.equal(checkCompactBattle(outsider, 1, true), 0);
          for (const table of [
            'battle_roster',
            'battle_motion',
            'battle_vitals',
            'focused_battle',
            'visible_battle_summaries',
          ]) {
            const response = await sql(database, outsider.token, `SELECT * FROM ${table}`);
            assert(response.ok);
            const result = await response.json();
            assert(
              result.every((r: { rows: unknown[] }) => r.rows.length === 0),
              'SQL view must also enforce fog of war',
            );
          }
        },
      );
      await t.test(
        'compact projections stay coherent during live transactions without resending roster',
        async () => {
          let motionUpdates = 0,
            rosterUpdates = 0;
          const failures: string[] = [];
          const onMotion = () => {
            motionUpdates++;
            try {
              checkCompactBattle(a, 1, true);
            } catch (error) {
              failures.push(String(error));
            }
          };
          const onRoster = () => {
            rosterUpdates++;
          };
          a.conn.db.battleMotion.onUpdate(onMotion);
          a.conn.db.battleRoster.onUpdate(onRoster);
          try {
            await admin.conn.reducers.setClock({ paused: false, speed: 1 });
            await delay(900);
            await admin.conn.reducers.setClock({ paused: true, speed: 1 });
            await waitFor(() => motionUpdates > 0, 'Compact motion must advance');
            assert.deepEqual(failures, []);
            assert.equal(rosterUpdates, 0, 'Movement must not resend unchanged affiliation');
            assert.equal(checkCompactBattle(a, 1, true), 40);
            assert(a.traffic.compressedFrames > 0, 'Gzip wire path must actually be exercised');
            assert(a.traffic.decodedBytes > a.traffic.receivedBytes);
            await a.conn.reducers.setFocus({ fleetId: 0, battleId: 0 });
            await waitFor(() => a.conn.db.battleRoster.count() === 0n, 'Focus exit clears details');
            assert.equal(checkCompactBattle(a, 1, true), 0);
            await a.conn.reducers.setFocus({ fleetId: 1, battleId: 1 });
            await waitFor(() => a.conn.db.battleRoster.count() === 40n, 'Focus entry reconstructs details');
            assert.equal(checkCompactBattle(a, 1, true), 40);
          } finally {
            a.conn.db.battleMotion.removeOnUpdate(onMotion);
            a.conn.db.battleRoster.removeOnUpdate(onRoster);
          }
        },
      );
      await t.test(
        'withdraw, failed split rollback, solo split and merge preserve membership counts',
        async () => {
          await a.conn.reducers.withdrawFleet({ fleetId: 1 });
          await waitFor(() => Number(a.conn.db.battleParticipants.count()) === 30, 'Withdrawal snapshot');
          assert.equal(checkCompactBattle(a, 1, true), 30);
          assert.equal(a.conn.db.galaxyFleets.id.find(1)!.battleId, 0);
          const owned = [...a.conn.db.fleetShips.iter()];
          const fleetCount = Number(a.conn.db.galaxyFleets.count());
          await assert.rejects(a.conn.reducers.splitFleet({ fleetId: 1, shipIds: [owned[0].id, 999999] }));
          assert.equal(Number(a.conn.db.galaxyFleets.count()), fleetCount);
          assert.equal(Number(a.conn.db.fleetShips.count()), 10);
          await a.conn.reducers.splitFleet({ fleetId: 1, shipIds: [owned[0].id] });
          await waitFor(() => Number(a.conn.db.fleetShips.count()) === 9, 'Split ships applied');
          const solo = [...a.conn.db.galaxyFleets.iter()].find((f) => f.empireId === 1 && f.shipCount === 1)!;
          assert(solo);
          await a.conn.reducers.mergeFleets({ sourceId: solo.id, targetId: 1 });
          await waitFor(() => Number(a.conn.db.fleetShips.count()) === 10, 'Merged ships applied');
          assert.equal(Number(a.conn.db.galaxyFleets.count()), fleetCount);
        },
      );
      await t.test(
        'redirect changes fleet route without touching its individual ship rows; pause freezes simulation',
        async () => {
          const ships = JSON.stringify([...a.conn.db.fleetShips.iter()]);
          let shipUpdates = 0;
          a.conn.db.fleetShips.onUpdate(() => {
            shipUpdates++;
          });
          await a.conn.reducers.moveFleet({ fleetId: 1, route: [5, 9] });
          await a.conn.reducers.moveFleet({ fleetId: 1, route: [9] });
          await delay(350);
          assert.equal(JSON.stringify([...a.conn.db.fleetShips.iter()]), ships);
          assert.equal(shipUpdates, 0);
          const before = [...a.conn.db.visibleBattles.iter()][0].step;
          await delay(300);
          assert.equal([...a.conn.db.visibleBattles.iter()][0].step, before);
        },
      );
      await t.test(
        'research/construction commands persist progress, ownership and cancellation',
        async () => {
          const before = [...a.conn.db.myEmpire.iter()][0].minerals;
          await a.conn.reducers.startJob({ kind: 'construction', targetId: 1 });
          await waitFor(() => Number(a.conn.db.myJobs.count()) === 3, 'Job snapshot');
          assert.equal([...a.conn.db.myEmpire.iter()][0].minerals, before - 100);
          const job = [...a.conn.db.myJobs.iter()].sort((a, b) => b.id - a.id)[0];
          await assert.rejects(b.conn.reducers.cancelJob({ jobId: job.id }));
          await a.conn.reducers.cancelJob({ jobId: job.id });
          await assert.rejects(a.conn.reducers.cancelJob({ jobId: job.id }));
        },
      );
      await t.test(
        'live reconnect retains identity and reconstructs advancing combat and economy',
        async () => {
          const before = [...a.conn.db.visibleBattles.iter()][0].step;
          const token = a.token;
          a.conn.disconnect();
          await admin.conn.reducers.setClock({ paused: false, speed: 4 });
          await delay(1600);
          const resumed = await connect(database, { uri, token });
          clients.push(resumed);
          await subscribe(resumed.conn, [...GALAXY_QUERIES, ...ALL_DETAIL_QUERIES]);
          assert.equal(resumed.identity, a.identity);
          assert.equal([...resumed.conn.db.myEmpire.iter()][0].id, 1);
          assert([...resumed.conn.db.visibleBattles.iter()][0].step > before);
          assert([...resumed.conn.db.myEmpire.iter()][0].energy > 10000);
          assert.equal(Number(resumed.conn.db.fleetShips.count()), 10);
          assert.equal(Number(resumed.conn.db.battleParticipants.count()), 30);
          assert.equal(checkCompactBattle(resumed, 1, true), 30);
          assert([...resumed.conn.db.battleParticipants.iter()].some((p) => p.targetId > 0));
          assert.equal([...resumed.conn.db.myJobs.iter()].filter((j) => j.status === 'cancelled').length, 1);
        },
      );
      await t.test('battle end atomically removes all compact detail rows', async () => {
        await admin.conn.reducers.setClock({ paused: true, speed: 1 });
        for (const fleetId of [11, 12]) await b.conn.reducers.withdrawFleet({ fleetId });
        await waitFor(() => b.conn.db.visibleBattles.id.find(1)?.state === 'finished', 'Battle must finish');
        assert.equal(checkCompactBattle(b, 1, true), 0);
        await waitFor(
          () => clients.at(-1)!.conn.db.battleRoster.count() === 0n,
          'Other client receives battle end',
        );
        assert.equal(checkCompactBattle(clients.at(-1)!, 1, true), 0);
        await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      });
      await t.test('seed cursor and activation are protected against replay', async () => {
        await assert.rejects(admin.conn.reducers.seedShips({ empireId: 1, expectedOffset: 0, count: 100 }));
        await assert.rejects(admin.conn.reducers.activate({}));
      });
      await t.test(
        'production deadlines complete once, preserve work and apply research modifiers',
        async () => {
          const resumed = clients.at(-1)!;
          await delay(25000);
          const e = [...resumed.conn.db.myEmpire.iter()][0];
          assert(e.researchLevel >= 1);
          const completed = [...resumed.conn.db.myJobs.iter()].filter((j) => j.status === 'complete');
          assert(completed.some((j) => j.kind === 'research'));
          assert(completed.some((j) => j.kind === 'construction'));
          assert(completed.every((j) => j.workDone === j.workTotal));
          await resumed.conn.reducers.startJob({ kind: 'research', targetId: 1 });
          assert([...resumed.conn.db.myJobs.iter()].some((j) => j.status === 'active' && j.rate > 1));
        },
      );
    } finally {
      await admin.conn.reducers.setClock({ paused: true, speed: 1 });
      for (const c of clients) c.conn.disconnect();
    }
  },
);
