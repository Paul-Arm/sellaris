import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { cli } from './tool.mjs';
import { connect, subscribe } from './client';
import { adminToken } from './admin';

// Upgrade only the operator's registered games. Lab/test worlds and source saves are untouched.
const directory = resolve(process.env.DATA_DIR || 'data');
let entries: { code: string; database: string }[] = [];
try {
  entries = JSON.parse(await readFile(resolve(directory, 'native-sectors.json'), 'utf8'));
} catch (e) {
  if ((e as NodeJS.ErrnoException).code !== 'ENOENT') throw e;
}
for (const entry of entries) {
  if (!/^[A-F0-9]{6}$/.test(entry.code) || !/^singularity-game-[a-z0-9-]+$/.test(entry.database))
    throw new Error('Invalid native sector registry entry');
  const before = await connect(entry.database, { uri: process.env.SPACETIME_WS, token: adminToken() });
  let prior: { paused: boolean; speed: number };
  try {
    await subscribe(before.conn, ['SELECT * FROM clock']);
    const clock = [...before.conn.db.clock.iter()][0];
    if (!clock) throw new Error(`Missing game clock: ${entry.code}`);
    prior = { paused: clock.paused, speed: clock.speed };
    // Older module versions accept 1x even when the game itself is currently at 3x.
    await before.conn.reducers.setClock({ paused: true, speed: 1 });
  } finally {
    before.conn.disconnect();
  }
  // On update failure, leave the affected world paused for diagnosis instead of running mixed rules.
  cli([
    'publish',
    entry.database,
    '--server',
    process.env.SPACETIME_HTTP || 'http://127.0.0.1:3100',
    '--js-path',
    'spacetimedb/dist/bundle.js',
    '--yes=skip-login',
  ]);
  const after = await connect(entry.database, { uri: process.env.SPACETIME_WS, token: adminToken() });
  try {
    await after.conn.reducers.initializeDiplomacy({});
    await after.conn.reducers.initializeStories({});
    await after.conn.reducers.setClock(prior);
  } finally {
    after.conn.disconnect();
  }
  console.log(`Updated ${entry.code}; durable game data retained.`);
}
console.log(`${entries.length} registered galaxies updated.`);
