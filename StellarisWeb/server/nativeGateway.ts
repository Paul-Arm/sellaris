import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { readFile, rename, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { connect } from '../backend/client';
import { adminToken } from '../backend/admin';
import { cli } from '../backend/tool.mjs';
import type { TemplateSnapshot } from '../shared/empires';
import { createGalaxy } from '../shared/galaxy';
import { parseGalaxySettings, type GalaxySettings } from '../shared/galaxySettings';

interface Entry {
  code: string;
  database: string;
  migrationKey: string;
  status?: 'provisioning' | 'ready';
  galaxy?: GalaxySettings;
}
export class NativeGateway {
  private entries = new Map<string, Entry>();
  private tail: Promise<unknown> = Promise.resolve();
  private file: string;
  constructor(directory: string) {
    this.file = resolve(directory, 'native-sectors.json');
  }
  get size() {
    return this.entries.size;
  }
  async load() {
    try {
      const rows = JSON.parse(await readFile(this.file, 'utf8'));
      if (!Array.isArray(rows)) throw new Error('Invalid native sector registry');
      for (const row of rows) {
        if (
          !/^[A-F0-9]{6}$/.test(row.code) ||
          !/^singularity-game-[a-z0-9-]+$/.test(row.database) ||
          typeof row.migrationKey !== 'string'
        )
          throw new Error('Invalid native sector registry entry');
        const { code, database, migrationKey } = row;
        this.entries.set(code, {
          code,
          database,
          migrationKey,
          status: row.status || 'ready',
          galaxy: parseGalaxySettings(row.galaxy),
        });
      }
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== 'ENOENT') throw e;
    }
    // Retry interrupted creation with its durable database name and bootstrap key.
    for (const entry of this.entries.values())
      if (entry.status === 'provisioning') await this.provision(entry);
  }
  private exclusive<T>(fn: () => Promise<T>): Promise<T> {
    const work = this.tail.catch(() => {}).then(fn);
    this.tail = work;
    return work;
  }
  private async save() {
    await writeFile(`${this.file}.tmp`, JSON.stringify([...this.entries.values()]), { mode: 0o600 });
    await rename(`${this.file}.tmp`, this.file);
  }
  private async provision(entry: Entry): Promise<Entry> {
    if (entry.status === 'ready') return entry;
    cli([
      'publish',
      entry.database,
      '--server',
      process.env.SPACETIME_HTTP || 'http://127.0.0.1:3100',
      '--js-path',
      'spacetimedb/dist/bundle.js',
      '--yes=skip-login',
    ]);
    const admin = await connect(entry.database, { uri: process.env.SPACETIME_WS, token: adminToken() });
    try {
      await admin.conn.reducers.initializeGame({
        code: entry.code,
        seed: parseInt(entry.code, 16),
        sourceJson: JSON.stringify(createGalaxy(entry.code, parseInt(entry.code, 16), entry.galaxy)),
        migrationKey: entry.migrationKey,
      });
    } finally {
      admin.conn.disconnect();
    }
    const ready = { ...entry, status: 'ready' as const };
    this.entries.set(entry.code, ready);
    await this.save();
    return ready;
  }
  async enter(options: { code?: string; template: TemplateSnapshot; galaxy?: unknown }) {
    const galaxy = options.code === undefined ? parseGalaxySettings(options.galaxy) : undefined;
    return this.exclusive(async () => {
      let code = options.code?.trim().toUpperCase();
      let entry: Entry;
      if (options.code !== undefined) {
        if (!code || !/^[A-F0-9]{6}$/.test(code)) throw new Error('Ungültiger Raumcode.');
        const existing = this.entries.get(code);
        if (!existing) throw new Error('Galaxie nicht gefunden.');
        entry = existing;
      } else {
        if (this.entries.size >= 64) throw new Error('Kapazität von 64 Galaxien erreicht.');
        do {
          code = randomBytes(3).toString('hex').toUpperCase();
        } while (this.entries.has(code));
        const key = createHash('sha256').update(code).digest('hex');
        entry = {
          code,
          database: `singularity-game-${code.toLowerCase()}-${key.slice(0, 8)}`,
          migrationKey: key,
          status: 'provisioning',
          galaxy,
        };
        this.entries.set(code, entry);
        await this.save();
      }
      entry = await this.provision(entry);
      const ticket = randomBytes(32).toString('hex');
      const admin = await connect(entry.database, { uri: process.env.SPACETIME_WS, token: adminToken() });
      try {
        await admin.conn.reducers.reserveGameSeat({
          ticket,
          externalId: randomUUID(),
          templateJson: JSON.stringify(options.template),
        });
      } finally {
        admin.conn.disconnect();
      }
      return { type: 'native_ready', code: entry.code, database: entry.database, ticket };
    });
  }
  async flush() {
    await this.tail.catch(() => {});
  }
}
