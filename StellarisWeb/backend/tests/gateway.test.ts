import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdtemp, readFile, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { WebSocket } from 'ws';
import { connect, subscribe, type Client } from '../client';
import { GAME_QUERIES, gameView } from '../game-client';
import { flagForEmpire } from '../../shared/flags';
async function until(check: () => boolean, timeout = 10000) {
  const end = Date.now() + timeout;
  while (!check()) {
    assert(Date.now() < end, 'gateway operation timed out');
    await delay(40);
  }
}

test(
  'native-only gateway creates a galaxy, proxies private identities and preserves games across restart',
  { timeout: 45000 },
  async () => {
    const directory = await mkdtemp(join(tmpdir(), 'singularity-native-gateway-'));
    let child: ChildProcess,
      port = 0;
    const sockets: WebSocket[] = [],
      clients: Client[] = [];
    const start = async () => {
      let output = '';
      child = spawn(process.execPath, ['--import', 'tsx', 'server/index.ts'], {
        env: { ...process.env, PORT: '0', HOST: '127.0.0.1', DATA_DIR: directory },
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
      });
      child.stdout?.on('data', (d) => (output += String(d)));
      child.stderr?.on('data', (d) => (output += String(d)));
      await until(() => output.includes('server on'));
      port = Number(output.match(/server on http:\/\/localhost:(\d+)/)![1]);
    };
    const stop = async () => {
      if (child.exitCode !== null) return;
      await new Promise<void>((resolve) => {
        child.once('exit', () => resolve());
        child.kill();
      });
    };
    const open = async () => {
      const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
      sockets.push(ws);
      const messages: any[] = [];
      ws.on('message', (d) => messages.push(JSON.parse(String(d))));
      await new Promise<void>((resolve, reject) => {
        ws.once('open', resolve);
        ws.once('error', reject);
      });
      return { ws, messages, send: (m: unknown) => ws.send(JSON.stringify(m)) };
    };
    try {
      await start();
      const lobby = await open();
      lobby.send({ type: 'library_open' });
      await until(() => lobby.messages.some((m) => m.type === 'library'));
      const ownLibrary = lobby.messages.find((m) => m.type === 'library');
      lobby.send({
        type: 'create',
        templateId: ownLibrary.library.empires[0].id,
        galaxy: { type: 'ring', systems: 401, hyperlaneDensity: 'dense' },
        requestId: 'invalid-galaxy',
      });
      await until(() => lobby.messages.some((m) => m.requestId === 'invalid-galaxy'));
      assert.equal(lobby.messages.find((m) => m.requestId === 'invalid-galaxy').type, 'error');
      const galaxy = { type: 'ring', systems: 400, hyperlaneDensity: 'dense' };
      lobby.send({ type: 'create', templateId: ownLibrary.library.empires[0].id, galaxy });
      await until(() => lobby.messages.some((m) => m.type === 'native_ready'));
      const ready = lobby.messages.find((m) => m.type === 'native_ready');
      const a = await connect(ready.database, { uri: `ws://127.0.0.1:${port}` });
      clients.push(a);
      await a.conn.reducers.redeemGameSeat({ ticket: ready.ticket });
      await subscribe(a.conn, GAME_QUERIES);
      await a.conn.reducers.gameCommand({ commandJson: JSON.stringify({ type: 'pause' }) });
      await a.conn.reducers.gameCommand({
        commandJson: JSON.stringify({ type: 'research', tech: 'extraction' }),
      });
      const before = gameView(a)!;
      assert.equal(before.systems.length, 400);
      assert.equal(before.links.length, 960);
      const scale = Math.sqrt(400 / 1000) * 0.4 + 0.6;
      assert(
        before.systems.every(
          (s) => Math.hypot((s.x - 800) / (720 * scale), (s.y - 525) / (440 * scale)) >= 0.479,
        ),
      );
      assert.equal(before.me.name, ownLibrary.library.empires[0].name);
      assert.deepEqual(before.me.empire!.design.flag, flagForEmpire(ownLibrary.library.empires[0]));
      const peer = await open();
      peer.send({ type: 'library_open' });
      await until(() => peer.messages.some((m) => m.type === 'library'));
      const library = peer.messages.find((m) => m.type === 'library').library;
      peer.send({ type: 'join', code: ready.code, native: true, templateId: library.empires[0].id });
      await until(() => peer.messages.some((m) => m.type === 'native_ready'));
      const second = peer.messages.find((m) => m.type === 'native_ready');
      assert.equal(second.database, ready.database);
      const b = await connect(second.database, { uri: `ws://127.0.0.1:${port}` });
      clients.push(b);
      await b.conn.reducers.redeemGameSeat({ ticket: second.ticket });
      await subscribe(b.conn, GAME_QUERIES);
      await until(() => gameView(a)!.players.length === 2);
      assert.notEqual(gameView(a)!.me.id, gameView(b)!.me.id);
      assert.equal(b.conn.db.fleetShips.count(), 0n);
      await delay(200);
      assert(
        !lobby.messages.some((m) => m.type === 'state'),
        'gateway sends no world snapshots during native play',
      );
      await stop();
      await start();
      const resumed = await connect(ready.database, { uri: `ws://127.0.0.1:${port}`, token: a.token });
      clients.push(resumed);
      await subscribe(resumed.conn, GAME_QUERIES);
      assert.equal(resumed.identity, a.identity);
      assert.equal(gameView(resumed)!.me.research!.remaining, before.me.research!.remaining);
      assert.equal(gameView(resumed)!.me.id, before.me.id);
      assert.deepEqual(gameView(resumed)!.me.resources, before.me.resources);
      assert.equal(gameView(resumed)!.players.length, 2);
      assert.deepEqual(
        gameView(resumed)!.systems.map((s) => [s.id, s.x, s.y]),
        before.systems.map((s) => [s.id, s.x, s.y]),
      );
      assert.deepEqual(gameView(resumed)!.links, before.links);
      const registry = JSON.parse(await readFile(join(directory, 'native-sectors.json'), 'utf8'));
      assert.equal(registry.length, 1);
      assert.equal(registry[0].database, ready.database);
      assert.deepEqual(registry[0].galaxy, galaxy);
      assert(!(await readdir(directory)).includes('sectors.json'));
      assert(!(await readdir(directory)).includes('native-imports'));
    } finally {
      clients.forEach((c) => c.conn.disconnect());
      sockets.forEach((s) => s.terminate());
      await stop();
    }
  },
);
