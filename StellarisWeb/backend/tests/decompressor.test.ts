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
import { facilitySpec, facilityYield } from '../../shared/celestial';
import { shipSetFor } from '../../shared/shipSets';
import { crisisProductionFactor } from '../../shared/stories';

async function until(check: () => boolean, timeout = 65000) {
  const end = Date.now() + timeout;
  while (!check()) {
    assert(Date.now() < end, 'decompressor timeout');
    await delay(70);
  }
}
test(
  'decompressor builds at a neutral black hole, reserves its host and pays durable mineral output',
  { timeout: 220000 },
  async () => {
    const database = `singularity-game-decompressor-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const source = createGame('DC0001'),
      p = addPlayer(source, 'a', 'Extraction'),
      other = addPlayer(source, 'b', 'Rival');
    const hole = source.systems.find((s) => s.kind === 'blackhole')!;
    hole.class = 'BH';
    source.paused = true;
    for (const player of [p, other]) {
      player.resources = { energy: 14000, minerals: 14000, data: 1000 };
      player.techs = ['megastructures'];
      player.surveyed.push(hole.id);
      player.discovered.push(hole.id);
      source.fleets.find((f) => f.owner === player.id && f.type === 'scout')!.systemId = hole.id;
    }
    const admin = await connect(database, { token: adminToken() }),
      clients: Client[] = [admin];
    try {
      await admin.conn.reducers.initializeGame({
        code: source.code,
        seed: 42,
        sourceJson: JSON.stringify(source),
        migrationKey: 'decompressor',
      });
      for (const id of [p.id, other.id]) {
        const client = await connect(database);
        clients.push(client);
        const ticket = randomBytes(32).toString('hex');
        await admin.conn.reducers.reserveGameSeat({ ticket, externalId: id, templateJson: '' });
        await client.conn.reducers.redeemGameSeat({ ticket });
        await subscribe(client.conn, GAME_QUERIES);
      }
      const a = clients[1],
        b = clients[2],
        view = () => gameView(a)!,
        issue = (cmd: GameCommand) => a.conn.reducers.gameCommand({ commandJson: JSON.stringify(cmd) });
      const focus = new SystemSubscription(a),
        nativeHole = [...a.conn.db.gameAtlas.iter()].find((s) => s.externalId === hole.id)!.id;
      await focus.focus(nativeHole);
      const bodies = () => objectBodies(a.conn.db.focusedSystemObjects.iter());
      const scout = view().fleets.find((f) => f.owner === p.id && f.type === 'scout')!;
      const place: GameCommand = {
        type: 'megastructure_place',
        systemId: hole.id,
        bodySlot: 0,
        facility: 'decompressor',
        fleetId: scout.id,
      };
      await assert.rejects(issue({ ...place, systemId: p.home }), /Schwarzes Loch/);
      await assert.rejects(issue({ ...place, facility: 'dyson' }), /eigenes System/);
      await assert.rejects(
        issue({ type: 'site_build', systemId: hole.id, bodySlot: 0, facility: 'decompressor' }),
        /passt nicht/,
      );
      await issue({
        type: 'local_move',
        systemId: hole.id,
        fleetId: scout.id,
        point: { x: 1200, y: 50, z: 0 },
      });
      await issue(place);
      assert(!bodies().some((s) => s.megastructure));
      await delay(450);
      assert(!bodies().some((s) => s.megastructure), 'paused queue does not start remote construction');
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => bodies().some((s) => s.megastructure === 'decompressor'));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      let structure = bodies().find((s) => s.megastructure === 'decompressor')!;
      const firstId = structure.objectId,
        cash = view().me.resources.minerals;
      await issue({ type: 'site_cancel', siteId: firstId });
      assert.equal(view().me.resources.minerals, cash + facilitySpec('decompressor', 0).cost.minerals / 2);
      assert(!bodies().some((s) => s.objectId === firstId));
      await assert.rejects(issue({ type: 'site_cancel', siteId: firstId }));
      await issue(place);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => bodies().some((s) => s.megastructure === 'decompressor'));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      structure = bodies().find((s) => s.megastructure === 'decompressor')!;
      assert.notEqual(structure.objectId, firstId);
      const site = () => view().sites!.find((s) => s.id === structure.objectId)!;
      const rivalFleet = gameView(b)!.fleets.find((f) => f.owner === other.id && f.type === 'scout')!;
      await assert.rejects(
        b.conn.reducers.gameCommand({ commandJson: JSON.stringify({ ...place, fleetId: rivalFleet.id }) }),
        /bereits eine Megastruktur/,
      );
      await assert.rejects(
        b.conn.reducers.gameCommand({
          commandJson: JSON.stringify({ type: 'site_cancel', siteId: structure.objectId }),
        }),
      );
      await assert.rejects(
        b.conn.reducers.gameCommand({
          commandJson: JSON.stringify({
            type: 'site_build',
            systemId: hole.id,
            bodySlot: structure.slot,
            facility: 'decompressor',
          }),
        }),
        /anderen Reich/,
      );
      await issue({
        type: 'site_build',
        systemId: hole.id,
        bodySlot: 0,
        facility: 'research',
        fleetId: scout.id,
      });
      const joined = await connect(database, { token: a.token });
      clients.push(joined);
      await subscribe(joined.conn, GAME_QUERIES);
      assert.deepEqual(gameView(joined)!.sites, view().sites, 'reconnect preserves active projects');
      for (const level of [1, 2, 3]) {
        if (level > 1) {
          await issue({
            type: 'site_build',
            systemId: hole.id,
            bodySlot: structure.slot,
            facility: 'decompressor',
            fleetId: scout.id,
          });
          await admin.conn.reducers.setClock({ paused: false, speed: 4 });
          await until(() => site().building);
          await admin.conn.reducers.setClock({ paused: true, speed: 4 });
          assert.equal(site().level, level - 1, 'upgrades retain previous production');
          if (level === 3) {
            await issue({
              type: 'empire_ship_set',
              shipSet: shipSetFor(view().me.empire!.design),
              revision: view().me.empire!.revision,
            });
            const before = view().me.resources.minerals;
            await issue({ type: 'site_cancel', siteId: site().id });
            assert.equal(site().level, 2);
            assert.equal(site().building, false);
            assert.equal(
              view().me.resources.minerals,
              before + facilitySpec('decompressor', 2).cost.minerals / 2,
            );
            await issue({
              type: 'site_build',
              systemId: hole.id,
              bodySlot: structure.slot,
              facility: 'decompressor',
              fleetId: scout.id,
            });
          }
        }
        const state = structuredClone(site());
        await delay(450);
        assert.deepEqual(site(), state, 'pause freezes construction');
        await admin.conn.reducers.setClock({ paused: false, speed: 4 });
        await until(() => site().level === level && !site().building);
        await admin.conn.reducers.setClock({ paused: true, speed: 4 });
        assert.equal(site().id, structure.objectId);
        assert(!site().suspended);
        assert.equal(
          view().systems.find((s) => s.id === hole.id)!.owner,
          null,
          'installation does not grant a victory colony',
        );
      }
      assert(view().sites!.some((s) => s.bodySlot === 0 && s.facility === 'research' && s.level === 1));
      const factor = Math.min(1, ...view().crises!.map((c) => crisisProductionFactor(c.phase, c.shielded)));
      assert.equal(view().me.installationIncome!.minerals, facilityYield('decompressor', 3, factor).minerals);
      const start = view().tick,
        minerals = view().me.resources.minerals;
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => view().tick >= start + 8);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert(
        view().me.resources.minerals >= minerals + facilityYield('decompressor', 3, 0.5).minerals,
        'actual mineral payout includes decompressor even during the crisis',
      );
      await assert.rejects(
        issue({ type: 'site_build', systemId: hole.id, bodySlot: structure.slot, facility: 'decompressor' }),
        /Maximale/,
      );
      await assert.rejects(
        issue({ type: 'site_build', systemId: hole.id, bodySlot: structure.slot, facility: 'dyson' }),
        /passt nicht/,
      );
      await focus.focus(0);
    } finally {
      clients.forEach((c) => c.conn.disconnect());
      cli(['delete', database, '--server', 'http://127.0.0.1:3100', '--yes']);
    }
  },
);
