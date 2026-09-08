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
import { RESOURCE_IDS } from '../../shared/resources';
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
        env: {
          ...process.env,
          PORT: '0',
          HOST: '127.0.0.1',
          DATA_DIR: directory,
          ADMIN_PANEL_TOKEN: 'gateway-test-admin',
        },
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
      const available = await fetch(`http://127.0.0.1:${port}/api/galaxies/${ready.code}`);
      assert.equal(available.status, 200);
      assert.deepEqual(await available.json(), { exists: true });
      const missingCode = ready.code === 'FFFFFF' ? '000000' : 'FFFFFF';
      const missing = await fetch(`http://127.0.0.1:${port}/api/galaxies/${missingCode}`);
      assert.equal(missing.status, 404);
      assert.deepEqual(await missing.json(), { exists: false });
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
      assert.deepEqual(before.me.empire!.design.flag, ownLibrary.library.empires[0].flag);
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
      assert.deepEqual(gameView(resumed)!.me.research, before.me.research);
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
      const adminUrl = `http://127.0.0.1:${port}/api/admin/servers`;
      const adminHeaders = { Authorization: 'Bearer gateway-test-admin', 'Content-Type': 'application/json' };
      assert.equal((await fetch(adminUrl)).status, 401);
      const overview = await (await fetch(adminUrl, { headers: adminHeaders })).json();
      assert.equal(overview.servers.length, 1);
      assert.equal(overview.servers[0].players.length, 2);
      assert.equal(overview.servers[0].status, 'paused');
      assert(!JSON.stringify(overview).includes(registry[0].creationKey));
      const readMatch = async () => {
        const response = await fetch(`${adminUrl}/${ready.code}`, { headers: adminHeaders });
        assert.equal(response.status, 200, await response.clone().text());
        return response.json();
      };
      const detail = await readMatch();
      assert.equal(detail.systems.length, 400);
      assert.equal(detail.lanes.length, 960);
      assert.equal(detail.empires.length, 2);
      assert.equal(detail.empires[0].colonies.length, 1);
      assert.deepEqual(Object.keys(detail.empires[0].resources), RESOURCE_IDS);
      assert.deepEqual(Object.keys(detail.empires[0].colonies[0].monthlyProduction), RESOURCE_IDS);
      assert(Object.values(detail.empires[0].colonies[0].monthlyProduction).every(Number.isFinite));
      assert(
        detail.empires[0].colonies[0].population > 0 && detail.empires[0].colonies[0].population < 100,
        'population is expressed in game billions, not fixed-point units',
      );
      assert.equal(detail.fleets.length, 6);
      assert(!JSON.stringify(detail).includes(registry[0].creationKey));
      const action = (body: unknown) =>
        fetch(`${adminUrl}/${ready.code}`, {
          method: 'POST',
          headers: adminHeaders,
          body: JSON.stringify(body),
        });
      assert.equal((await action({ action: 'clock', paused: false, speed: 9 })).status, 400);
      assert.equal((await action({ action: 'clock', paused: false, speed: 2 })).status, 200);
      await until(() => !gameView(resumed)!.paused && gameView(resumed)!.speed === 2);
      assert.equal((await action({ action: 'clock', paused: true, speed: 1 })).status, 200);
      await until(() => gameView(resumed)!.paused);
      const target = detail.empires[0];
      const beforeResources = (await readMatch()).empires[0].resources.energy;
      const grant = { action: 'resources', empireId: target.id, resource: 'energy', amount: 100 };
      const denied = await fetch(`http://127.0.0.1:3100/v1/database/${ready.database}/call/administer_game`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${a.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify([JSON.stringify(grant)]),
      });
      assert(!denied.ok, 'ordinary player cannot call admin reducer');
      assert.equal((await action({ ...grant, amount: 100001 })).status, 400);
      assert.equal((await action(grant)).status, 200);
      assert.equal((await readMatch()).empires[0].resources.energy, beforeResources + 100);
      assert.equal((await action({ ...grant, amount: -100000 })).status, 502);
      assert.equal(
        (await readMatch()).empires[0].resources.energy,
        beforeResources + 100,
        'rejected booking is atomic',
      );
      const secondResumed = await connect(ready.database, { uri: `ws://127.0.0.1:${port}`, token: b.token });
      clients.push(secondResumed);
      const nextHost = detail.empires.find((e: { host: boolean }) => !e.host);
      assert.equal((await action({ action: 'host', empireId: nextHost.id })).status, 200);
      assert.equal((await readMatch()).empires.find((e: { host: boolean }) => e.host).id, nextHost.id);
      assert.equal((await action({ action: 'add_ai' })).status, 200);
      const withAi = await readMatch();
      assert.equal(withAi.empires.length, 3);
      assert.equal(withAi.empires.filter((e: { ai: boolean }) => e.ai).length, 1);
      assert.equal(
        (await action({ action: 'host', empireId: withAi.empires.find((e: { ai: boolean }) => e.ai).id }))
          .status,
        502,
      );
      assert.equal((await action({ action: 'delete', confirmation: 'WRONG' })).status, 400);
      const templatesBefore = await readFile(join(directory, 'empire-libraries.json'), 'utf8');
      clients.forEach((c) => c.conn.disconnect());
      assert.equal((await action({ action: 'delete', confirmation: ready.code })).status, 200);
      assert.deepEqual(JSON.parse(await readFile(join(directory, 'native-sectors.json'), 'utf8')), []);
      assert.equal(await readFile(join(directory, 'empire-libraries.json'), 'utf8'), templatesBefore);
      assert.equal((await (await fetch(adminUrl, { headers: adminHeaders })).json()).servers.length, 0);
    } finally {
      clients.forEach((c) => c.conn.disconnect());
      sockets.forEach((s) => s.terminate());
      await stop();
    }
  },
);
