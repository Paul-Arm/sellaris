import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { NativeGateway } from '../server/nativeGateway';
import { createAdminPanel } from '../server/adminPanel';

test('admin API requires its own credential and rejects invalid and unregistered actions', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'singularity-admin-'));
  const native = new NativeGateway(dir);
  await native.load();
  const panel = createAdminPanel(native, 'test-admin-key');
  const server = createServer(async (req, res) => {
    if (!(await panel.handle(req, res))) {
      res.writeHead(404);
      res.end();
    }
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address() as { port: number };
  const url = `http://127.0.0.1:${address.port}/api/admin/servers`;
  const headers = { Authorization: 'Bearer test-admin-key', 'Content-Type': 'application/json' };
  try {
    assert.equal((await fetch(url)).status, 401);
    assert.equal((await fetch(url, { headers: { Authorization: 'Bearer wrong' } })).status, 401);
    assert.equal((await fetch(`${url}/ABCDEF`, { method: 'POST', body: '{}' })).status, 401);
    const overview = await fetch(url, { headers });
    assert.equal(overview.headers.get('cache-control'), 'no-store');
    assert.deepEqual((await overview.json()).servers, []);
    assert.equal((await fetch(`${url}/ABCDEF`, { method: 'POST', headers, body: '{' })).status, 400);
    assert.equal((await fetch(`${url}/ABCDEF`, { method: 'POST', headers, body: 'null' })).status, 400);
    assert.equal(
      (
        await fetch(`${url}/ABCDEF`, {
          method: 'POST',
          headers,
          body: JSON.stringify({ action: 'delete', confirmation: 'ABCDEF' }),
        })
      ).status,
      404,
    );
    assert.equal(
      (await fetch(`${url}/singularity-lab`, { method: 'POST', headers, body: '{}' })).status,
      404,
    );
    assert.equal(
      (await fetch(`${url}/ABCDEF`, { method: 'POST', headers, body: 'x'.repeat(5000) })).status,
      413,
    );
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

test('registry admin operations retain failed deletions, serialize changes and persist only registered removals', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'singularity-admin-registry-'));
  const file = join(dir, 'native-sectors.json');
  await writeFile(
    file,
    JSON.stringify([
      {
        code: 'ABCDEF',
        database: 'singularity-game-abcdef-test',
        migrationKey: 'private-key',
        status: 'ready',
      },
    ]),
  );
  const templates = join(dir, 'empire-libraries.json');
  await writeFile(templates, 'templates unchanged');
  const native = new NativeGateway(dir);
  await native.load();
  assert(!JSON.stringify(native.listServers()).includes('private-key'));
  await assert.rejects(
    native.administer(
      'ABCDEF',
      async () => {
        throw new Error('offline');
      },
      true,
    ),
  );
  assert.equal(native.size, 1);
  assert.equal(JSON.parse(await readFile(file, 'utf8')).length, 1);
  await assert.rejects(
    native.administer('AAAAAA', async () => assert.fail('unknown database must not execute')),
  );
  await native.administer(
    'ABCDEF',
    async (database) => assert.equal(database, 'singularity-game-abcdef-test'),
    true,
  );
  const reloaded = new NativeGateway(dir);
  await reloaded.load();
  assert.equal(reloaded.size, 0);
  assert.equal(await readFile(templates, 'utf8'), 'templates unchanged');
});
