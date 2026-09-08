import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { cli } from '../tool.mjs';
import { adminToken } from '../admin';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { createGame, addPlayer, type GameCommand } from '../../shared/game';
async function until(check: () => boolean) {
  const end = Date.now() + 65000;
  while (!check()) {
    assert(Date.now() < end, 'event core timeout');
    await delay(40);
  }
}
test(
  'event core persists private projects, validates ownership/revisions/costs, and advances once across pause and reconnect',
  { timeout: 100000 },
  async () => {
    const database = `singularity-game-events-${Date.now()}`;
    cli([
      'publish',
      database,
      '--server',
      'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const source = createGame('E0E001'),
      p = addPlayer(source, 'owner', 'Owner'),
      other = addPlayer(source, 'other', 'Other');
    source.paused = true;
    p.resources = { energy: 0, minerals: 1000, data: 1000 };
    const admin = await connect(database, { token: adminToken() }),
      clients: Client[] = [admin];
    try {
      await admin.conn.reducers.initializeGame({
        code: source.code,
        seed: 42,
        sourceJson: JSON.stringify(source),
        creationKey: 'events',
      });
      for (const player of [p, other]) {
        const c = await connect(database);
        clients.push(c);
        const ticket = randomBytes(32).toString('hex');
        await admin.conn.reducers.reserveGameSeat({ ticket, externalId: player.id, templateJson: '' });
        await c.conn.reducers.redeemGameSeat({ ticket });
        await subscribe(c.conn, GAME_QUERIES);
      }
      const a = clients[1],
        b = clients[2],
        view = () => gameView(a)!,
        item = () => view().situations!.find((s) => s.definitionId === 'cartography')!;
      const issue = (c: Client, cmd: GameCommand) =>
        c.conn.reducers.gameCommand({ commandJson: JSON.stringify(cmd) });
      assert.equal(item().state.status, 'available');
      assert(!gameView(b)!.situations!.some((s) => s.id === item().id));
      const ack = { type: 'situation_ack' as const, id: item().id, notice: item().state.notice };
      await assert.rejects(issue(b, ack));
      await issue(a, ack);
      await issue(a, ack);
      assert.equal(item().state.seen, ack.notice);

      const anon = await connect(database);
      clients.push(anon);
      await subscribe(anon.conn, ['SELECT * FROM my_situations']);
      assert.equal(anon.conn.db.mySituations.count(), 0n);
      const start = { type: 'situation_start' as const, id: item().id, revision: item().state.revision };
      await assert.rejects(issue(b, start));
      await assert.rejects(issue(a, start));
      assert.equal(item().state.status, 'available');
      // A private, paid trade supplies energy through a normal core transaction.
      await issue(b, {
        type: 'offer_treaty',
        empireId: p.id,
        kind: 'trade',
        give: { energy: 100, minerals: 0, data: 0 },
        receive: { energy: 0, minerals: 1, data: 0 },
      });
      await until(() => !!view().offers?.length);
      await issue(a, { type: 'respond_treaty', treatyId: view().offers![0].id, accept: true });
      const before = view().me.resources.energy;
      await issue(a, start);
      assert.equal(item().state.status, 'active');
      assert.equal(view().me.resources.energy, before - 50);
      await assert.rejects(issue(a, start));
      const snapshot = structuredClone(item());
      await delay(300);
      assert.deepEqual(item(), snapshot);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => item().state.progress > 3);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      await issue(a, { type: 'situation_pause', id: item().id, revision: item().state.revision });
      const paused = structuredClone(item());
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await delay(400);
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      assert.deepEqual(item(), paused);
      const rejoined = await connect(database, { token: a.token });
      clients.push(rejoined);
      await subscribe(rejoined.conn, GAME_QUERIES);
      assert.deepEqual(gameView(rejoined)!.situations, view().situations);
      await issue(a, { type: 'situation_resume', id: item().id, revision: item().state.revision });
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => item().state.status === 'decision');
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      await issue(a, ack);
      assert(item().state.seen < item().state.notice, 'an old acknowledgement cannot hide a new phase');
      const choice = {
        type: 'situation_choice' as const,
        id: item().id,
        revision: item().state.revision,
        choice: 'careful',
      };
      await assert.rejects(issue(a, { ...choice, choice: 'invalid' }));
      await assert.rejects(issue(b, choice));
      await issue(a, choice);
      await assert.rejects(issue(a, choice));
      assert.equal(item().state.stage, 2);
      await admin.conn.reducers.setClock({ paused: false, speed: 4 });
      await until(() => item().state.status === 'completed');
      await admin.conn.reducers.setClock({ paused: true, speed: 4 });
      const complete = structuredClone(item());
      await assert.rejects(
        issue(a, { type: 'situation_start', id: item().id, revision: item().state.revision }),
      );
      assert.deepEqual(item(), complete);
    } finally {
      clients.forEach((c) => c.conn.disconnect());
      cli(['delete', database, '--server', 'http://127.0.0.1:3100', '--yes']);
    }
  },
);
