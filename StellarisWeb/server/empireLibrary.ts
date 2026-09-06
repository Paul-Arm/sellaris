import { createHash, randomBytes } from 'node:crypto';
import { readFile, rename, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import {
  mutateLibrary,
  starterLibrary,
  validateEmpireLibrary,
  type EmpireLibrary,
  type LibraryMutation,
} from '../shared/empires';

interface Profile {
  tokenHash: string;
  library: EmpireLibrary;
}
/** A persistent, private browser identity, independent of room/session tokens. */
export class EmpireLibraryStore {
  private profiles = new Map<string, Profile>();
  private pending: Promise<unknown> = Promise.resolve();
  private file: string;
  constructor(directory: string) {
    this.file = resolve(directory, 'empire-libraries.json');
  }
  async load() {
    try {
      const data = JSON.parse(await readFile(this.file, 'utf8'));
      if (data.version !== 1 || !Array.isArray(data.profiles)) throw new Error('Ungültige Bibliotheksdatei.');
      for (const profile of data.profiles) {
        if (!/^[a-f0-9]{64}$/.test(profile.tokenHash) || this.profiles.has(profile.tokenHash))
          throw new Error('Ungültiges oder doppeltes Bibliotheksprofil.');
        this.profiles.set(profile.tokenHash, {
          tokenHash: profile.tokenHash,
          library: validateEmpireLibrary(profile.library),
        });
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
    }
  }
  private serialize<T>(action: () => Promise<T>): Promise<T> {
    const task = this.pending.then(action);
    this.pending = task.catch(() => undefined);
    return task;
  }
  private async persist(profiles: Map<string, Profile>) {
    await writeFile(`${this.file}.tmp`, JSON.stringify({ version: 1, profiles: [...profiles.values()] }), {
      mode: 0o600,
    });
    await rename(`${this.file}.tmp`, this.file);
    this.profiles = profiles;
  }
  async connect(token?: unknown) {
    return this.serialize(async () => {
      if (token !== undefined && token !== null) {
        if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token))
          throw new Error('Ungültiger Bibliotheksschlüssel.');
        const key = createHash('sha256').update(token).digest('hex');
        if (!this.profiles.has(key))
          throw new Error('Bibliotheksprofil nicht gefunden. Prüfe, ob du den richtigen Server verwendest.');
        return { key, token, library: this.read(key) };
      }
      if (this.profiles.size >= 500) throw new Error('Der Server hat seine Profilkapazität erreicht.');
      const newToken = randomBytes(32).toString('hex');
      const key = createHash('sha256').update(newToken).digest('hex');
      const profiles = new Map(this.profiles);
      profiles.set(key, { tokenHash: key, library: starterLibrary() });
      await this.persist(profiles);
      return { key, token: newToken, library: this.read(key) };
    });
  }
  read(key: string): EmpireLibrary {
    const profile = this.profiles.get(key);
    if (!profile) throw new Error('Öffne zuerst deine Vorlagenbibliothek.');
    return structuredClone(profile.library);
  }
  async mutate(key: string, mutation: LibraryMutation) {
    return this.serialize(async () => {
      const library = mutateLibrary(this.read(key), mutation);
      const profiles = new Map(this.profiles);
      profiles.set(key, { tokenHash: key, library });
      await this.persist(profiles);
      return structuredClone(library);
    });
  }
  async flush() {
    await this.pending;
  }
}
