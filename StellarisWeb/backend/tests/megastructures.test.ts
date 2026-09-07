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
import { facilitySpec } from '../../shared/celestial';
import { crisisProductionFactor } from '../../shared/stories';
import { STELLAR_COLLAPSE } from '../../shared/stellarProjects';

async function until(check: () => boolean, timeout = 55000) {
  const end = Date.now() + timeout;
  while (!check()) {
    assert(Date.now() < end, 'megastructure timeout');
    await delay(60);
  }
}
test(
  'Dyson construction and controlled stellar collapse preserve identity and apply economic consequences',
  { timeout: 220000 },
  async () => {
    const database = `singularity-game-dyson-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const source = createGame('D750A1'),
      p = addPlayer(source, 'a', 'Dyson Builder'),
      other = addPlayer(source, 'b', 'Observer');
    source.paused = true;
    p.resources = { energy: 12000, minerals: 12000, data: 2000 };
    p.techs = ['terraforming', 'extraction', 'automation', 'propulsion'];
    const admin = await connect(database, { token: adminToken() }),
      clients: Client[] = [admin];
    try {
      await admin.conn.reducers.initializeGame({
        code: source.code,
        seed: 42,
        sourceJson: JSON.stringify(source),
        migrationKey: 'dyson',
      });
      for (const id of [p.id, other.id]) {
        const c = await connect(database);
        clients.push(c);
        const ticket = randomBytes(32).toString('hex');
        await admin.conn.reducers.reserveGameSeat({ ticket, externalId: id, templateJson: '' });
        await c.conn.reducers.redeemGameSeat({ ticket });
        await subscribe(c.conn, GAME_QUERIES);
      }
      const a = clients[1],
        b = clients[2],
        issue = (cmd: GameCommand) => a.conn.reducers.gameCommand({ commandJson: JSON.stringify(cmd) });
      const detail = new SystemSubscription(a);
      await detail.focus([...a.conn.db.myGamePlayer.iter()][0].homeId);
      const bodies = () => objectBodies(a.conn.db.focusedSystemObjects.iter());
      const count = bodies().length;
      const place: GameCommand = {
        type: 'megastructure_place',
        systemId: p.home,
        bodySlot: 0,
        facility: 'dyson',
      };
      await assert.rejects(issue(place), /Megakonstruktion/);
      assert.equal(bodies().length, count);
      await issue({ type: 'research', tech: 'megastructures' });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(a)!.me.techs.includes('megastructures'));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      await assert.rejects(b.conn.reducers.gameCommand({ commandJson: JSON.stringify(place) }));
      await assert.rejects(issue({ ...place, bodySlot: 1 }));
      await assert.rejects(issue({ type: 'site_build', systemId: p.home, bodySlot: 0, facility: 'dyson' }));
      await issue({ type: 'site_build', systemId: p.home, bodySlot: 0, facility: 'solar' });
      await issue(place);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => bodies().some((x) => x.megastructure === 'dyson'));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      let structure = bodies().find((x) => x.megastructure === 'dyson')!;
      const firstId = structure.objectId;
      assert.equal(structure.parent, 0);
      assert(
        gameView(a)!.sites!.some((s) => s.facility === 'solar'),
        'stellar installation coexists',
      );
      await assert.rejects(issue(place));
      await issue({ type: 'site_cancel', siteId: structure.objectId });
      assert(!bodies().some((x) => x.objectId === firstId));
      await issue(place);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => bodies().some((x) => x.megastructure === 'dyson'));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      structure = bodies().find((x) => x.megastructure === 'dyson')!;
      assert.notEqual(structure.objectId, firstId, 'cancelled IDs are never reused');
      const site = () => gameView(a)!.sites!.find((s) => s.id === structure.objectId)!;
      for (const level of [1, 2, 3]) {
        if (level > 1) {
          const upgrade: GameCommand = {
            type: 'site_build',
            systemId: p.home,
            bodySlot: structure.slot,
            facility: 'dyson',
          };
          await issue(upgrade);
          await admin.conn.reducers.setClock({ paused: false, speed: 4 });
          await until(() => !!site().building);
          await admin.conn.reducers.setClock({ paused: true, speed: 4 });
          if (level === 2) {
            const minerals = gameView(a)!.me.resources.minerals;
            await issue({ type: 'site_cancel', siteId: structure.objectId });
            assert.equal(site().level, 1);
            assert.equal(
              gameView(a)!.me.resources.minerals,
              minerals + facilitySpec('dyson', 1).cost.minerals / 2,
            );
            await issue(upgrade);
          }
        }
        const snapshot = structuredClone(site());
        const joined = await connect(database, { token: a.token });
        clients.push(joined);
        await subscribe(joined.conn, GAME_QUERIES);
        assert.deepEqual(
          gameView(joined)!.sites!.find((s) => s.id === structure.objectId),
          snapshot,
        );
        await admin.conn.reducers.setClock({ paused: false, speed: 4 });
        await until(() => site().level === level && !site().building);
        await admin.conn.reducers.setClock({ paused: true, speed: 4 });
        assert.equal(site().id, structure.objectId);
        const view = gameView(a)!;
        assert.equal(
          view.me.installationIncome!.energy,
          [5, 35, 95][level - 1] *
            Math.min(1, ...(view.crises || []).map((c) => crisisProductionFactor(c.phase, c.shielded))),
        );
      }
      await assert.rejects(
        issue({ type: 'site_build', systemId: p.home, bodySlot: structure.slot, facility: 'dyson' }),
      );
      const beforeIncome = gameView(a)!;
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => gameView(a)!.tick >= beforeIncome.tick + 8);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert(
        gameView(a)!.me.resources.energy >= beforeIncome.me.resources.energy + 45,
        'completed Dyson collectors credit actual energy, including the strongest crisis penalty',
      );
      assert.equal(gameView(b)!.sites!.length, 0, 'foreign construction remains private');
      const star = bodies().find((b) => b.slot === 0)!;
      const beforeCollapse = gameView(a)!;
      const planets = bodies().filter((b) => b.kind === 'planet' && b.environment);
      const sectors = beforeCollapse.systems.find((s) => s.id === p.home)!.colony!.sectors;
      const collapse: GameCommand = {
        type: 'stellar_collapse',
        systemId: p.home,
        objectId: star.objectId,
        revision: star.revision,
      };
      await assert.rejects(issue({ ...collapse, revision: star.revision + 1 }));
      await assert.rejects(b.conn.reducers.gameCommand({ commandJson: JSON.stringify(collapse) }));
      await issue(collapse);
      await assert.rejects(issue(collapse));
      const project = () => gameView(a)!.stellarProjects?.[0];
      const first = project()!;
      assert(first && !gameView(b)!.stellarProjects?.length, 'stellar projects remain private');
      await delay(350);
      assert.equal(project()!.remaining, first.remaining, 'pause freezes stellar work');
      const paid = gameView(a)!.me.resources.data;
      await issue({ type: 'stellar_cancel', jobId: first.id });
      assert.equal(gameView(a)!.me.resources.data, paid + STELLAR_COLLAPSE.data / 2);
      await assert.rejects(issue({ type: 'stellar_cancel', jobId: first.id }));
      assert.equal(bodies().find((b) => b.slot === 0)!.revision, star.revision);
      await issue(collapse);
      const rejoined = await connect(database, { token: a.token });
      clients.push(rejoined);
      await subscribe(rejoined.conn, GAME_QUERIES);
      assert.deepEqual(gameView(rejoined)!.stellarProjects, gameView(a)!.stellarProjects);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => !!project() && project()!.remaining < 25);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const planet = bodies().find((b) => b.main)!;
      await a.conn.reducers.startTerraforming({
        objectId: planet.objectId,
        revision: planet.revision,
        target: 'desert',
      });
      const data = gameView(a)!.me.resources.data;
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => !project());
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const after = gameView(a)!,
        remnant = bodies().find((b) => b.slot === 0)!;
      assert.equal(remnant.objectId, star.objectId);
      assert.equal(remnant.stellar!.family, 'neutron');
      const changedSystem = after.systems.find((s) => s.id === p.home)!;
      assert.equal(changedSystem.class, 'NS');
      assert.equal(changedSystem.color, remnant.color);
      assert.equal(changedSystem.owner, p.id);
      assert.deepEqual(changedSystem.colony!.sectors, sectors);
      assert.deepEqual(after.links, beforeCollapse.links);
      for (const original of planets) {
        const frozen = bodies().find((b) => b.objectId === original.objectId)!;
        assert.equal(frozen.environment, 'arctic');
        assert.equal(frozen.orbit, original.orbit);
      }
      assert(!bodies().some((b) => b.megastructure === 'dyson'));
      assert(!after.sites!.some((s) => ['dyson', 'solar'].includes(s.facility)));
      assert(after.me.resources.data >= data + STELLAR_COLLAPSE.reward);
      await assert.rejects(a.conn.reducers.cancelTerraforming({ objectId: planet.objectId }));
      await assert.rejects(issue({ type: 'site_build', systemId: p.home, bodySlot: 0, facility: 'solar' }));
      await assert.rejects(issue(place));
      await assert.rejects(issue(collapse));
      const reconnectDetail = new SystemSubscription(rejoined);
      await reconnectDetail.focus([...a.conn.db.myGamePlayer.iter()][0].homeId);
      assert.deepEqual(objectBodies(rejoined.conn.db.focusedSystemObjects.iter()), bodies());
      assert.equal(gameView(rejoined)!.systems.find((s) => s.id === p.home)!.class, 'NS');
      await reconnectDetail.focus(0);
      await detail.focus(0);
    } finally {
      clients.forEach((c) => c.conn.disconnect());
      cli(['delete', database, '--server', 'http://127.0.0.1:3100', '--yes']);
    }
  },
);
