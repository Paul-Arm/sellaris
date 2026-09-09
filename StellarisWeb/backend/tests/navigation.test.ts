import { categoryIncome } from './economy-helpers';
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { adminToken } from '../admin';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { SystemSubscription } from '../system-subscription';
import { addPlayer, createGame, type GameCommand } from '../../shared/game';
import { objectBodies } from '../../shared/systemObjects';
import { localPosition, localVelocity, bodyPosition, BUILD_REACH } from '../../shared/navigation';

async function until(check: () => boolean, timeout = 60000) {
  const end = Date.now() + timeout;
  while (!check()) {
    assert(Date.now() < end, 'navigation timeout');
    await delay(50);
  }
}
test(
  'local navigation, ordered travel and physical surveys; persistent free stations',
  { timeout: 180000 },
  async () => {
    const database = `singularity-game-navigation-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const source = createGame('AF1234'),
      pa = addPlayer(source, 'a', 'Navigator'),
      pb = addPlayer(source, 'b', 'Observer');
    pa.resources = { energy: 5000, minerals: 5000, data: 5000 };
    const scout = source.fleets.find((f) => f.owner === pa.id && f.type === 'scout')!;
    const initial = scout.systemId;
    const target = source.systems.find(
      (s) => s.id !== initial && s.id !== pb.home && !s.owner && s.kind === 'star',
    )!;
    target.defense = 0;
    // The visitor sees motion in the system, but never the navigator's queue.
    source.fleets.find((f) => f.owner === pb.id)!.systemId = initial;
    source.paused = true;
    const clients: Client[] = [],
      admin = await connect(database, { token: adminToken() });
    clients.push(admin);
    try {
      await admin.conn.reducers.initializeGame({
        code: source.code,
        seed: 42,
        sourceJson: JSON.stringify(source),
        creationKey: 'navigation',
      });
      for (const id of ['a', 'b']) {
        const c = await connect(database);
        clients.push(c);
        const ticket = randomBytes(32).toString('hex');
        await admin.conn.reducers.reserveGameSeat({ ticket, externalId: id, templateJson: '' });
        await c.conn.reducers.redeemGameSeat({ ticket });
        await subscribe(c.conn, GAME_QUERIES);
      }
      const a = clients[1],
        b = clients[2],
        issue = (c: GameCommand) => a.conn.reducers.gameCommand({ commandJson: JSON.stringify(c) });
      const ship = () => gameView(a)!.fleets.find((f) => f.id === scout.id)!,
        nav = () => ship().navigation!;
      const home = [...a.conn.db.myGamePlayer.iter()][0].homeId;
      const detail = new SystemSubscription(a);
      await detail.focus(home);
      const bodies = () => objectBodies(a.conn.db.focusedSystemObjects.iter());
      const partner = source.fleets.find((f) => f.owner === pa.id && f.id !== scout.id)!;
      const foreign = source.fleets.find((f) => f.owner === pb.id)!;
      const groupIds = [scout.id, partner.id];
      const groupState = () => groupIds.map((id) => gameView(a)!.fleets.find((f) => f.id === id)!.navigation);
      await issue({
        type: 'fleet_group',
        fleetIds: groupIds,
        order: { type: 'local_move', systemId: initial, point: { x: 200, y: 100, z: 200 } },
      });
      await issue({
        type: 'fleet_group',
        fleetIds: groupIds,
        order: { type: 'local_move', systemId: initial, point: { x: -200, y: 100, z: 200 }, append: true },
      });
      assert(groupState().every((navigation) => navigation!.orders.length === 2));
      const groupBefore = structuredClone(groupState());
      await assert.rejects(
        issue({ type: 'fleet_group', fleetIds: [scout.id, foreign.id], order: { type: 'fleet_stop' } }),
      );
      assert.deepEqual(groupState(), groupBefore, 'one foreign fleet rolls back the entire group');
      await assert.rejects(
        issue({ type: 'fleet_group', fleetIds: [scout.id, scout.id], order: { type: 'fleet_stop' } }),
      );
      await delay(600);
      assert.deepEqual(groupState(), groupBefore, 'group navigation remains paused');
      const groupReconnect = await connect(database, { token: a.token });
      clients.push(groupReconnect);
      await subscribe(groupReconnect.conn, GAME_QUERIES);
      assert.deepEqual(
        groupIds.map((id) => gameView(groupReconnect)!.fleets.find((f) => f.id === id)!.navigation),
        groupBefore,
      );
      await issue({ type: 'fleet_group', fleetIds: groupIds, order: { type: 'fleet_stop' } });
      assert(groupState().every((navigation) => navigation!.orders.length === 0));
      await assert.rejects(
        issue({ type: 'local_move', fleetId: scout.id, systemId: initial, point: { x: 1700, y: 0, z: 0 } }),
      );
      await assert.rejects(
        b.conn.reducers.gameCommand({
          commandJson: JSON.stringify({
            type: 'local_move',
            fleetId: scout.id,
            systemId: initial,
            point: { x: 200, y: 100, z: 200 },
          }),
        }),
      );
      await issue({
        type: 'local_move',
        fleetId: scout.id,
        systemId: initial,
        point: { x: 700, y: 200, z: 300 },
      });
      await issue({ type: 'scan', fleetId: scout.id, append: true }); // Already surveyed: skip at execution, then continue.
      await issue({
        type: 'local_move',
        fleetId: scout.id,
        systemId: initial,
        point: { x: -700, y: 100, z: 300 },
        append: true,
      });
      await issue({
        type: 'local_move',
        fleetId: scout.id,
        systemId: initial,
        point: { x: 0, y: 80, z: 500 },
        append: true,
      });
      assert.equal(nav().orders.length, 4);
      await until(() => !!gameView(b)!.fleets.find((f) => f.id === scout.id)?.navigation);
      assert.deepEqual(gameView(b)!.fleets.find((f) => f.id === scout.id)!.navigation!.orders, []);
      await issue({ type: 'fleet_remove_order', fleetId: scout.id, index: 3 });
      assert.equal(nav().orders.length, 3);
      await assert.rejects(issue({ type: 'fleet_remove_order', fleetId: scout.id, index: 0 }));
      const paused = structuredClone(nav());
      await delay(600);
      assert.deepEqual(nav(), paused);
      const reconnect = await connect(database, { token: a.token });
      clients.push(reconnect);
      await subscribe(reconnect.conn, GAME_QUERIES);
      assert.deepEqual(gameView(reconnect)!.fleets.find((f) => f.id === scout.id)!.navigation, paused);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => nav().orders.length === 1);
      assert.equal(nav().motion.to.x, -700);
      await until(() => nav().orders.length === 0);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.deepEqual(localPosition(nav().motion, gameView(a)!.tick), { x: -700, y: 100, z: 300 });
      assert(gameView(a)!.log.some((e) => e.text.includes('übersprungen')));
      await issue({
        type: 'local_move',
        fleetId: scout.id,
        systemId: initial,
        point: { x: 800, y: 80, z: 0 },
      });
      await admin.conn.reducers.setClock({ paused: false, speed: 1 });
      const flightStart = nav().motion.startedAt;
      await until(() => gameView(a)!.tick >= flightStart + 3);
      await admin.conn.reducers.setClock({ paused: true, speed: 1 });
      const stoppedAt = localPosition(nav().motion, gameView(a)!.tick);
      const velocityAt = localVelocity(nav().motion, gameView(a)!.tick);
      await issue({
        type: 'local_move',
        fleetId: scout.id,
        systemId: initial,
        point: { x: 600, y: 80, z: 300 },
        append: true,
      });
      const beforeInvalid = structuredClone(nav());
      await assert.rejects(
        issue({
          type: 'local_move',
          fleetId: scout.id,
          systemId: target.id,
          point: { x: 600, y: 80, z: 300 },
        }),
      );
      assert.deepEqual(nav(), beforeInvalid, 'invalid replacement preserves the active flight and queue');
      await issue({
        type: 'local_move',
        fleetId: scout.id,
        systemId: initial,
        point: { x: -600, y: 80, z: -300 },
      });
      assert.equal(nav().orders.length, 1, 'right-click replacement clears queued orders');
      assert.deepEqual(nav().motion.from, stoppedAt, 'replacement starts at the current flight position');
      assert.deepEqual(
        localVelocity(nav().motion, gameView(a)!.tick),
        velocityAt,
        'replacement retains momentum',
      );
      assert.equal(nav().motion.to.x, -600);
      await issue({ type: 'fleet_stop', fleetId: scout.id });
      assert.deepEqual(nav().motion.from, stoppedAt);
      assert.notDeepEqual(nav().motion.to, stoppedAt, 'stop brakes instead of freezing instantly');
      assert.equal(nav().orders.length, 0);
      await issue({ type: 'move', fleetId: scout.id, systemId: target.id });
      await issue({ type: 'scan', fleetId: scout.id, append: true });
      await issue({
        type: 'local_move',
        fleetId: scout.id,
        systemId: target.id,
        point: { x: 800, y: 120, z: 0 },
        append: true,
      });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => nav().phase === 'survey_flight' || nav().phase === 'survey_scan');
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert(!gameView(a)!.me.surveyed.includes(target.id), 'arrival alone does not finish the survey');
      const targetId = [...a.conn.db.gameAtlas.iter()].find((s) => s.externalId === target.id)!.id;
      await detail.focus(targetId);
      const expected = bodies()
        .map((b) => b.slot)
        .sort((a, b) => a - b);
      const visited = new Set<number>();
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      const end = Date.now() + 90000;
      while (!gameView(a)!.me.surveyed.includes(target.id)) {
        for (const slot of nav().visited) visited.add(slot);
        if (nav().phase === 'survey_scan') visited.add(nav().targetSlot);
        assert(Date.now() < end, 'survey completion');
        await delay(30);
      }
      // The last completed survey is retained until the next order begins. During scan at each body, record it too.
      assert.deepEqual(
        [...visited].sort((a, b) => a - b),
        expected,
        'every body was visited and scanned before the reward',
      );
      await until(() => nav().orders.length === 0);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.equal(ship().systemId, target.id);
      assert.equal(nav().motion.to.x, 800);
      await assert.rejects(issue({ type: 'scan', fleetId: scout.id }));
      await detail.focus(home);
      const star = bodies().find((b) => b.kind === 'star')!;
      const rock = bodies().find((b) => b.kind === 'asteroid')!;
      await assert.rejects(
        issue({ type: 'site_build', systemId: initial, bodySlot: rock.slot, facility: 'solar' }),
      );
      await issue({ type: 'site_build', systemId: initial, bodySlot: star.slot, facility: 'solar' });
      const beforeMine = gameView(a)!.me.resources.minerals;
      await issue({ type: 'site_build', systemId: initial, bodySlot: rock.slot, facility: 'mine' });
      assert(
        !gameView(a)!.sites!.some((s) => s.facility === 'mine'),
        'distant construction does not start remotely',
      );
      assert.equal(gameView(a)!.me.resources.minerals, beforeMine, 'approach reserves no construction costs');
      const builder = gameView(a)!.fleets.find((f) =>
        f.navigation?.orders.some((o) => o.type === 'site_build' && o.bodySlot === rock.slot),
      )!;
      assert(builder, 'construction is a real ship order');
      const pendingBuild = structuredClone(builder.navigation);
      await assert.rejects(
        issue({ type: 'site_build', systemId: initial, bodySlot: rock.slot, facility: 'mine' }),
      );
      assert.deepEqual(gameView(a)!.fleets.find((f) => f.id === builder.id)!.navigation, pendingBuild);
      await issue({ type: 'fleet_stop', fleetId: builder.id });
      assert.equal(gameView(a)!.fleets.find((f) => f.id === builder.id)!.navigation!.orders.length, 0);
      assert.equal(gameView(a)!.me.resources.minerals, beforeMine, 'cancelling the approach charges nothing');
      await assert.rejects(
        issue({
          type: 'site_build',
          systemId: initial,
          bodySlot: rock.slot,
          facility: 'mine',
          fleetId: scout.id,
        }),
        'a ship in another system cannot start remote construction',
      );
      await issue({
        type: 'site_build',
        systemId: initial,
        bodySlot: rock.slot,
        facility: 'mine',
        fleetId: builder.id,
      });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(a)!.sites!.some((s) => s.facility === 'mine'));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const arrived = gameView(a)!.fleets.find((f) => f.id === builder.id)!.navigation!;
      const near = localPosition(arrived.motion, gameView(a)!.tick),
        rockAt = bodyPosition(rock, bodies(), gameView(a)!.tick);
      assert(
        Math.hypot(near.x - rockAt.x, near.y - rockAt.y, near.z - rockAt.z) <= rock.radius + BUILD_REACH,
      );
      const count = bodies().length,
        point = { x: 1400, y: 250, z: 0 };
      await assert.rejects(
        issue({
          type: 'station_place',
          systemId: initial,
          point: { x: 0, y: 0, z: 0 },
          facility: 'research',
        }),
      );
      assert.equal(bodies().length, count, 'invalid placement does not leave an object');
      await issue({ type: 'station_place', systemId: initial, point, facility: 'research' });
      assert.equal(bodies().length, count, 'free station is not created before its builder arrives');
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => bodies().length === count + 1);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const station = bodies().find((b) => b.kind === 'station')!;
      assert.deepEqual(station.position, point);
      await assert.rejects(issue({ type: 'station_place', systemId: initial, point, facility: 'habitat' }));
      await issue({ type: 'site_cancel', siteId: station.objectId });
      await until(() => bodies().length === count);
      await issue({ type: 'station_place', systemId: initial, point, facility: 'research' });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(a)!.sites!.some((s) => s.bodySlot > 8 && s.level === 1));
      await until(() => gameView(a)!.sites!.some((s) => s.facility === 'solar' && s.level === 1));
      assert(gameView(a)!.sites!.some((s) => s.facility === 'mine' && s.level === 1));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert(categoryIncome(gameView(a)!, 'installations').data > 0, 'free station produces research');
      await detail.focus(0);
    } finally {
      for (const c of clients) c.conn.disconnect();
      cli(['delete', database, '--server', 'http://127.0.0.1:3100', '--yes']);
    }
  },
);
