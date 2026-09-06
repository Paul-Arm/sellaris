import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { connect } from './client';
import { SCENARIOS, type Scenario } from './domain';

/** Only local tooling may read the CLI administrator credential; never imported into the browser. */
export function adminToken() {
  if (process.env.SPACETIME_ADMIN_TOKEN) return process.env.SPACETIME_ADMIN_TOKEN;
  const config = readFileSync(resolve('.spacetime/config/cli.toml'), 'utf8');
  const token = /^spacetimedb_token\s*=\s*"([^"\r\n]+)"/m.exec(config)?.[1];
  if (!token) throw new Error('Publish to the local server first, or set SPACETIME_ADMIN_TOKEN');
  return token;
}
export async function seedDatabase(database: string, scenario: Scenario, uri?: string) {
  const client = await connect(database, { token: adminToken(), uri });
  try {
    await client.conn.reducers.configure(scenario);
    for (let empireId = 1; empireId <= scenario.empires; empireId++) {
      for (let expectedOffset = 0; expectedOffset < scenario.shipsPerEmpire; expectedOffset += 1000) {
        await client.conn.reducers.seedShips({
          empireId,
          expectedOffset,
          count: Math.min(1000, scenario.shipsPerEmpire - expectedOffset),
        });
      }
    }
    await client.conn.reducers.activate({});
  } finally {
    client.conn.disconnect();
  }
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(import.meta.filename)) {
  const [database = 'singularity-lab', profile = 'standard'] = process.argv.slice(2);
  const scenario = SCENARIOS[profile] ?? (existsSync(profile) ? JSON.parse(readFileSync(profile, 'utf8')) : undefined);
  if (!scenario) throw new Error(`Unknown profile: ${profile}`);
  await seedDatabase(database, scenario, process.env.SPACETIME_WS);
  console.log(
    `Ready: ${database}, ${scenario.systems} systems, ${scenario.empires * scenario.shipsPerEmpire} ships.`,
  );
}
