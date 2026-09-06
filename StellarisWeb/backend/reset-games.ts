import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { cli } from './tool.mjs';

// Explicit development reset. Only registered game databases; never template libraries or lab worlds.
const path = resolve(process.env.DATA_DIR || 'data', 'native-sectors.json');
const server = process.env.SPACETIME_HTTP || 'http://127.0.0.1:3100';
let entries: { code: string; database: string }[] = JSON.parse(await readFile(path, 'utf8'));
if (
  !Array.isArray(entries) ||
  entries.some((e) => !/^[A-F0-9]{6}$/.test(e.code) || !/^singularity-game-[a-z0-9-]+$/.test(e.database))
)
  throw new Error('Invalid native sector registry; nothing deleted.');
const count = entries.length;
for (const entry of [...entries]) {
  cli(['delete', entry.database, '--server', server, '--yes']);
  entries = entries.filter((e) => e.database !== entry.database);
  await writeFile(path, JSON.stringify(entries, null, 2) + '\n');
  console.log(`Deleted old galaxy ${entry.code}.`);
}
console.log(`${count} old galaxies deleted. Create a new expedition; template libraries are retained.`);
