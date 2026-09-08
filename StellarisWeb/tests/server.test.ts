import { VERSION } from '../shared/game';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { WebSocket } from 'ws';

test(
  'gateway rejects retired world commands and never restores or writes Node game saves',
  { timeout: 30000 },
  async () => {
    const dataDir = await mkdtemp(join(tmpdir(), 'singularity-test-'));
    await writeFile(join(dataDir, 'sectors.json'), 'invalid retired file');
    const child = spawn(process.execPath, ['--import', 'tsx', 'server/index.ts'], {
      env: { ...process.env, PORT: '0', HOST: '127.0.0.1', DATA_DIR: dataDir },
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });
    let output = '';
    child.stdout.on('data', (d) => (output += d));
    child.stderr.on('data', (d) => (output += d));
    const sockets: WebSocket[] = [];
    try {
      await until(() => output.includes('server on'), 8000).catch((error) => {
        throw new Error(`${error.message}\n${output}`);
      });
      const port = Number(output.match(/server on http:\/\/localhost:(\d+)/)![1]);
      const open = async () => {
        const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
        sockets.push(ws);
        const messages: any[] = [];
        ws.on('message', (d) => messages.push(JSON.parse(d.toString())));
        await new Promise<void>((resolve, reject) => {
          ws.once('open', resolve);
          ws.once('error', reject);
        });
        return { ws, messages, send: (msg: unknown) => ws.send(JSON.stringify(msg)) };
      };
      const a = await open();
      for (const type of ['resume', 'command']) {
        a.send({ type, code: 'ABCDEF', token: 'obsolete', requestId: type });
        await until(() => a.messages.some((m) => m.requestId === type && m.type === 'error'));
      }
      a.send({ type: 'join', code: '', requestId: 'empty' });
      await until(() => a.messages.some((m) => m.requestId === 'empty' && m.type === 'error'));
      const health = (await (await fetch(`http://127.0.0.1:${port}/api/health`)).json()) as any;
      assert.equal(health.version, VERSION);
      assert.equal(health.backend, 'spacetimedb');
      assert.equal(health.rooms, 0);
      assert(!a.messages.some((m) => ['state', 'joined'].includes(m.type)));
      assert(!(await readdir(dataDir)).includes('native-imports'));
    } finally {
      for (const ws of sockets) ws.terminate();
      child.kill();
    }
  },
);
async function until(predicate: () => boolean | Promise<boolean>, timeout = 4000) {
  const start = Date.now();
  while (!(await predicate())) {
    if (Date.now() - start > timeout) throw new Error('Timed out waiting for multiplayer state');
    await new Promise((r) => setTimeout(r, 40));
  }
}
