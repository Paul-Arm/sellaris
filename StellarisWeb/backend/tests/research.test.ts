import { categoryIncome } from './economy-helpers';
import { ECONOMY_MONTH_DAYS, monthsDue } from '../../shared/economy';
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { adminToken } from '../admin';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { addPlayer, createGame, income, type GameCommand } from '../../shared/game';
import { RESOURCE_IDS } from '../../shared/resources';
import { terraformWork } from '../../shared/terraforming';
import { objectBodies } from '../../shared/systemObjects';
import { SystemSubscription } from '../system-subscription';
import { researchAllocation, TECHS } from '../../shared/research';
import { baseIncome } from '../../shared/colonies';

async function until(check: () => boolean, timeout = 40000) {
  const end = Date.now() + timeout;
  while (!check()) {
    assert(Date.now() < end, 'research timeout');
    await delay(60);
  }
}

test(
  'native Compute budgets persist, pay boosted income and retime shared Terraforming without losing work',
  { timeout: 60000 },
  async () => {
    const database = `singularity-compute-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const source = createGame('C010A1'),
      p = addPlayer(source, 'a', 'Compute'),
      other = addPlayer(source, 'b', 'Other');
    source.paused = true;
    p.resources = { energy: 9000, minerals: 9000, data: 9000, unity: 0 };
    p.techs = ['terraforming'];
    p.empire!.economyModifiers = [{ id: 'capacity', name: 'Capacity', category: 'compute', factor: 10 }];
    for (const system of source.systems)
      for (const district of system.colony?.sectors.flatMap((s) => s.districts) ?? [])
        if (district.building === 'habitat') district.enabled = false;
    const clients: Client[] = [],
      admin = await connect(database, { token: adminToken() });
    clients.push(admin);
    try {
      await admin.conn.reducers.initializeGame({
        code: source.code,
        seed: 42,
        sourceJson: JSON.stringify(source),
        creationKey: 'compute',
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
        view = () => gameView(a)!;
      const issue = (cmd: GameCommand) => a.conn.reducers.gameCommand({ commandJson: JSON.stringify(cmd) });
      const initial = income(view(), view().me);
      await issue({ type: 'compute_allocation', use: 'production', percent: 50 });
      await issue({ type: 'compute_allocation', use: 'terraforming', percent: 25 });
      const budget = structuredClone(view().me.research);
      await assert.rejects(issue({ type: 'compute_allocation', use: 'production', percent: 51 }));
      await assert.rejects(issue({ type: 'compute_allocation', use: 'unity' as never, percent: 1 }));
      assert.deepEqual(view().me.research, budget);
      assert.equal(gameView(b)!.me.research.production, 0);
      const expected = income(view(), view().me);
      assert(expected.energy > initial.energy);
      assert.equal(expected.unity, initial.unity);
      const focus = new SystemSubscription(a);
      await focus.focus([...a.conn.db.myGamePlayer.iter()][0].homeId);
      const bodies = objectBodies(a.conn.db.focusedSystemObjects.iter())
        .filter((body) => body.kind === 'planet' && body.environment)
        .slice(0, 2);
      assert.equal(bodies.length, 2);
      for (const body of bodies)
        await a.conn.reducers.startTerraforming({
          objectId: body.objectId,
          revision: body.revision,
          target: body.environment === 'continental' ? 'ocean' : 'continental',
        });
      const projects = () => [...a.conn.db.myTerraformProjects.iter()];
      assert.equal(projects().length, 2);
      assert.equal(projects()[0].rate, projects()[1].rate);
      assert(projects()[0].rate > 1);
      assert.equal(b.conn.db.myTerraformProjects.count(), 0n);
      await assert.rejects(b.conn.reducers.cancelTerraforming({ objectId: bodies[0].objectId }));
      const stock = { ...view().me.resources };
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => view().me.resources.unity > stock.unity, 15000);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      for (const resource of RESOURCE_IDS)
        assert(
          Math.abs(view().me.resources[resource] - stock[resource] - expected[resource]) < 1e-6,
          resource,
        );
      const before = projects()[0];
      await issue({ type: 'compute_allocation', use: 'terraforming', percent: 0 });
      const slowed = projects().find((row) => row.id === before.id)!;
      assert.equal(slowed.rate, 1);
      assert(slowed.finishAt > before.finishAt);
      assert(Math.abs(slowed.workDone - terraformWork(before, slowed.updatedAt)) < 1e-8);
      await issue({ type: 'compute_allocation', use: 'terraforming', percent: 25 });
      const boosted = projects()[0].rate;
      await a.conn.reducers.cancelTerraforming({ objectId: bodies[1].objectId });
      assert.equal(projects().length, 1);
      assert(projects()[0].rate > boosted);
      const token = a.token;
      const persisted = structuredClone(view().me.research),
        project = projects()[0];
      await focus.focus(0);
      a.conn.disconnect();
      const reconnected = await connect(database, { token });
      clients.push(reconnected);
      await subscribe(reconnected.conn, GAME_QUERIES);
      assert.deepEqual(gameView(reconnected)!.me.research, persisted);
      assert.equal([...reconnected.conn.db.myTerraformProjects.iter()][0].finishAt, project.finishAt);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => reconnected.conn.db.myTerraformProjects.count() === 0n, 30000);
      assert(gameView(reconnected)!.log.some((entry) => entry.text.includes('terraformt')));
    } finally {
      clients.forEach((client) => client.conn.disconnect());
      cli(['delete', database, '--server', 'http://127.0.0.1:3100', '--yes']);
    }
  },
);
test(
  'native research: private programs, real synthesis, weighted compute, parking, dependencies and durable reconnect',
  { timeout: 100000 },
  async () => {
    const database = `singularity-game-research-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const source = createGame('DA7AC0'),
      p = addPlayer(source, 'a', 'Researchers'),
      other = addPlayer(source, 'b', 'Observer');
    source.paused = true;
    p.resources = { energy: 5000, minerals: 5000, data: 3000 };
    // Accelerated fixture keeps monthly dependency coverage bounded in real time.
    p.empire!.economyModifiers = [
      { id: 'test-compute', name: 'Test Compute', category: 'compute', factor: 30 },
    ];
    for (const s of source.systems)
      for (const sector of s.colony?.sectors || [])
        for (const d of sector.districts) if (d.building === 'habitat') d.enabled = false;
    const clients: Client[] = [],
      admin = await connect(database, { token: adminToken() });
    clients.push(admin);
    try {
      await admin.conn.reducers.initializeGame({
        code: source.code,
        seed: 42,
        sourceJson: JSON.stringify(source),
        creationKey: 'research',
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
        view = () => gameView(a)!;
      const issue = (cmd: GameCommand) => a.conn.reducers.gameCommand({ commandJson: JSON.stringify(cmd) });
      const initial = view();
      assert(Math.abs(initial.me.compute! - 126) < 1e-8);
      assert.equal(categoryIncome(initial, 'synthesis').data, 31.5, 'idle Compute produces real data');
      await assert.rejects(issue({ type: 'research', tech: 'quantum' }), /noch nicht entdeckt/);
      assert.equal(view().me.resources.data, initial.me.resources.data);
      await issue({ type: 'research', tech: 'computing' });
      await issue({ type: 'research', tech: 'propulsion' });
      assert.deepEqual(
        view().me.research.projects.map((p) => p.tech),
        ['computing', 'propulsion'],
      );
      assert.equal(
        view().me.resources.data,
        initial.me.resources.data - 150,
        'only available projects charged',
      );
      assert(!view().me.research.projects.some((p) => p.tech === 'quantum'));
      assert.equal(gameView(b)!.me.research.projects.length, 0);
      assert.equal(b.conn.db.myResearch.count(), 1n);
      const anon = await connect(database);
      clients.push(anon);
      await subscribe(anon.conn, ['SELECT * FROM my_research']);
      assert.equal(anon.conn.db.myResearch.count(), 0n);
      const beforeInvalid = structuredClone(view().me.research);
      await assert.rejects(issue({ type: 'research', tech: 'computing' }), /Bereits/);
      await assert.rejects(issue({ type: 'research_weight', tech: 'quantum', weight: 6 }));
      await assert.rejects(issue({ type: 'compute_allocation', use: 'synthesis', percent: 101 }));
      assert.deepEqual(view().me.research, beforeInvalid);
      await issue({ type: 'compute_allocation', use: 'synthesis', percent: 0 });
      await issue({ type: 'research_weight', tech: 'propulsion', weight: 3 });
      const before = view().tick;
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(
        () =>
          view().tick >= before + ECONOMY_MONTH_DAYS &&
          (view().me.research.projects.find((p) => p.tech === 'computing')?.done ?? 0) > 0,
      );
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const program = view().me.research,
        computer = program.projects.find((p) => p.tech === 'computing')!,
        drive = program.projects.find((p) => p.tech === 'propulsion')!;
      assert(computer.done > 0);
      assert.equal(drive.done, computer.done * 3, 'priorities split actual committed work');
      assert(!program.projects.some((p) => p.tech === 'quantum'));
      await issue({ type: 'research_weight', tech: 'computing', weight: 0 });
      await issue({ type: 'compute_allocation', use: 'synthesis', percent: 100 });
      const frozen = structuredClone(view().me.research),
        data = view().me.resources.data,
        at = view().tick;
      const anchors = [...a.conn.db.myColonies.iter()],
        researchAt = [...a.conn.db.myResearch.iter()][0].updatedAt;
      await delay(500);
      assert.deepEqual(view().me.research, frozen);
      const rejoin = await connect(database, { token: a.token });
      clients.push(rejoin);
      await subscribe(rejoin.conn, GAME_QUERIES);
      assert.deepEqual(gameView(rejoin)!.me.research, frozen);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => view().tick >= at + ECONOMY_MONTH_DAYS);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      await issue({ type: 'compute_allocation', use: 'synthesis', percent: 100 });
      assert.deepEqual(view().me.research, frozen, 'synthesis uses Compute without advancing research');
      const end = view(),
        updated = [...a.conn.db.myColonies.iter()];
      const expected =
        data +
        baseIncome(end.me).data *
          (Math.floor(end.tick / ECONOMY_MONTH_DAYS) - Math.floor(at / ECONOMY_MONTH_DAYS)) +
        anchors.reduce(
          (n, c) =>
            n +
            c.monthlyProduction.data *
              monthsDue(c.lastProducedAt, updated.find((u) => u.id === c.id)!.lastProducedAt),
          0,
        ) +
        monthsDue(researchAt, [...a.conn.db.myResearch.iter()][0].updatedAt) *
          categoryIncome(end, 'synthesis').data;
      assert(
        Math.abs(end.me.resources.data - expected) < 1e-6,
        'exact synthesis payout is separate from passive data income',
      );
      await issue({ type: 'compute_allocation', use: 'synthesis', percent: 0 });
      await issue({ type: 'research_weight', tech: 'computing', weight: 5 });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => view().me.techs.includes('computing'));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert(
        Math.abs(view().me.compute! - 189) < 1e-8,
        'completed architecture increases authoritative capacity',
      );
      assert.equal(
        view().me.research.projects.some((p) => p.tech === 'computing'),
        false,
      );
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await issue({ type: 'research', tech: 'distributed' });
      await until(() => view().me.techs.includes('distributed') && view().me.techs.includes('propulsion'));
      await issue({ type: 'research', tech: 'quantum' });
      await until(() => view().me.techs.includes('quantum'));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert(view().me.techs.includes('distributed') && view().me.techs.includes('propulsion'));
      assert(Math.abs(view().me.compute! - 567) < 1e-8);
      assert.equal(view().me.research.projects.length, 0);
      assert(
        Math.abs(categoryIncome(view(), 'synthesis').data - 141.75) < 1e-8,
        'all idle Compute returns to synthesis',
      );
      assert.equal(view().log.filter((e) => e.text === `${TECHS.quantum.name} erforscht.`).length, 1);
      assert(
        Math.abs(researchAllocation(view().me.research, view().me.techs, view().me.compute!).data - 141.75) <
          1e-8,
      );
      await assert.rejects(issue({ type: 'research', tech: 'quantum' }), /Bereits/);
      const home = view().systems.find((s) => s.id === p.home)!;
      const slot = home.colony!.sectors.find((s) => s.districts.length < s.slots)!;
      await issue({
        type: 'colony_build',
        slot: slot.districts.length,
        systemId: p.home,
        sectorId: slot.id,
        building: 'datacenter',
        revision: home.colony!.revision,
      });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => !view().systems.find((s) => s.id === p.home)!.colony!.construction);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert(view().me.compute! > 567, 'staffed new data center supplies Compute');
      const built = view().systems.find((s) => s.id === p.home)!.colony!;
      const center = built.sectors.flatMap((s) => s.districts).find((d) => d.building === 'datacenter')!;
      await issue({
        type: 'colony_toggle',
        systemId: p.home,
        districtId: center.id,
        enabled: false,
        revision: built.revision,
      });
      assert(Math.abs(view().me.compute! - 567) < 1e-8, 'disabled data center immediately loses capacity');
    } finally {
      clients.forEach((c) => c.conn.disconnect());
      cli(['delete', database, '--server', 'http://127.0.0.1:3100', '--yes']);
    }
  },
);
