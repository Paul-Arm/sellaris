import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { WebSocket } from 'ws';
import type { EmpireLibrary, EmpireTemplate } from '../shared/empires';
import { FLAG_PRESETS } from '../shared/flags';

async function until(predicate: () => boolean | Promise<boolean>, timeout = 8000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    if (await predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error('Timed out waiting for empire server evidence.');
}
test(
  'real clients persist private templates and isolate library updates across profiles and restarts',
  { timeout: 40000 },
  async () => {
    const dataDir = await mkdtemp(join(tmpdir(), 'empire-server-'));
    const processes: ChildProcess[] = [];
    const sockets: WebSocket[] = [];
    async function start() {
      const child = spawn(process.execPath, ['--import', 'tsx', 'server/index.ts'], {
        env: { ...process.env, PORT: '0', HOST: '127.0.0.1', DATA_DIR: dataDir },
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
      });
      processes.push(child);
      let output = '';
      child.stdout!.on('data', (data) => {
        output += data;
      });
      child.stderr!.on('data', (data) => {
        output += data;
      });
      await until(() => /server on http:\/\/localhost:\d+/.test(output));
      const port = Number(output.match(/server on http:\/\/localhost:(\d+)/)![1]);
      return { child, port };
    }
    async function open(port: number) {
      const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
      sockets.push(ws);
      const messages: any[] = [];
      ws.on('message', (data) => messages.push(JSON.parse(data.toString())));
      await new Promise<void>((resolve, reject) => {
        ws.once('open', resolve);
        ws.once('error', reject);
      });
      return { ws, messages, send: (message: unknown) => ws.send(JSON.stringify(message)) };
    }
    try {
      const first = await start();
      const a = await open(first.port);
      a.send({ type: 'library_open', requestId: 'open-a' });
      await until(() => a.messages.some((m) => m.requestId === 'open-a'));
      const profile = a.messages.find((m) => m.requestId === 'open-a');
      const library = profile.library as EmpireLibrary;
      const custom: EmpireTemplate = {
        ...library.empires[0],
        id: 'private-custom',
        revision: 0,
        name: 'Cygnus-Konvent',
        flag: FLAG_PRESETS[2].flag,
        homeworldName: 'Haven',
        systemName: 'Cygnus',
        lore: 'Only my library knows this history.',
      };
      a.send({
        type: 'library_mutate',
        requestId: 'save-a',
        mutation: { type: 'save_empire', template: custom },
      });
      await until(() => a.messages.some((m) => m.requestId === 'save-a'));
      assert.equal(a.messages.find((m) => m.requestId === 'save-a').type, 'library');
      const disk = JSON.parse(await readFile(join(dataDir, 'empire-libraries.json'), 'utf8'));
      assert.ok(disk.profiles.some((p: any) => p.library.empires.some((e: any) => e.name === custom.name)));

      const b = await open(first.port);
      for (const token of ['0'.repeat(64), 'invalid-key']) {
        const requestId = `unavailable-${token.length}`;
        b.send({ type: 'library_open', token, requestId });
        await until(() => b.messages.some((m) => m.requestId === requestId));
        const failure = b.messages.find((m) => m.requestId === requestId);
        assert.equal(failure.type, 'error');
        assert.equal(failure.code, 'LIBRARY_PROFILE_UNAVAILABLE');
        assert.equal(failure.library, undefined);
      }
      assert.deepEqual(JSON.parse(await readFile(join(dataDir, 'empire-libraries.json'), 'utf8')), disk);
      b.send({
        type: 'library_mutate',
        requestId: 'unavailable-write',
        mutation: { type: 'save_empire', template: custom },
      });
      await until(() => b.messages.some((m) => m.requestId === 'unavailable-write'));
      assert.equal(b.messages.find((m) => m.requestId === 'unavailable-write').type, 'error');
      b.send({ type: 'library_open', requestId: 'open-b' });
      await until(() => b.messages.some((m) => m.requestId === 'open-b'));
      const peerLibrary = b.messages.find((m) => m.requestId === 'open-b').library as EmpireLibrary;
      assert.notEqual(b.messages.find((m) => m.requestId === 'open-b').token, profile.token);
      assert.ok(
        JSON.parse(await readFile(join(dataDir, 'empire-libraries.json'), 'utf8')).profiles.some((p: any) =>
          p.library.empires.some((e: any) => e.name === custom.name),
        ),
      );
      assert.equal(
        peerLibrary.empires.some((e) => e.id === custom.id),
        false,
      );
      b.send({ type: 'create', templateId: custom.id, requestId: 'steal' });
      await until(() => b.messages.some((m) => m.requestId === 'steal'));
      assert.equal(b.messages.find((m) => m.requestId === 'steal').type, 'error');
      assert.equal(
        ((await (await fetch(`http://127.0.0.1:${first.port}/api/health`)).json()) as { rooms: number })
          .rooms,
        0,
      );

      const bCount = b.messages.filter((m) => m.type === 'library').length;
      a.send({
        type: 'library_mutate',
        requestId: 'rename',
        mutation: { type: 'save_empire', template: { ...custom, revision: 1, name: 'Future Cygnus' } },
      });
      await until(() => a.messages.some((m) => m.requestId === 'rename'));
      assert.equal(a.messages.find((m) => m.requestId === 'rename').type, 'library');
      assert.equal(b.messages.filter((m) => m.type === 'library').length, bCount);

      const tab = await open(first.port);
      tab.send({ type: 'library_open', token: profile.token, requestId: 'same-profile' });
      await until(() => tab.messages.some((m) => m.requestId === 'same-profile'));
      assert.equal(
        tab.messages
          .find((m) => m.requestId === 'same-profile')
          .library.empires.find((e: any) => e.id === custom.id).revision,
        2,
      );
      a.send({
        type: 'library_mutate',
        requestId: 'delete',
        mutation: { type: 'delete_empire', id: custom.id, revision: 2 },
      });
      await until(() => a.messages.some((m) => m.requestId === 'delete'));
      await until(() =>
        tab.messages
          .filter((m) => m.type === 'library')
          .at(-1)
          ?.library.empires.every((e: any) => e.id !== custom.id),
      );
      for (const socket of sockets) socket.close();
      first.child.kill();
      await new Promise((resolve) => first.child.once('exit', resolve));
      const second = await start();
      const restored = await open(second.port);
      restored.send({ type: 'library_open', token: profile.token, requestId: 'restore-library' });
      await until(() => restored.messages.some((m) => m.requestId === 'restore-library'));
      assert.equal(
        restored.messages
          .find((m) => m.requestId === 'restore-library')
          .library.empires.some((e: any) => e.id === custom.id),
        false,
      );
    } finally {
      for (const ws of sockets) ws.terminate();
      for (const child of processes) if (child.exitCode === null) child.kill();
    }
  },
);
