import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { adminToken } from '../admin';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { addPlayer, createGame, type GameCommand } from '../../shared/game';
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
        migrationKey: 'research',
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
      assert.equal(initial.me.compute, 4);
      assert.equal(initial.me.synthesisIncome, 4, 'idle Compute produces real data');
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
      await assert.rejects(issue({ type: 'research_synthesis', percent: 101 }));
      assert.deepEqual(view().me.research, beforeInvalid);
      await issue({ type: 'research_synthesis', percent: 0 });
      await issue({ type: 'research_weight', tech: 'propulsion', weight: 3 });
      const before = view().tick;
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => view().tick >= before + 4);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const program = view().me.research,
        computer = program.projects.find((p) => p.tech === 'computing')!,
        drive = program.projects.find((p) => p.tech === 'propulsion')!;
      assert(computer.done > 0);
      assert.equal(drive.done, computer.done * 3, 'priorities split actual committed work');
      assert(!program.projects.some((p) => p.tech === 'quantum'));
      await issue({ type: 'research_weight', tech: 'computing', weight: 0 });
      await issue({ type: 'research_synthesis', percent: 100 });
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
      await until(() => view().tick >= at + 8);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      await issue({ type: 'research_synthesis', percent: 100 });
      assert.deepEqual(view().me.research, frozen, 'synthesis uses Compute without advancing research');
      const end = view(),
        updated = [...a.conn.db.myColonies.iter()];
      const expected =
        data +
        baseIncome(end.me).data * (Math.floor(end.tick / 4) - Math.floor(at / 4)) +
        anchors.reduce(
          (n, c) =>
            n + c.dataRate * ((updated.find((u) => u.id === c.id)!.lastProducedAt - c.lastProducedAt) / 4),
          0,
        ) +
        ([...a.conn.db.myResearch.iter()][0].updatedAt - researchAt);
      assert(
        Math.abs(end.me.resources.data - expected) < 1e-6,
        'exact synthesis payout is separate from passive data income',
      );
      await issue({ type: 'research_synthesis', percent: 0 });
      await issue({ type: 'research_weight', tech: 'computing', weight: 5 });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => view().me.techs.includes('computing'));
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.equal(view().me.compute, 6, 'completed architecture increases authoritative capacity');
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
      assert.equal(view().me.compute, 18);
      assert.equal(view().me.research.projects.length, 0);
      assert.equal(view().me.synthesisIncome, 18, 'all idle Compute returns to synthesis');
      assert.equal(view().log.filter((e) => e.text === `${TECHS.quantum.name} erforscht.`).length, 1);
      assert.equal(researchAllocation(view().me.research, view().me.techs, view().me.compute!).data, 4.5);
      await assert.rejects(issue({ type: 'research', tech: 'quantum' }), /Bereits/);
      const home = view().systems.find((s) => s.id === p.home)!;
      const slot = home.colony!.sectors.find((s) => s.districts.length < s.slots)!;
      await issue({
        type: 'colony_build',
        systemId: p.home,
        sectorId: slot.id,
        building: 'datacenter',
        revision: home.colony!.revision,
      });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => !view().systems.find((s) => s.id === p.home)!.colony!.construction);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert(view().me.compute! > 18, 'staffed new data center supplies Compute');
      const built = view().systems.find((s) => s.id === p.home)!.colony!;
      const center = built.sectors.flatMap((s) => s.districts).find((d) => d.building === 'datacenter')!;
      await issue({
        type: 'colony_toggle',
        systemId: p.home,
        districtId: center.id,
        enabled: false,
        revision: built.revision,
      });
      assert.equal(view().me.compute, 18, 'disabled data center immediately loses capacity');
    } finally {
      clients.forEach((c) => c.conn.disconnect());
      cli(['delete', database, '--server', 'http://127.0.0.1:3100', '--yes']);
    }
  },
);
